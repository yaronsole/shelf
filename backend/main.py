"""
Shelf API – Cloud Run backend
Python 3.12 / FastAPI / Firestore / Claude API
"""
from __future__ import annotations

import logging
import os
import re
import time
import uuid
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import Annotated

import anthropic
from fastapi import Depends, FastAPI, Header, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from google.cloud import firestore
from pydantic import ValidationError

from models import (
    BookOverviewRequest,
    DebugInfoResponse,
    ListBookResponse,
    ListCatalogResponse,
    ListDetailResponse,
    ListMetadata,
    ListReactionKind,
    ListReactionRequest,
    ReactionKind,
    ReactionRequest,
    RecommendationBatchOut,
    RecommendationResponse,
    SeenBooksRequest,
    SeedBookRequest,
    SeedBookResponse,
    StructuredOverviewOut,
    SuggestionBatchOut,
    SuggestionResponse,
    SuggestionsRequest,
    UserSettingsRequest,
    UserSettingsResponse,
)
from prompts import build_recommendations_prompt, build_suggestions_prompt, build_overview_structure_prompt
from book_match import is_derivative_description
from credentials import credentials, strip_unverified_quotes
from google_books import lookup_cover, lookup_metadata
from open_library import lookup_cover as open_library_lookup_cover
from nyt_bestsellers import lookup_bestseller
from nyt_history import fetch_next_pages as nyt_history_fetch_next_pages, lookup_bestseller_history
from lists import book_id_hash, get_list_metadata, load_catalog, load_list_books

import threading
from concurrent.futures import Future, ThreadPoolExecutor, as_completed
import httpx

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Clients (module-level singletons, initialised once at cold start)
# ---------------------------------------------------------------------------
db = firestore.Client()
# Measured Claude calls run 15-40s. The SDK default (600s timeout, 2 retries) would
# let one stalled call hold a request for ~30 min -- longer than the cron's whole
# time budget -- so bound it tightly.
claude = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"], timeout=120.0, max_retries=1)

# ---------------------------------------------------------------------------
# Community list ("loved by readers") config
# ---------------------------------------------------------------------------
# Slug must match the entry in data/lists/_index.json. The computed books live
# in Firestore (computed_lists/<slug>) so serving is a cheap single-doc read;
# Cloud Run's filesystem is ephemeral so we can't write a JSON file there.
COMMUNITY_LIST_SLUG = "loved_by_readers"
COMMUNITY_LIST_SIZE = int(os.environ.get("COMMUNITY_LIST_SIZE", "30"))
# Stored with headroom: each viewer's own read books are hidden at serve time
# (the heaviest reader had read 67 of the top 120).
COMMUNITY_STORED_SIZE = COMMUNITY_LIST_SIZE * 3

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
app = FastAPI(title="Shelf API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Auth helper
# ---------------------------------------------------------------------------
# Exclusion list: every seed and reaction is ALWAYS excluded (the reader's own
# history; stays small), plus up to this many of their most recent distinct prior
# recommendations. The old single cap of 150 let a heavy reader's older picks age
# out and get re-recommended -- one reader had 1,987 recs over only 612 distinct
# titles -- and the client silently discards repeats, which starved the feed.
# Inline stays shorter so the model answers fast and fully; the repeat filter
# after parsing catches whatever the shorter list lets through.
MAX_EXCLUSION_RECS_INLINE = 250
MAX_EXCLUSION_RECS_CRON = 600
FEED_DELIVERY_LIMIT = 50  # Phase 4: deliver up to this many undelivered recs per
                          # /v1/recommendations call, so a queue accumulated while
                          # the user was away drains in one open (was 10).

# Claude model + per-site effort. Opus 5.5 rejects sampling parameters and can't run
# without thinking, so effort is the quality/latency lever, and its levels sit higher
# than Opus 5's (its medium beats Opus 5's high in Anthropic's testing). Measured on
# 10-08 with the current prompt: inline recs (a phone is waiting, 60s client timeout)
# at medium took 43s for the heaviest reader (18.7k-token prompt, 10/10 kept) and
# less for everyone else; low returned a 4-book dud for that reader. Cron recs run
# medium against the long exclusion list. Similar-books ("closely related to this one
# book") and the mechanical overview split run low: the 18-book pool took 27s, the
# overview 3s. Opus 5 at the same settings cost 25% more per token.
CLAUDE_MODEL = "claude-opus-5-5"
REC_EFFORT_INLINE = "medium"
REC_EFFORT_CRON = "medium"
SIMILAR_EFFORT = "low"
OVERVIEW_EFFORT = "low"
# Cron: a batch thinner than this after filtering gets one refill draw.
CRON_MIN_BATCH = 8
# Books per generation. Inline is smaller because a phone is waiting: with the long
# card descriptions, 10 books at medium took up to 59s of model time on 10-08
# (client timeout 60s), 6 books 32-34s. The nightly queue fills the rest.
CRON_BATCH_SIZE = 10
INLINE_BATCH_SIZE = 6

# Seed context for the recs prompt: how many of the user's newest seeds get a
# description/year attached, and how many Google Books lookups a single
# generation may spend filling gaps (bounds new GB quota use; the rest of the
# gaps are filled on later runs, one-time per seed).
SEED_CONTEXT_MAX = 40
SEED_ENRICH_PER_RUN = 5

# Nightly cron: stop STARTING new users once this much wall time is spent, well
# inside the Cloud Run request timeout (1800s in deploy.sh). Users left over are
# ordered first the next night.
CRON_TIME_BUDGET_SECONDS = 1500

# Phase B lookback: how many of the user's most recent DELIVERED batches feed
# the cross-session genre/era counterbalance histogram. Bounded for token cost.
RECENT_BATCH_LOOKBACK = 3

# Phase 6: size of the shared, taste-blind similar-books pool generated and cached
# per book (served to all users; per-user `exclude` applied after the cache).
SIMILAR_CACHE_POOL_SIZE = 18

# Bump to invalidate ALL cached book overviews (re-structured lazily on next read)
# — used when the structuring prompt/logic changes, e.g. the relevance guard.
OVERVIEW_CACHE_VERSION = 4

_EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)

# Deliberation leaking into a structured field, e.g. "The Tin Drum? no — The Late Show".
_LEAK_RE = re.compile(r"(?:\?|\.\.\.|…)\s*no\s*[—-]|\breplaced:", re.I)

# The same deliberation leaking into a blurb (39 stored recs, 9 of them among
# Opus 5's first 855): "Wait—better entry point: ...", "No—too thin for you. Instead, ...",
# "Too obvious—instead, ...", "Already shown—so instead, ...". Anchored on a
# marker word followed by punctuation, so "No one ..." and "no-nonsense" pass.
_BLURB_LEAK_RE = re.compile(
    r"^\W*(?:wait|no|actually|hmm+|scratch that|too obvious|already shown|correction"
    r"|on second thought|never mind)\s*[—–\-,.:;!]"
    r"|\b(?:wait|actually)\s*[—–-]\s*no\b|\bthe pick you want is\b",
    re.I)

# Stand-in values the model sometimes emits instead of real text. Seen on Opus 5:
# blurb "placeholder", author "placeholder" / "x", genre and era "placeholder".
_PLACEHOLDER_RE = re.compile(
    r"\bplace[- ]?holder\b|lorem ipsum|\{\{|\}\}"
    r"|^\s*(?:tbd|todo|n/?a|none|null|undefined|x+|\.{2,}|…|-+|\?+)\s*\.?\s*$",
    re.I)
_MIN_BLURB_CHARS = 20
# Core fields: a book whose core field is a stand-in is dropped. Optional fields
# (the reason clause and editorial hooks) are blanked instead, keeping the book.
_CORE_TEXT_FIELDS = ("title", "author", "blurb", "genre", "era")
_OPTIONAL_TEXT_FIELDS = ("because_of_reason", "context_tag", "acclaim")


def _is_placeholder(value) -> bool:
    return isinstance(value, str) and bool(value.strip()) and bool(_PLACEHOLDER_RE.search(value))


def _blank_placeholder_fields(b: dict) -> None:
    """Blank optional fields (and award entries) holding a stand-in value or leaked
    deliberation."""
    for f in _OPTIONAL_TEXT_FIELDS:
        if _is_placeholder(b.get(f)) or _BLURB_LEAK_RE.search(b.get(f) or ""):
            b[f] = ""
    if isinstance(b.get("awards"), list):
        b["awards"] = [a for a in b["awards"] if not _is_placeholder(a)]


def _junk_reason(b: dict, seed_titles=()) -> str | None:
    """Why a generated book must be dropped, or None if it is usable: leaked
    deliberation, missing title/author, the author's name as the title, a seed
    title in possessive form ("The Poet X's"), a stand-in core field, or no real
    blurb. `seed_titles` are lowercased seed titles for the possessive check."""
    title, author = (b.get("title") or "").strip(), (b.get("author") or "").strip()
    if _LEAK_RE.search(title) or _LEAK_RE.search(author):
        return "leaked deliberation"
    if len(title) < 2 or len(author) < 2:
        return "missing title/author"
    if title.lower() == author.lower():
        return "title is the author"
    possessive = re.match(r"^(.*?)['’]s$", title)
    if possessive and possessive.group(1).strip().lower() in seed_titles:
        return "possessive seed title"
    for f in _CORE_TEXT_FIELDS:
        if _is_placeholder(b.get(f)):
            return f"placeholder {f}"
    blurb = (b.get("blurb") or "").strip()
    if len(blurb) < _MIN_BLURB_CHARS:
        return "missing blurb"
    if _BLURB_LEAK_RE.search(blurb):
        return "leaked deliberation in blurb"
    return None


def _exc_key(title, author) -> tuple[str, str] | None:
    """Normalized title|author identity used for exclusion and repeat filtering."""
    t, a = (title or "").strip(), (author or "").strip()
    return (t.lower(), a.lower()) if t else None


# Per-MTok (input, output) USD prices and the cache-read multiplier, for the cost
# estimate in the usage log line. Models a server-side fallback can answer with
# are included; an unlisted model logs tokens without an estimate. 5-minute cache
# writes bill at 1.25x of the input price on all of these.
_PRICES_PER_MTOK = {
    "claude-opus-5-5": (4.0, 20.0, 0.05),
    "claude-opus-5": (5.0, 25.0, 0.1),
    "claude-opus-4-8": (5.0, 25.0, 0.1),
    "claude-opus-4-7": (5.0, 25.0, 0.1),
}


def _log_claude_usage(kind: str, effort: str, body: dict) -> None:
    """One greppable line per Claude call ('claude usage kind=...'), so the daily
    token and dollar spend can be rolled up from Cloud Run logs by call site.
    output_tokens includes thinking. Never raises."""
    try:
        u = body.get("usage") or {}
        model = body.get("model") or CLAUDE_MODEL
        inp = int(u.get("input_tokens") or 0)
        out = int(u.get("output_tokens") or 0)
        cread = int(u.get("cache_read_input_tokens") or 0)
        cwrite = int(u.get("cache_creation_input_tokens") or 0)
        price = _PRICES_PER_MTOK.get(model)
        est = (f"{(inp * price[0] + cread * price[0] * price[2] + cwrite * price[0] * 1.25 + out * price[1]) / 1e6:.4f}"
               if price else "n/a")
        log.info("claude usage kind=%s model=%s effort=%s input=%d output=%d cache_read=%d cache_write=%d "
                 "stop=%s est_usd=%s", kind, model, effort, inp, out, cread, cwrite, body.get("stop_reason"), est)
    except Exception as exc:
        log.warning("claude usage logging failed for kind=%s: %s", kind, exc)


def _claude_parse(prompt: str, output_format, effort: str, max_tokens: int, kind: str):
    """One structured-output Claude call. Returns the validated `output_format`
    instance, or None when there is nothing usable: the safety classifiers
    declined (an HTTP 200 with stop_reason "refusal" — even after the server-side
    fallback chain), or the output failed schema validation. The SDK validates
    inside parse(), so a max_tokens truncation or a mid-output refusal surfaces
    as ValidationError rather than through stop_reason. API errors propagate to
    the caller exactly as before. max_tokens caps thinking plus text together on
    Opus 5.x, so callers size it well above the JSON.

    The raw response is read before validation so the usage line is logged even
    when the output then fails to validate. `kind` labels the call site."""
    raw = claude.beta.messages.with_raw_response.parse(
        model=CLAUDE_MODEL,
        max_tokens=max_tokens,
        messages=[{"role": "user", "content": prompt}],
        output_format=output_format,
        output_config={"effort": effort},
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",
    )
    try:
        body = raw.http_response.json()
    except Exception:
        body = {}
    _log_claude_usage(kind, effort, body)
    try:
        response = raw.parse()
    except ValidationError as exc:
        log.warning("Claude %s output failed schema validation (truncated or mid-output refusal): %s",
                    output_format.__name__, exc)
        return None
    if response.stop_reason == "refusal":
        log.warning("Claude declined %s request: %s",
                    output_format.__name__, getattr(response, "stop_details", None))
        return None
    if response.parsed_output is None:
        log.warning("Claude %s request returned no parseable output (stop_reason=%s)",
                    output_format.__name__, response.stop_reason)
        return None
    return response.parsed_output


def get_user_id(authorization: Annotated[str | None, Header()] = None) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED)
    return authorization.removeprefix("Bearer ").strip()


UserID = Annotated[str, Depends(get_user_id)]


# ---------------------------------------------------------------------------
# Firestore helpers
# ---------------------------------------------------------------------------
def user_ref(user_id: str) -> firestore.DocumentReference:
    return db.collection("users").document(user_id)


def seed_col(user_id: str):
    return user_ref(user_id).collection("seed_books")


def reaction_col(user_id: str):
    return user_ref(user_id).collection("reactions")


def recommendation_col(user_id: str):
    return user_ref(user_id).collection("recommendations")


def _is_gb_catalog_url(url: str) -> bool:
    """True for a Google Books 'catalog-only' cover (volume id ending in AAJ),
    which serves an 'image not available' placeholder rather than a real cover."""
    if "books.google.com" not in url:
        return False
    m = re.search(r"[?&]id=([^&]+)", url)
    return bool(m and m.group(1).endswith("AAJ"))


def _has_valid_cover(cover_url: str | None) -> bool:
    """Single source of truth for 'does this book have a usable cover?'.
    Valid iff the URL is a non-empty string after trimming. Applied at rec
    generation, suggestion generation, and list build so a cover-less book
    (which renders as a blank placeholder on iOS) is filtered out before it ever
    reaches the client. The iOS client keeps an identical guard as a backstop."""
    return bool((cover_url or "").strip())


_META_KEYS = ("cover_url", "page_count", "description", "year")
# How long an unresolved/partial Google Books result is trusted before one retry.
_META_RECHECK = timedelta(days=7)


def _meta_is_stale_partial(d: dict, now: datetime) -> bool:
    """A cached entry with no description (Google Books returned only a cover or
    page count) is retried after _META_RECHECK so a description GB starts serving
    later is not frozen out forever. Fully empty results are never cached at all."""
    if d.get("description"):
        return False
    ts = d.get("cached_at")
    return not isinstance(ts, datetime) or (now - ts) > _META_RECHECK


# book_meta_cache entries written since edition matching (book_match) carry this
# version. Older entries may hold a wrong edition's cover and description: about a
# quarter of a live sample matched a summary edition or an unrelated book.
META_CACHE_VERSION = 2


def _cached_lookup_metadata(title: str, author: str, client: httpx.Client,
                            require_validated: bool = False) -> dict:
    """google_books.lookup_metadata behind the shared book_meta_cache/{book_id}
    collection, so a popular title costs one Google Books query across all users
    (GB quota is 1000/day). Empty results are never cached, so a title self-heals
    once quota returns. Best-effort: a cache failure degrades to the direct lookup.

    Pre-validation entries are still served, since re-fetching them all would
    exhaust the GB quota, except when require_validated (the caller is about to
    show the entry's cover) or when the description is from a summary edition.
    Re-fetched entries are overwritten, even with an empty result, so a bad entry
    is replaced once instead of being re-fetched on every read. The returned
    dict's "validated" says whether the entry passed edition matching."""
    ref = db.collection("book_meta_cache").document(book_id_hash(title, author))
    replacing_bad = False
    try:
        snap = ref.get()
        if snap.exists:
            d = snap.to_dict() or {}
            validated = d.get("v") == META_CACHE_VERSION
            if is_derivative_description(d.get("description")) or (require_validated and not validated):
                replacing_bad = True
            elif not _meta_is_stale_partial(d, datetime.now(timezone.utc)):
                return {"cover_url": d.get("cover_url") or "", "page_count": d.get("page_count"),
                        "description": d.get("description") or "", "year": d.get("year"),
                        "validated": validated}
    except Exception as exc:
        log.warning("book_meta_cache read failed for %r: %s", title, exc)
    meta = lookup_metadata(title, author, client=client)
    if meta.get("description") or meta.get("page_count") or meta.get("cover_url") or replacing_bad:
        try:
            ref.set({**{k: meta.get(k) for k in _META_KEYS}, "title": title, "author": author,
                     "v": META_CACHE_VERSION, "cached_at": datetime.now(timezone.utc)})
        except Exception as exc:
            log.warning("book_meta_cache write failed for %r: %s", title, exc)
    return {**meta, "validated": True}


# Key terms of an accolade; one that shares a term with the model's description
# ("...won the Pulitzer") is not repeated under it.
_ACCOLADE_TERMS = ("pulitzer", "booker", "national book award", "national book critics", "nobel", "hugo",
                   "nebula", "newbery", "caldecott", "printz", "costa", "women's prize", "oprah", "reese",
                   "bestseller", "motion picture", "film", "series", "netflix", "hbo", "notable", "best book")


def _attach_credentials(b: dict, overview: dict | None = None) -> None:
    """Set the card fields in place: blurb_text (the model's description with any
    unverified praise-quote removed), review_quote + source and accolades (verbatim
    from the publisher description, credentials.py), and blurb, the three joined
    for app builds that predate the separate fields. When the regex finds nothing,
    a structured overview of the same publisher text (cron prewarm) supplies them
    exactly as the PDP shows them: its first pull quote, extracted from the
    publisher text by the relevance-guarded structuring call."""
    source = b.get("description") or ""
    text = strip_unverified_quotes(b.get("blurb_text") or b.get("blurb") or "", source)
    quote, accs = credentials(source, b.get("title") or "", b.get("author") or "")
    if overview:
        if not quote:
            for q in overview.get("pull_quotes") or []:
                qt, qs = (q.get("text") or "").strip(), (q.get("source") or "").strip()
                if qt and qs:
                    quote = (qt, qs)
                    break
        if not accs:
            accs = [a for a in (overview.get("accolades") or []) if isinstance(a, str) and a.strip()]
    said = text.lower()
    fresh = [a for a in accs if not any(t in a.lower() and t in said for t in _ACCOLADE_TERMS)][:3]
    b["blurb_text"] = text
    b["review_quote"], b["review_quote_source"] = (quote if quote else ("", ""))
    b["accolades"] = fresh
    parts = [text]
    if quote:
        parts.append(f"“{quote[0]}” — {quote[1]}")
    if fresh:
        parts.append(" · ".join(fresh[:2]))
    b["blurb"] = "\n\n".join(p for p in parts if p)


def _enrich_books(books: list[dict], client: httpx.Client) -> None:
    """Enrich a whole batch concurrently (Google Books + Open Library + NYT per
    book are all network wait). One book's failure must not discard a Claude
    batch we already paid for: it is logged, left unenriched, and the cover
    filter drops it. httpx.Client and the Firestore client are both
    thread-safe; the NYT refresh is locked in its module."""
    if not books:
        return

    def _one(b: dict) -> None:
        try:
            _enrich_book(b, client=client)
        except Exception as exc:
            log.warning("enrichment failed for %r: %s", b.get("title"), exc)

    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(_one, books))


def _enrich_book(b: dict, client: httpx.Client) -> None:
    """Add cover_url, NYT bestseller status, reading time, normalized fields
    to a book dict in-place. Used by both /v1/recommendations and
    /v1/onboarding/suggestions before persistence / response."""
    title = b.get("title", "")
    author = b.get("author", "")

    # Prefer Open Library for covers — far better data quality than Google Books.
    # Fall back to Google Books if Open Library has nothing. Both only accept an
    # edition that matches this title/author and isn't a summary edition.
    meta = _cached_lookup_metadata(title, author, client)   # still need for pageCount
    if not b.get("cover_url"):
        ol_cover = open_library_lookup_cover(title, author, client=client)
        if not ol_cover and not meta.get("validated"):
            meta = _cached_lookup_metadata(title, author, client, require_validated=True)
        b["cover_url"] = ol_cover or meta.get("cover_url", "")

    # Reading time: ~1.7 min per page on average (200wpm, ~340 words/page)
    page_count = meta.get("page_count")
    b["reading_time_minutes"] = round(page_count * 1.7) if isinstance(page_count, int) and page_count > 0 else None

    # Phase 3: store the full Google Books description so the PDP can show an
    # expandable description — captured here at build time, never fetched per-open.
    # Claude's picks carry no description, so the Google Books value is authoritative.
    if not b.get("description"):
        b["description"] = meta.get("description", "") or ""

    # NYT bestseller status — check current lists first, then historical archive
    bs = lookup_bestseller(title, author)
    if bs:
        b["nyt_bestseller"] = True
        b["nyt_weeks_on_list"] = bs.get("weeks_on_list")
    else:
        hist = lookup_bestseller_history(db, title, author)
        if hist:
            b["nyt_bestseller"] = True
            b["nyt_weeks_on_list"] = hist.get("max_weeks_on_list")
        else:
            b["nyt_bestseller"] = False
            b["nyt_weeks_on_list"] = None

    # Normalize Claude-optional fields
    b["awards"] = b.get("awards") or []
    b["context_tag"] = b.get("context_tag") or ""
    b["acclaim"] = b.get("acclaim") or ""


def _resolve_seed_context(user_id: str, seeds: list[dict], spend_lookups: bool) -> None:
    """Attach description/year (in-place) to the newest SEED_CONTEXT_MAX seeds so
    the recs prompt can see what each seed IS instead of inferring taste from bare
    titles. Sources, cheapest first: fields already on the seed doc; the shared
    book_meta_cache (one batched read); then -- only when spend_lookups, i.e. the
    nightly cron, never the user-facing inline path -- at most SEED_ENRICH_PER_RUN
    Google Books lookups. Resolved fields are persisted onto the seed doc. A seed
    that could not be resolved gets a meta_checked_at marker so it is not retried
    (and does not hog the lookup slots ahead of older seeds) for _META_RECHECK.
    Seeds past the cap or still unresolved stay title-only. Best-effort: never
    blocks generation."""
    now = datetime.now(timezone.utc)

    def _recently_checked(s: dict) -> bool:
        ts = s.get("meta_checked_at")
        return isinstance(ts, datetime) and (now - ts) < _META_RECHECK

    try:
        targets = [s for s in seeds[:SEED_CONTEXT_MAX]
                   if not (s.get("description") or s.get("year")) and not _recently_checked(s)]
        if not targets:
            return
        refs = [db.collection("book_meta_cache").document(book_id_hash(s.get("title", ""), s.get("author", "")))
                for s in targets]
        cached = {snap.id: (snap.to_dict() or {}) for snap in db.get_all(refs) if snap.exists}

        resolved: list[dict] = []
        checked: list[dict] = []   # looked at, nothing usable yet -> marker only
        misses: list[dict] = []
        for s, ref in zip(targets, refs):
            meta = cached.get(ref.id)
            if meta is None or _meta_is_stale_partial(meta, now):
                misses.append(s)
            elif meta.get("description") or meta.get("year"):
                s["description"], s["year"] = meta.get("description") or "", meta.get("year")
                resolved.append(s)
            else:
                checked.append(s)

        if misses and spend_lookups:
            with httpx.Client(timeout=5.0) as client:
                for s in misses[:SEED_ENRICH_PER_RUN]:
                    meta = _cached_lookup_metadata(s.get("title", ""), s.get("author", ""), client)
                    if meta.get("description") or meta.get("year"):
                        s["description"], s["year"] = meta.get("description") or "", meta.get("year")
                        resolved.append(s)
                    else:
                        checked.append(s)

        batch = db.batch()
        for s in resolved:
            if s.get("id"):
                batch.set(seed_col(user_id).document(s["id"]),
                          {"description": s["description"], "year": s["year"], "meta_checked_at": now},
                          merge=True)
        for s in checked:
            if s.get("id"):
                batch.set(seed_col(user_id).document(s["id"]), {"meta_checked_at": now}, merge=True)
        if resolved or checked:
            batch.commit()
    except Exception as exc:
        log.warning("seed context enrichment failed for user %s: %s", user_id, exc)


# ---------------------------------------------------------------------------
# POST /v1/seed-books
# ---------------------------------------------------------------------------
@app.post("/v1/seed-books", status_code=status.HTTP_201_CREATED)
def add_seed_book(body: SeedBookRequest, user_id: UserID):
    """Add a seed book. Idempotent on (title, author) — returns the existing
    seed's id if the user already has it, instead of creating a duplicate."""
    title_key = body.title.lower().strip()
    author_key = body.author.lower().strip()
    for doc in seed_col(user_id).where("domain", "==", body.domain).stream():
        d = doc.to_dict()
        if (d.get("title", "").lower().strip() == title_key and
                d.get("author", "").lower().strip() == author_key):
            return {"id": doc.id}

    doc_id = str(uuid.uuid4())
    seed_col(user_id).document(doc_id).set(
        {**body.model_dump(), "id": doc_id, "created_at": datetime.now(timezone.utc)}
    )
    return {"id": doc_id}


# ---------------------------------------------------------------------------
# GET /v1/seed-books
# ---------------------------------------------------------------------------
@app.get("/v1/seed-books", response_model=list[SeedBookResponse])
def list_seed_books(user_id: UserID, domain: str = "books"):
    docs = seed_col(user_id).where("domain", "==", domain).stream()
    return [SeedBookResponse(**d.to_dict()) for d in docs]


# ---------------------------------------------------------------------------
# DELETE /v1/seed-books/{id}
# ---------------------------------------------------------------------------
@app.delete("/v1/seed-books/{book_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_seed_book(book_id: str, user_id: UserID):
    seed_col(user_id).document(book_id).delete()


# ---------------------------------------------------------------------------
# POST /v1/reactions
# ---------------------------------------------------------------------------
@app.post("/v1/reactions", status_code=status.HTTP_201_CREATED)
def add_reaction(body: ReactionRequest, user_id: UserID):
    doc_id = str(uuid.uuid4())

    # Look up the book so we can store title/author alongside the reaction.
    # This makes the data directly usable in the recommendation prompt without
    # a second lookup step at generation time.
    book_doc = recommendation_col(user_id).document(body.book_id).get()
    book = book_doc.to_dict() if book_doc.exists else {}

    # Prefer the canonical title/author from the recommendation we generated;
    # fall back to the values the client sent (seed/list/search surfaces have no
    # recommendation_col entry). Without this fallback, those reactions store an
    # empty title and get dropped from both the exclusion list and the
    # negative-signal list at generation time.
    reaction_col(user_id).document(doc_id).set({
        **body.model_dump(),
        "id": doc_id,
        "created_at": datetime.now(timezone.utc),
        "title": book.get("title") or body.title or "",
        "author": book.get("author") or body.author or "",
    })
    return {"id": doc_id}


# ---------------------------------------------------------------------------
# POST /v1/seen-books
# ---------------------------------------------------------------------------
@app.post("/v1/seen-books", status_code=status.HTTP_204_NO_CONTENT)
def mark_seen(body: SeenBooksRequest, user_id: UserID):
    batch = db.batch()
    ref = user_ref(user_id)
    for book_id in body.book_ids:
        batch.set(
            ref.collection("seen_books").document(book_id),
            {"book_id": book_id, "domain": body.domain,
             "seen_at": datetime.now(timezone.utc)},
        )
    batch.commit()


# ---------------------------------------------------------------------------
# GET /v1/recommendations  (generate if needed, else return cached batch)
# ---------------------------------------------------------------------------
@app.get("/v1/recommendations", response_model=list[RecommendationResponse])
def get_recommendations(user_id: UserID, domain: str = "books", force: bool = False):
    # If force=true, skip the cache and generate a fresh batch immediately
    # (used by the Discover feed's "Load more" CTA).
    if force:
        return _generate_inline(user_id, domain)

    # Otherwise return any undelivered cached recommendations.
    # CRITICAL: mark them delivered=True as we return, so the SAME books aren't
    # served on every poll — that was the source of the "I keep seeing the same
    # recs back-to-back" bug.
    unseen_docs = list(
        recommendation_col(user_id)
        .where("domain", "==", domain)
        .where("delivered", "==", False)
        .limit(FEED_DELIVERY_LIMIT)
        .stream()
    )
    if unseen_docs:
        cached = [RecommendationResponse(**d.to_dict()) for d in unseen_docs]
        # Batch mark as delivered
        batch = db.batch()
        for doc in unseen_docs:
            batch.update(doc.reference, {"delivered": True})
        batch.commit()
        return cached

    # No cached undelivered → generate a fresh batch
    return _generate_inline(user_id, domain)


_INFLIGHT: dict[tuple[str, str], Future] = {}
_INFLIGHT_GUARD = threading.Lock()


def _generate_inline(user_id: str, domain: str) -> list[RecommendationResponse]:
    """Coalesce concurrent inline generations for one user onto a single Claude
    call. The client fires several fetches at once (each seed added during
    onboarding, foreground refresh, first-run fill, daily rotation) — one new
    user triggered nine ~30s generations in two minutes, each paying for its own
    call and, because none could see the others' picks, producing batches that
    overlapped (111 recs, 81 distinct). Callers that arrive while a generation is
    in flight wait for it and receive the same batch; the client dedups by id, so
    they simply add nothing new. Sequential calls still each get a fresh batch.
    Per-process only (best-effort across Cloud Run instances)."""
    key = (user_id, domain)
    with _INFLIGHT_GUARD:
        fut = _INFLIGHT.get(key)
        owner = fut is None
        if owner:
            fut = Future()
            _INFLIGHT[key] = fut
    if not owner:
        return fut.result()
    try:
        results = _generate_recommendations(user_id, domain)
    except BaseException as exc:
        fut.set_exception(exc)
        raise
    else:
        fut.set_result(results)
        return results
    finally:
        with _INFLIGHT_GUARD:
            _INFLIGHT.pop(key, None)


def _generate_recommendations(user_id: str, domain: str, is_cron: bool = False) -> list[RecommendationResponse]:
    """Generate a fresh batch, persist it as undelivered, and return it.

    Batches are stored delivered=False on BOTH paths: the next plain
    /v1/recommendations call serves and marks them, and the client dedups by id,
    so an inline batch the phone did receive is re-served once harmlessly — while
    a batch the phone gave up on (60s client timeout) is no longer lost.

    is_cron: the nightly path. No one is waiting, so it spends Google Books
    lookups on seed context, uses the long exclusion list at higher effort,
    refills a thin batch with a second draw, and pre-structures overviews.
    """
    # Gather seed books, newest first — the seed-context cap below favors what the
    # reader added most recently.
    seeds = [d.to_dict() for d in seed_col(user_id).where("domain", "==", domain).stream()]
    if not seeds:
        return []
    seeds.sort(key=lambda s: s.get("created_at") or _EPOCH, reverse=True)
    # Google Books lookups for seed context only on the cron path: the inline
    # request is user-facing and already runs ~30-40s against a 60s client timeout.
    _resolve_seed_context(user_id, seeds, spend_lookups=is_cron)

    # Build exclude list as "Title by Author" strings — Claude needs human-readable
    # context, not opaque UUIDs. Include every rec we've EVER generated for this user
    # (so the same book never appears in two consecutive Generate-more sessions),
    # plus the seed books themselves (no need to recommend what they already love),
    # plus any reaction that carries a title/author (e.g. list-saved/passed books
    # from Phase 1 don't have a corresponding recommendation_col entry).
    # Stream the user's full recommendation history once and reuse it for both
    # the exclusion list and the Phase B recent-mix histogram below.
    all_recs = [r.to_dict() for r in recommendation_col(user_id).stream()]
    # Exclusion list. Seeds and reactions are the reader's own history and are
    # ALWAYS excluded; prior recommendations are excluded newest-first, distinct
    # by title|author, up to the per-path MAX_EXCLUSION_RECS_*. exclude_keys also backs the
    # post-parse repeat filter, so a pick the model repeats anyway is never
    # persisted or served.
    exclude_keys: set[tuple[str, str]] = set()
    exclude_list: list[str] = []

    def _exclude(title, author) -> None:
        k = _exc_key(title, author)
        if k and k not in exclude_keys:
            t, a = (title or "").strip(), (author or "").strip()
            exclude_keys.add(k)
            exclude_list.append(f"{t} by {a}" if a else t)

    max_recs = MAX_EXCLUSION_RECS_CRON if is_cron else MAX_EXCLUSION_RECS_INLINE
    for d in sorted(all_recs, key=lambda r: r.get("created_at") or _EPOCH, reverse=True):
        if len(exclude_list) >= max_recs:
            break
        _exclude(d.get("title"), d.get("author"))
    for s in seeds:
        _exclude(s.get("title"), s.get("author"))
    for rxn in reaction_col(user_id).stream():
        d = rxn.to_dict()
        _exclude(d.get("title"), d.get("author"))

    # Positive / negative taste signals
    liked = [
        d.to_dict()
        for d in reaction_col(user_id)
        .where("kind", "in", [ReactionKind.save, ReactionKind.already_read_liked])
        .stream()
    ]
    disliked = [
        d.to_dict()
        for d in reaction_col(user_id)
        .where("kind", "in", [ReactionKind.already_read_disliked, ReactionKind.dismiss])
        .limit(50)
        .stream()
    ]

    # Phase B: compact genre/era histogram over the last few DELIVERED batches
    # (bounded by RECENT_BATCH_LOOKBACK). Lets the prompt apply a LIGHT bias
    # against one genre/era dominating many consecutive feeds — without chasing
    # variety the taste profile doesn't support. Stays None when the user has no
    # delivered history yet, preserving first-batch behavior.
    delivered_recs = [
        r for r in all_recs
        if r.get("delivered") and r.get("batch_id") and r.get("created_at")
    ]
    recent_mix: dict | None = None
    if delivered_recs:
        latest_ts: dict[str, datetime] = {}
        for r in delivered_recs:
            bid, ts = r["batch_id"], r["created_at"]
            if bid not in latest_ts or ts > latest_ts[bid]:
                latest_ts[bid] = ts
        recent_ids = {
            bid for bid, _ in
            sorted(latest_ts.items(), key=lambda kv: kv[1], reverse=True)[:RECENT_BATCH_LOOKBACK]
        }
        genre_hist: dict[str, int] = {}
        era_hist: dict[str, int] = {}
        for r in delivered_recs:
            if r["batch_id"] not in recent_ids:
                continue
            g = (r.get("genre") or "").strip()
            e = (r.get("era") or "").strip()
            if g:
                genre_hist[g] = genre_hist.get(g, 0) + 1
            if e:
                era_hist[e] = era_hist.get(e, 0) + 1
        if genre_hist or era_hist:
            recent_mix = {"batches": len(recent_ids), "genres": genre_hist, "eras": era_hist}

    seed_title_lookup = {s["title"].strip().lower(): s["title"] for s in seeds if s.get("title")}
    effort = REC_EFFORT_CRON if is_cron else REC_EFFORT_INLINE
    batch_size = CRON_BATCH_SIZE if is_cron else INLINE_BATCH_SIZE

    def _draw() -> list[dict] | None:
        """One Claude draw: prompt -> parse -> validate -> filter. None if declined.
        Kept picks are added to the exclusion set so a refill draw cannot repeat them."""
        prompt = build_recommendations_prompt(
            seeds=seeds,
            liked=liked,
            disliked=disliked,
            exclude_ids=exclude_list,
            domain=domain,
            count=batch_size,
            recent_mix=recent_mix,
        )
        parsed = _claude_parse(prompt, RecommendationBatchOut, effort, max_tokens=16000,
                               kind="recs_cron" if is_cron else "recs_inline")
        if parsed is None:
            return None
        drawn: list[dict] = [b.model_dump() for b in parsed.books]
        kept: list[dict] = []
        dropped_junk = dropped_repeat = 0
        for b in drawn:
            b["cover_url"] = ""   # resolved by enrichment below
            _blank_placeholder_fields(b)
            # Validate `because_of` against the user's actual seed titles. If Claude
            # invents or distorts a title, drop the field rather than show a confusing
            # "Because you loved <book you don't own>" line in the UI.
            raw_because = b.get("because_of")
            if isinstance(raw_because, str) and raw_because.strip():
                b["because_of"] = seed_title_lookup.get(raw_because.strip().lower())
            else:
                b["because_of"] = None
            # The reason clause is only meaningful next to a valid because_of.
            raw_reason = b.get("because_of_reason")
            if b["because_of"] and isinstance(raw_reason, str) and raw_reason.strip():
                b["because_of_reason"] = raw_reason.strip()[:120]
            else:
                b["because_of_reason"] = ""
            # Drop picks the model should not have produced: leaked deliberation in
            # a title ("The Tin Drum? no — The Late Show"), stand-in text in a core
            # field (a "placeholder" blurb), and repeats of anything excluded (the
            # client discards those anyway, so they were dead weight in every batch).
            title, author = b.get("title") or "", b.get("author") or ""
            junk = _junk_reason(b, seed_title_lookup)
            if junk:
                log.warning("recs for user %s: dropped %r by %r (%s)", user_id, title, author, junk)
                dropped_junk += 1
                continue
            if _exc_key(title, author) in exclude_keys:
                dropped_repeat += 1
                continue
            _exclude(title, author)
            kept.append(b)
        if dropped_junk or dropped_repeat:
            log.warning("recs for user %s: dropped %d junk and %d repeated picks of %d",
                        user_id, dropped_junk, dropped_repeat, len(drawn))
        return kept

    books = _draw()
    if books is None:
        raise RuntimeError(f"recommendation generation declined by Claude for user {user_id}")
    # A thin batch on the cron path gets one more draw against the now-extended
    # exclusion list. Inline can't afford the second call.
    if is_cron and len(books) < CRON_MIN_BATCH:
        more = _draw() or []
        books.extend(more[:batch_size - len(books)])
        log.info("cron refill for user %s: +%d -> %d books", user_id, len(more), len(books))

    # Enrich with Google Books cover + NYT bestseller + reading time
    with httpx.Client(timeout=5.0) as client:
        _enrich_books(books, client)

    # Phase 2: drop any book whose cover couldn't be resolved, so a blank
    # placeholder never reaches the feed. Earliest line of defense — these are
    # never persisted or served. (iOS guards again on insert as a backstop.)
    books = [b for b in books if _has_valid_cover(b.get("cover_url"))]

    # Card fields: the model's description plus a verified review quote and
    # accolades. The nightly path structures each book's overview first (so its
    # PDP opens instantly) and lets that fill in what the regex finds nothing
    # for; the inline path can't afford the extra calls.
    overviews: dict[str, dict] = {}
    if is_cron:
        try:
            _prewarm_overviews(books)
            overviews = _cached_overviews(books)
        except Exception as exc:
            log.warning("overview prewarm failed: %s", exc)
    for b in books:
        _attach_credentials(b, overviews.get(book_id_hash(b.get("title", ""), b.get("author", ""))))

    batch_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc)
    results: list[RecommendationResponse] = []

    firestore_batch = db.batch()
    for book in books:
        doc_id = str(uuid.uuid4())
        rec = {
            "id": doc_id,
            "batch_id": batch_id,
            "domain": domain,
            "delivered": False,
            "created_at": now,
            **book,
        }
        firestore_batch.set(recommendation_col(user_id).document(doc_id), rec)
        results.append(RecommendationResponse(**rec))

    # Store generation metadata on user doc
    firestore_batch.set(
        user_ref(user_id),
        {"last_generation_timestamp": now, "last_batch_size": len(books)},
        merge=True,
    )
    firestore_batch.commit()
    return results


# ---------------------------------------------------------------------------
# POST /v1/onboarding/suggestions
# ---------------------------------------------------------------------------
_SIMILAR_INFLIGHT: dict[str, Future] = {}
_SIMILAR_INFLIGHT_GUARD = threading.Lock()


def _similar_pool(body: SuggestionsRequest) -> list[dict]:
    """The shared similar-books pool for one seed book: from the cache, or computed
    once. Concurrent misses for the same book wait for the one in-flight
    computation instead of each paying for a Claude call. The iOS foreground
    refresh fans out over every Taste book and re-requests seeds whose first call
    is still running: on 09-24 one device sent 220 requests in 10 minutes, ~194
    Claude calls for only 26 distinct books, all on one instance. Per-process
    only, like _generate_inline."""
    book_id = book_id_hash(body.seed_book_title, body.seed_book_author)
    cache_ref = db.collection("similar_books_cache").document(book_id)
    snap = cache_ref.get()
    if snap.exists:
        return (snap.to_dict() or {}).get("books", [])
    with _SIMILAR_INFLIGHT_GUARD:
        fut = _SIMILAR_INFLIGHT.get(book_id)
        owner = fut is None
        if owner:
            fut = Future()
            _SIMILAR_INFLIGHT[book_id] = fut
    if not owner:
        return fut.result()
    try:
        # Re-check: a computation that finished between the read above and taking
        # ownership has already cached the pool.
        snap = cache_ref.get()
        pool = ((snap.to_dict() or {}).get("books", []) if snap.exists
                else _compute_similar_pool(body, cache_ref))
    except BaseException as exc:
        fut.set_exception(exc)
        raise
    else:
        fut.set_result(pool)
        return pool
    finally:
        with _SIMILAR_INFLIGHT_GUARD:
            _SIMILAR_INFLIGHT.pop(book_id, None)


def _compute_similar_pool(body: SuggestionsRequest, cache_ref) -> list[dict]:
    """One Claude call for the taste-blind pool, then filter, enrich, and cache."""
    prompt = build_suggestions_prompt(
        seed_title=body.seed_book_title,
        seed_author=body.seed_book_author,
        domain=body.domain,
        count=SIMILAR_CACHE_POOL_SIZE,
        exclude=None,   # user-agnostic pool — no per-user exclude baked in
        liked=None,
        disliked=None,
    )
    parsed = _claude_parse(prompt, SuggestionBatchOut, SIMILAR_EFFORT, max_tokens=16000, kind="similar")
    if parsed is None:
        raise RuntimeError(f"similar-books generation declined by Claude for {body.seed_book_title!r}")
    pool = [b.model_dump() for b in parsed.books]
    kept = []
    for b in pool:
        b["cover_url"] = ""   # resolved by enrichment below
        _blank_placeholder_fields(b)
        junk = _junk_reason(b, {body.seed_book_title.strip().lower()})
        if junk:
            log.warning("similar-books for %r: dropped %r by %r (%s)",
                        body.seed_book_title, b.get("title"), b.get("author"), junk)
            continue
        kept.append(b)
    pool = kept
    # Enrich (cover + NYT + reading time + description) then drop cover-less so a
    # cover-less book is never cached or served (Phase 2 parity).
    with httpx.Client(timeout=5.0) as client:
        _enrich_books(pool, client)
    pool = [b for b in pool if _has_valid_cover(b.get("cover_url"))]
    for b in pool:
        _attach_credentials(b)
    cache_ref.set({
        "books": pool,
        "seed_title": body.seed_book_title,
        "seed_author": body.seed_book_author,
        "cached_at": datetime.now(timezone.utc),
    })
    return pool


@app.post("/v1/onboarding/suggestions", response_model=list[SuggestionResponse])
def get_suggestions(body: SuggestionsRequest, user_id: UserID):
    # Phase 6: shared, taste-blind, per-book cache. Similar-books are computed once
    # per seed book and served to EVERY user (keyed by book_id, not by user) — the
    # seed book is the anchor and per-user taste is intentionally not applied. The
    # per-user `exclude` list is applied AFTER the cache so each reader still avoids
    # books they've already been shown. No LLM call on a cache hit.
    pool = _similar_pool(body)

    # Per-user dedup against the supplied exclude list (lowercased title|author).
    exclude_keys = {item.lower().strip() for item in (body.exclude or [])}
    def _key(b: dict) -> str:
        return f"{b.get('title','').lower().strip()}|{b.get('author','').lower().strip()}"
    filtered = [b for b in pool if _key(b) not in exclude_keys]

    return [
        SuggestionResponse(id=str(uuid.uuid4()), **{k: v for k, v in b.items() if k != "id"})
        for b in filtered[: body.count]
    ]


# ---------------------------------------------------------------------------
# GET /v1/book-overview  (lazy full Google Books description for list PDPs)
# ---------------------------------------------------------------------------
def _structure_overview(raw: str, title: str = "", author: str = "") -> dict:
    """Split a messy publisher description into {synopsis, pull_quotes, accolades}
    via one Claude call. Passes title/author so the model can return EMPTY when the
    description is clearly about a different book (guards against bad GB editions).
    Best-effort: on failure, fall back to raw text. Cached at most once per book."""
    raw = (raw or "").strip()
    if not raw:
        return {"synopsis": "", "pull_quotes": [], "accolades": []}
    try:
        parsed = _claude_parse(build_overview_structure_prompt(raw, title, author),
                               StructuredOverviewOut, OVERVIEW_EFFORT, max_tokens=8000, kind="overview")
        if parsed is None:
            raise RuntimeError("overview structuring declined by Claude")
        data = parsed.model_dump()
        # Trust the model's structure. An EMPTY synopsis here is INTENTIONAL — the
        # relevance guard returns all-empty when the text is clearly about a different
        # book — so never substitute the raw (wrong) text back in. Only a genuine
        # API failure (the except: below) falls back to raw.
        synopsis = (data.get("synopsis") or "").strip()
        # A stand-in synopsis is a failed call, not an intentional empty: the
        # except: below marks it _failed, so it is never cached and retries later.
        if _is_placeholder(synopsis):
            raise RuntimeError("overview synopsis is a placeholder")
        quotes = []
        for q in (data.get("pull_quotes") or [])[:3]:
            t = (q.get("text") or "").strip().strip('"').strip("“”").strip()
            s = (q.get("source") or "").strip()
            if t and not _is_placeholder(t) and not _is_placeholder(s):
                quotes.append({"text": t[:400], "source": s[:80]})
        accolades = [str(a).strip()[:60] for a in (data.get("accolades") or [])[:4]
                     if str(a).strip() and not _is_placeholder(str(a))]
        return {"synopsis": synopsis, "pull_quotes": quotes, "accolades": accolades}
    except Exception as exc:
        log.warning("overview structuring failed: %s", exc)
        # Mark the failure so the caller doesn't cache it (self-heals once Claude
        # recovers) and can avoid showing unverified text. The relevance guard runs
        # inside this call, so on failure the text is NOT guard-checked.
        return {"synopsis": raw, "pull_quotes": [], "accolades": [], "_failed": True}


def _has_overview_content(d: dict) -> bool:
    return bool(d.get("synopsis") or d.get("pull_quotes") or d.get("accolades"))


@app.post("/v1/book-overview")
def get_book_overview(body: BookOverviewRequest, user_id: UserID):
    """Return a STRUCTURED overview {synopsis, pull_quotes:[{text,source}],
    accolades:[]}, cached shared per book_id. If the caller passes `description`
    (For You recs already store it), structure THAT and skip Google Books — so it
    works even when the GB quota is exhausted. Empty results are NOT cached, so a
    book self-heals once a description becomes available (e.g. GB quota resets)."""
    book_id = book_id_hash(body.title, body.author)
    ref = db.collection("book_overview_cache").document(book_id)
    snap = ref.get()
    if snap.exists:
        d = snap.to_dict() or {}
        # Only a current-version, non-empty structured cache counts; older/empty
        # entries fall through and re-structure (so stale-wrong overviews heal).
        if d.get("v") == OVERVIEW_CACHE_VERSION and _has_overview_content(d) and not d.get("_failed"):
            return {"synopsis": d.get("synopsis", ""),
                    "pull_quotes": d.get("pull_quotes", []),
                    "accolades": d.get("accolades", [])}

    raw = (body.description or "").strip()
    gb_sourced = False
    # Prefer Google Books (richer: quotes/accolades) when the caller passed no
    # description, or when the description is only a fallback (e.g. a short curated
    # list blurb from Discover). A provided non-fallback description is
    # authoritative (For You recs carry the full description) — skip GB.
    if body.description_is_fallback or not raw:
        with httpx.Client(timeout=5.0) as client:
            gb = (lookup_metadata(body.title, body.author, client=client).get("description") or "").strip()
        if gb:
            raw = gb
            gb_sourced = True

    structured = _structure_overview(raw, body.title, body.author)
    if structured.pop("_failed", False):
        # Claude was unavailable (e.g. out of credits / rate-limited). Do NOT cache,
        # so the book self-heals once Claude recovers. And never show unverified
        # Google Books text on failure — the relevance guard didn't run, so it may be
        # a wrong-book match; blank it. An authoritative/curated caller description is
        # at least the right book, so return that raw rather than nothing.
        return {"synopsis": "", "pull_quotes": [], "accolades": []} if gb_sourced else structured

    # Cache GB-sourced overviews and authoritative caller descriptions. Never cache a
    # fallback used only because GB was empty/over quota — leaving it uncached lets
    # the book upgrade to the richer GB overview once quota returns, instead of
    # freezing in the short curated text.
    cacheable = _has_overview_content(structured) and (gb_sourced or not body.description_is_fallback)
    if cacheable:
        ref.set({**structured, "v": OVERVIEW_CACHE_VERSION, "title": body.title,
                 "author": body.author, "cached_at": datetime.now(timezone.utc)})
    return structured


def _prewarm_overviews(books: list[dict]) -> None:
    """Pre-structure + cache overviews for a freshly-generated (cron) batch so
    their PDPs open with no structuring latency. Skips already-cached + empty
    descriptions; never caches empty results. Concurrent; best-effort. Cron-only
    (the inline generation path is already slow enough to risk the client timeout)."""
    targets = [b for b in books if (b.get("description") or "").strip()]
    if not targets:
        return

    def _one(b: dict) -> None:
        book_id = book_id_hash(b["title"], b["author"])
        ref = db.collection("book_overview_cache").document(book_id)
        d = ref.get().to_dict() or {}
        if d.get("v") == OVERVIEW_CACHE_VERSION and _has_overview_content(d):
            return
        structured = _structure_overview(b["description"], b["title"], b["author"])
        # A failed call returns the raw, unverified text marked _failed: never cache
        # it (get_book_overview would serve it as if the relevance guard had run).
        if not structured.get("_failed") and _has_overview_content(structured):
            ref.set({**structured, "v": OVERVIEW_CACHE_VERSION, "title": b["title"],
                     "author": b["author"], "cached_at": datetime.now(timezone.utc)})

    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(_one, targets))


def _cached_overviews(books: list[dict]) -> dict[str, dict]:
    """Current-version structured overviews for these books, keyed by book_id."""
    refs = [db.collection("book_overview_cache").document(book_id_hash(b.get("title", ""), b.get("author", "")))
            for b in books]
    out = {}
    for snap in (db.get_all(refs) if refs else []):
        d = (snap.to_dict() or {}) if snap.exists else {}
        if d.get("v") == OVERVIEW_CACHE_VERSION and _has_overview_content(d) and not d.get("_failed"):
            out[snap.id] = d
    return out


# ---------------------------------------------------------------------------
# GET /v1/debug/generation-info
# ---------------------------------------------------------------------------
@app.get("/v1/debug/generation-info", response_model=DebugInfoResponse)
def debug_info(user_id: UserID):
    doc = user_ref(user_id).get()
    if not doc.exists:
        return DebugInfoResponse(last_generation_timestamp=None, last_batch_size=None)
    data = doc.to_dict()

    # Phase 0: compute diversity metrics for the most recent batch.
    # Find the batch_id of the newest batch by scanning recommendation_col and
    # picking the doc with the latest created_at, then grouping the rest.
    genre_dist: dict[str, int] = {}
    era_dist: dict[str, int] = {}
    comfort_push_count = 0
    latest_batch_id: str | None = None

    all_recs = [r.to_dict() for r in recommendation_col(user_id).stream()]
    if all_recs:
        # Determine the most recent batch_id (by max created_at among docs that have one)
        batched = [r for r in all_recs if r.get("batch_id") and r.get("created_at")]
        if batched:
            # created_at may be a datetime or a Firestore Timestamp — both support comparison
            latest_batch_id = max(batched, key=lambda r: r["created_at"])["batch_id"]
            batch_recs = [r for r in batched if r["batch_id"] == latest_batch_id]
            for r in batch_recs:
                genre = (r.get("genre") or "").strip()
                era = (r.get("era") or "").strip()
                if genre:
                    genre_dist[genre] = genre_dist.get(genre, 0) + 1
                if era:
                    era_dist[era] = era_dist.get(era, 0) + 1
                if r.get("is_comfort_zone_push"):
                    comfort_push_count += 1

    return DebugInfoResponse(
        last_generation_timestamp=data.get("last_generation_timestamp"),
        last_batch_size=data.get("last_batch_size"),
        genre_distribution=genre_dist or None,
        era_distribution=era_dist or None,
        comfort_push_count=comfort_push_count if latest_batch_id else None,
        batch_id=latest_batch_id,
    )


# ---------------------------------------------------------------------------
# POST /v1/cron/generate-all  (Cloud Scheduler hook, runs nightly)
# ---------------------------------------------------------------------------
@app.post("/v1/cron/generate-all")
def cron_generate_all(
    x_cloud_scheduler_auth: Annotated[str | None, Header()] = None,
):
    """Trigger fresh recommendation generation for every user.

    Protected by a shared secret in the X-CloudScheduler-Auth header. Cap of
    60 unseen recs per user (PRD REC-04) is honored: if a user already has
    60+ undelivered, we skip their generation.
    """
    expected = os.environ.get("CRON_SECRET", "")
    if not expected or x_cloud_scheduler_auth != expected:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid cron secret")

    lock = _acquire_cron_lock("generate_all")
    if lock is None:
        log.warning("cron generate-all: another run holds the lock; skipping this delivery")
        return {"processed": 0, "skipped": 0, "failed": 0, "remaining": 0,
                "elapsed_seconds": 0.0, "skipped_reason": "already running"}
    try:
        return _generate_all_users()
    finally:
        _release_cron_lock("generate_all", lock)


# A lease outlives the longest possible run (the 1800s Cloud Run request timeout),
# so a run that dies without releasing it never blocks the next night.
CRON_LOCK_TTL_SECONDS = 1800


def _acquire_cron_lock(name: str) -> str | None:
    """Take a Firestore lease so overlapping deliveries of one Cloud Scheduler job
    don't both run. Returns the lease token, or None while a live lease is held.
    Scheduler delivery is at-least-once: on 09-22 it fired shelf-nightly-gen at
    10:00:30 and again at 10:02:10, and both full runs went ahead."""
    ref = db.collection("cron_locks").document(name)
    token = str(uuid.uuid4())
    now = datetime.now(timezone.utc)

    @firestore.transactional
    def _take(transaction) -> bool:
        snap = ref.get(transaction=transaction)
        if snap.exists:
            expires_at = (snap.to_dict() or {}).get("expires_at")
            if isinstance(expires_at, datetime) and expires_at > now:
                return False
        transaction.set(ref, {"token": token, "acquired_at": now,
                              "expires_at": now + timedelta(seconds=CRON_LOCK_TTL_SECONDS)})
        return True

    return token if _take(db.transaction()) else None


def _release_cron_lock(name: str, token: str) -> None:
    """Drop the lease if this run still holds it. Best-effort: a lease left behind
    expires on its own."""
    ref = db.collection("cron_locks").document(name)
    try:
        snap = ref.get()
        if snap.exists and (snap.to_dict() or {}).get("token") == token:
            ref.delete()
    except Exception as exc:
        log.warning("cron lock release failed for %s: %s", name, exc)


def _generate_all_users() -> dict:
    """The nightly run proper; cron_generate_all holds the lock around it."""
    started = time.monotonic()
    processed = 0
    skipped = 0
    failed = 0

    # Materialize the user list up front, iterating the stream manually (instead
    # of a plain `for`) so a mid-stream Firestore failure -- observed as both
    # DeadlineExceeded and an AttributeError from a broken retry path on some
    # client-library versions -- can be caught. A plain `for` loop lets that
    # exception escape from `next()` unguarded, killing the whole nightly run.
    # On such a failure we log and carry on with the users we did get; anyone
    # not reached self-heals on the next nightly run.
    users: list[tuple[str, datetime | None]] = []
    users_stream = db.collection("users").stream()
    while True:
        try:
            user = next(users_stream)
        except StopIteration:
            break
        except Exception as exc:
            log.exception(
                "cron generate-all: users stream failed after %d users; "
                "continuing with those (processed=%d, skipped=%d, failed=%d so far): %s",
                len(users), processed, skipped, failed, exc,
            )
            break
        last_gen = (user.to_dict() or {}).get("last_generation_timestamp")
        users.append((user.id, last_gen if isinstance(last_gen, datetime) else None))

    # Least-recently generated first, users never generated for at the very
    # front — so whoever the time budget cuts off tonight is first tomorrow.
    users.sort(key=lambda u: (u[1] is not None, u[1] or _EPOCH))

    remaining = 0
    for i, (user_id, _) in enumerate(users):
        elapsed = time.monotonic() - started
        if elapsed >= CRON_TIME_BUDGET_SECONDS:
            remaining = len(users) - i
            log.warning("cron generate-all: time budget spent after %.0fs; %d of %d users left unprocessed",
                        elapsed, remaining, len(users))
            break
        user_started = time.monotonic()
        try:
            # Skip if user already has too many unseen (PRD REC-03 / REC-04)
            unseen_count = sum(
                1 for _ in recommendation_col(user_id)
                .where("delivered", "==", False)
                .limit(60)
                .stream()
            )
            if unseen_count >= 60:
                skipped += 1
                continue
            _generate_recommendations(user_id, "books", is_cron=True)
            processed += 1
        except Exception as exc:
            log.exception("cron generation failed for user %s: %s", user_id, exc)
            failed += 1
        finally:
            log.info("cron generate-all: user %s took %.1fs", user_id, time.monotonic() - user_started)

    elapsed_seconds = round(time.monotonic() - started, 1)
    log.info("cron generate-all: processed=%d skipped=%d failed=%d remaining=%d in %.1fs",
             processed, skipped, failed, remaining, elapsed_seconds)
    return {"processed": processed, "skipped": skipped, "failed": failed,
            "remaining": remaining, "elapsed_seconds": elapsed_seconds}


# ---------------------------------------------------------------------------
# POST /v1/cron/nyt-backfill  (Cloud Scheduler hook, runs every few minutes)
# ---------------------------------------------------------------------------
@app.post("/v1/cron/nyt-backfill")
def cron_nyt_backfill(
    x_cloud_scheduler_auth: Annotated[str | None, Header()] = None,
):
    """Fetch the next page of NYT bestseller history and persist to Firestore.
    Designed to be called every 3 minutes by Cloud Scheduler so we stay under
    NYT's 500-req/day rate limit while building the full ~40k-book archive."""
    expected = os.environ.get("CRON_SECRET", "")
    if not expected or x_cloud_scheduler_auth != expected:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid cron secret")
    return nyt_history_fetch_next_pages(db, pages=1)


# ---------------------------------------------------------------------------
# Curated lists (Phase 1)
# ---------------------------------------------------------------------------
def _resolve_list_covers(books: list[dict]) -> dict[str, str]:
    """Resolve cover URLs for a list of books.

    Uses a global Firestore cache at list_cover_cache/{book_id} so each
    (title, author) is looked up at most once across all users. Misses
    are fetched concurrently from Open Library (primary) then Google
    Books (fallback) — mirrors the cover hierarchy used elsewhere."""
    cache_col = db.collection("list_cover_cache")
    refs = [cache_col.document(b["book_id"]) for b in books]
    snapshots = db.get_all(refs) if refs else []
    cached: dict[str, str] = {}
    for snap in snapshots:
        if snap.exists:
            d = snap.to_dict() or {}
            url = d.get("cover_url", "")
            # Ignore cached Google Books catalog-only placeholders ("image not
            # available") so they re-resolve (and the book is dropped if no real cover).
            if url and not _is_gb_catalog_url(url):
                cached[snap.id] = url

    misses = [b for b in books if b["book_id"] not in cached]
    resolved: dict[str, str] = dict(cached)

    if misses:
        def _fetch(book: dict) -> tuple[str, str]:
            with httpx.Client(timeout=5.0) as client:
                url = open_library_lookup_cover(book["title"], book["author"], client=client) \
                      or lookup_cover(book["title"], book["author"], client=client)
            return book["book_id"], url or ""

        with ThreadPoolExecutor(max_workers=8) as pool:
            futures = [pool.submit(_fetch, b) for b in misses]
            for fut in as_completed(futures):
                bid, url = fut.result()
                resolved[bid] = url

        # Persist cache (skip empty results so we retry next time)
        firestore_batch = db.batch()
        wrote_any = False
        now = datetime.now(timezone.utc)
        for b in misses:
            url = resolved.get(b["book_id"], "")
            if url:
                firestore_batch.set(cache_col.document(b["book_id"]), {
                    "cover_url": url,
                    "title": b["title"],
                    "author": b["author"],
                    "cached_at": now,
                })
                wrote_any = True
        if wrote_any:
            firestore_batch.commit()

    return resolved


def _user_list_status_map(user_id: str, domain: str) -> dict[tuple[str, str], str]:
    """Build a (title_lower, author_lower) → status map for the user.

    Status precedence (last write wins): passed/saved from reactions,
    then read from seeds (seeds override — a seed means the user has
    explicitly marked the book as read)."""
    status: dict[tuple[str, str], str] = {}

    for doc in reaction_col(user_id).where("domain", "==", domain).stream():
        d = doc.to_dict()
        title = (d.get("title") or "").lower().strip()
        author = (d.get("author") or "").lower().strip()
        if not title:
            continue
        kind = d.get("kind", "")
        if kind == ReactionKind.dismiss.value:
            status[(title, author)] = "passed"
        elif kind == ReactionKind.save.value:
            status[(title, author)] = "saved"
        elif kind in (ReactionKind.already_read_liked.value,
                      ReactionKind.already_read_disliked.value):
            status[(title, author)] = "read"

    for doc in seed_col(user_id).where("domain", "==", domain).stream():
        d = doc.to_dict()
        title = (d.get("title") or "").lower().strip()
        author = (d.get("author") or "").lower().strip()
        if not title:
            continue
        status[(title, author)] = "read"

    return status


# ---------------------------------------------------------------------------
# GET /v1/lists  (catalog — public, no auth)
# ---------------------------------------------------------------------------
@app.get("/v1/lists", response_model=ListCatalogResponse)
def get_lists():
    out: list[ListMetadata] = []
    for entry in load_catalog():
        m = ListMetadata(**entry)
        if entry["slug"] == COMMUNITY_LIST_SLUG:
            # book_count for the computed list comes from Firestore, not a file.
            # The stored list has headroom; a viewer is shown at most COMMUNITY_LIST_SIZE.
            m.book_count = min(len(_community_list_books()), COMMUNITY_LIST_SIZE)
        out.append(m)
    return ListCatalogResponse(lists=out)


# ---------------------------------------------------------------------------
# GET /v1/lists/{slug}  (metadata + books + per-user status)
# ---------------------------------------------------------------------------
@app.get("/v1/lists/{slug}", response_model=ListDetailResponse)
def get_list_detail(slug: str, user_id: UserID, domain: str = "books"):
    meta = get_list_metadata(slug)
    if not meta:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="list not found")

    if slug == COMMUNITY_LIST_SLUG:
        # Precomputed in Firestore; covers were resolved at compute time.
        books = _community_list_books()
        covers = {b["book_id"]: b.get("cover_url", "") for b in books}
    else:
        try:
            books = load_list_books(slug)
        except FileNotFoundError:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="list books not found")
        covers = _resolve_list_covers(books)

    user_status = _user_list_status_map(user_id, domain)
    is_community = slug == COMMUNITY_LIST_SLUG

    decorated = []
    for b in books:
        if is_community and len(decorated) >= COMMUNITY_LIST_SIZE:
            break
        cover_url = covers.get(b["book_id"], "")
        # Phase 2: omit books whose cover didn't resolve so a list never shows a
        # blank placeholder tile. (Community-list books are already cover-filtered
        # at compute time; this is the guard for the curated-list path.)
        if not _has_valid_cover(cover_url):
            continue
        key = (b["title"].lower().strip(), b["author"].lower().strip())
        # "Loved by readers" is for discovering other readers' books: hide the
        # viewer's own read books (Taste seeds and read reactions).
        if is_community and user_status.get(key) == "read":
            continue
        decorated.append(ListBookResponse(
            book_id=b["book_id"],
            title=b["title"],
            author=b["author"],
            year=b.get("year"),
            cover_url=cover_url,
            user_status=user_status.get(key),
            description=b.get("description", ""),
        ))

    return ListDetailResponse(
        slug=slug,
        metadata=ListMetadata(**meta),
        books=decorated,
    )


# ---------------------------------------------------------------------------
# POST /v1/lists/{slug}/react  (mark book from list as read/saved/passed)
# ---------------------------------------------------------------------------
@app.post("/v1/lists/{slug}/react", status_code=status.HTTP_201_CREATED)
def react_to_list_book(slug: str, body: ListReactionRequest, user_id: UserID):
    if not get_list_metadata(slug):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="list not found")

    source = f"list:{slug}"
    now = datetime.now(timezone.utc)
    title_key = body.title.lower().strip()
    author_key = body.author.lower().strip()

    if body.kind == ListReactionKind.read:
        # "Read" from a list = seed book (same weight as onboarding seeds).
        # Idempotent on (title, author) — mirrors add_seed_book behavior.
        for doc in seed_col(user_id).where("domain", "==", body.domain).stream():
            d = doc.to_dict()
            if (d.get("title", "").lower().strip() == title_key
                    and d.get("author", "").lower().strip() == author_key):
                return {"id": doc.id, "kind": "read"}
        doc_id = str(uuid.uuid4())
        seed_col(user_id).document(doc_id).set({
            "id": doc_id,
            "title": body.title,
            "author": body.author,
            "cover_url": body.cover_url,
            "domain": body.domain,
            "source": source,
            "created_at": now,
        })
        return {"id": doc_id, "kind": "read"}

    # saved → reaction kind=save, passed → reaction kind=dismiss
    rxn_kind = (ReactionKind.save if body.kind == ListReactionKind.saved
                else ReactionKind.dismiss)
    doc_id = str(uuid.uuid4())
    reaction_col(user_id).document(doc_id).set({
        "id": doc_id,
        "book_id": body.book_id,
        "kind": rxn_kind.value,
        "domain": body.domain,
        "title": body.title,
        "author": body.author,
        "cover_url": body.cover_url,
        "source": source,
        "created_at": now,
    })
    return {"id": doc_id, "kind": body.kind.value}


# ---------------------------------------------------------------------------
# DELETE /v1/lists/{slug}/react/{book_id}  (undo a list reaction)
# ---------------------------------------------------------------------------
@app.delete("/v1/lists/{slug}/react/{book_id}", status_code=status.HTTP_204_NO_CONTENT)
def unreact_to_list_book(slug: str, book_id: str, user_id: UserID, domain: str = "books"):
    if slug == COMMUNITY_LIST_SLUG:
        books = _community_list_books()
    else:
        try:
            books = load_list_books(slug)
        except FileNotFoundError:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="list not found")
    book = next((b for b in books if b["book_id"] == book_id), None)
    if not book:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="book not in list")

    title_key = book["title"].lower().strip()
    author_key = book["author"].lower().strip()
    source = f"list:{slug}"

    batch = db.batch()
    deleted_any = False

    # Remove matching seed docs (only those sourced from THIS list, so we
    # don't accidentally nuke onboarding seeds that happen to share a title)
    for doc in seed_col(user_id).where("domain", "==", domain).stream():
        d = doc.to_dict()
        if (d.get("title", "").lower().strip() == title_key
                and d.get("author", "").lower().strip() == author_key
                and d.get("source") == source):
            batch.delete(doc.reference)
            deleted_any = True

    # Remove matching reactions sourced from this list
    for doc in reaction_col(user_id).where("domain", "==", domain).stream():
        d = doc.to_dict()
        if (d.get("title", "").lower().strip() == title_key
                and d.get("author", "").lower().strip() == author_key
                and d.get("source") == source):
            batch.delete(doc.reference)
            deleted_any = True

    if deleted_any:
        batch.commit()


# ---------------------------------------------------------------------------
# Community list — "loved by readers" (aggregated from "Read & loved"
# reactions). Computed on a schedule, persisted to Firestore, served cheaply
# through the /v1/lists endpoints above.
# ---------------------------------------------------------------------------
def _clean_blurb(text: str, limit: int = 480) -> str:
    """Strip HTML / collapse whitespace from a Google Books description and
    truncate to a sentence-ish length for the list detail sheet."""
    if not text:
        return ""
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) > limit:
        text = text[:limit].rsplit(" ", 1)[0] + "…"
    return text


def _community_doc_ref():
    return db.collection("computed_lists").document(COMMUNITY_LIST_SLUG)


def _community_list_books() -> list[dict]:
    """Precomputed 'loved by readers' books (empty until the first recompute).
    Each dict carries book_id/title/author/cover_url/loved_count."""
    snap = _community_doc_ref().get()
    if not snap.exists:
        return []
    return (snap.to_dict() or {}).get("books", [])


def _compute_loved_by_readers(dry_run: bool = False) -> dict:
    """Rank books by the count of DISTINCT users who marked them
    'alreadyReadLiked'. Honors the per-user `contribute` flag, drops cover-less
    books, and stores up to COMMUNITY_STORED_SIZE so that after get_list_detail
    hides each viewer's own read books there are still COMMUNITY_LIST_SIZE to
    show. No LLM calls.

    Books with the same number of readers are ordered by their most recent love,
    so the list moves as readers react. (It used to count one seed user's Taste
    books as loves and rank that user's picks first, then sort the rest
    alphabetically. The list was mostly that user's own shelf and barely changed.)

    dry_run=True computes and returns the result WITHOUT persisting."""
    loved_users: dict[tuple[str, str], set[str]] = defaultdict(set)
    latest_love: dict[tuple[str, str], datetime] = {}
    titles: dict[tuple[str, str], dict] = {}

    def _register(title: str, author: str, uid: str, loved_at) -> None:
        t = (title or "").strip()
        a = (author or "").strip()
        if not t:
            return
        key = (t.lower(), a.lower())
        loved_users[key].add(uid)
        titles.setdefault(key, {"title": t, "author": a})
        if isinstance(loved_at, datetime) and loved_at > latest_love.get(key, _EPOCH):
            latest_love[key] = loved_at

    # 1) "Read & loved" reactions across contributing users
    for user in db.collection("users").stream():
        if (user.to_dict() or {}).get("contribute", True) is False:
            continue
        uid = user.id
        for doc in (reaction_col(uid)
                    .where("kind", "==", ReactionKind.already_read_liked.value)
                    .stream()):
            d = doc.to_dict()
            _register(d.get("title", ""), d.get("author", ""), uid, d.get("created_at"))

    # Rank by distinct readers desc; within a tier the most recently loved first,
    # then title for a stable order.
    def _rank(k: tuple[str, str]):
        return (-len(loved_users[k]), -latest_love.get(k, _EPOCH).timestamp(), k[0])
    ranked = sorted(titles.keys(), key=_rank)

    # Resolve covers for a candidate pool (headroom for the cover guard), drop
    # cover-less, then cap.
    candidates = [
        {
            "book_id": book_id_hash(titles[k]["title"], titles[k]["author"]),
            "title": titles[k]["title"],
            "author": titles[k]["author"],
            "loved_count": len(loved_users[k]),
        }
        for k in ranked[: COMMUNITY_STORED_SIZE * 2]
    ]
    covers = _resolve_list_covers(candidates) if candidates else {}

    books: list[dict] = []
    seen: set[str] = set()
    for c in candidates:
        if len(books) >= COMMUNITY_STORED_SIZE:
            break
        cover = covers.get(c["book_id"], "")
        if not _has_valid_cover(cover) or c["book_id"] in seen:
            continue
        seen.add(c["book_id"])
        books.append({**c, "cover_url": cover})

    # Enrich the final list with a year + short description from Google Books
    # (no LLM) so the detail sheet matches the curated lists instead of being bare.
    def _meta(book: dict) -> tuple[str, dict]:
        with httpx.Client(timeout=5.0) as cl:
            return book["book_id"], _cached_lookup_metadata(book["title"], book["author"], cl)
    if books:
        with ThreadPoolExecutor(max_workers=8) as pool:
            metas = dict(f.result() for f in as_completed([pool.submit(_meta, b) for b in books]))
        for b in books:
            m = metas.get(b["book_id"], {})
            b["year"] = m.get("year")
            b["description"] = _clean_blurb(m.get("description", ""))

    if not dry_run:
        _community_doc_ref().set({
            "books": books,
            "count": len(books),
            "updated_at": datetime.now(timezone.utc),
        })

    return {
        "count": len(books),
        "distinct_books_considered": len(titles),
        "books": [
            {"title": b["title"], "author": b["author"], "loved_count": b["loved_count"],
             "year": b.get("year"), "description": b.get("description", "")}
            for b in books
        ],
    }


@app.post("/v1/cron/recompute-community")
def cron_recompute_community(
    x_cloud_scheduler_auth: Annotated[str | None, Header()] = None,
):
    """Recompute and persist the 'loved by readers' list. Protected by the
    shared CRON_SECRET. Schedule daily via Cloud Scheduler (see deploy.sh)."""
    expected = os.environ.get("CRON_SECRET", "")
    if not expected or x_cloud_scheduler_auth != expected:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid cron secret")
    return _compute_loved_by_readers()


# ---------------------------------------------------------------------------
# User settings — community contribution toggle
# ---------------------------------------------------------------------------
@app.get("/v1/user/settings", response_model=UserSettingsResponse)
def get_user_settings(user_id: UserID):
    d = user_ref(user_id).get().to_dict() or {}
    return UserSettingsResponse(contribute=d.get("contribute", True))


@app.put("/v1/user/settings", response_model=UserSettingsResponse)
def update_user_settings(body: UserSettingsRequest, user_id: UserID):
    user_ref(user_id).set({"contribute": body.contribute}, merge=True)
    return UserSettingsResponse(contribute=body.contribute)


# ---------------------------------------------------------------------------
# DELETE /v1/user/data — wipe ALL Firestore data for the device token.
# Satisfies Apple's account/data-deletion requirement without an auth system:
# the iOS client also clears local SwiftData + the Keychain token, so a fresh
# anonymous token is minted on next launch. Hard delete; "lose history on
# reinstall" is the accepted trade-off.
# ---------------------------------------------------------------------------
@app.delete("/v1/user/data", status_code=status.HTTP_204_NO_CONTENT)
def delete_user_data(user_id: UserID):
    ref = user_ref(user_id)
    # Deleting a document does not delete its subcollections — purge each
    # (seed_books, reactions, recommendations, seen_books, …) explicitly.
    for coll in ref.collections():
        batch = db.batch()
        count = 0
        for doc in coll.stream():
            batch.delete(doc.reference)
            count += 1
            if count == 400:  # stay under Firestore's 500-write batch limit
                batch.commit()
                batch = db.batch()
                count = 0
        if count:
            batch.commit()
    ref.delete()


# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------
@app.get("/healthz")
def healthz():
    return {"status": "ok"}
