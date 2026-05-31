"""
Shelf API – Cloud Run backend
Python 3.12 / FastAPI / Firestore / Claude API
"""
from __future__ import annotations

import json
import logging
import os
import uuid
from datetime import datetime, timezone
from typing import Annotated

import anthropic
from fastapi import Depends, FastAPI, Header, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from google.cloud import firestore

from models import (
    DebugInfoResponse,
    ListBookResponse,
    ListCatalogResponse,
    ListDetailResponse,
    ListMetadata,
    ListReactionKind,
    ListReactionRequest,
    ReactionKind,
    ReactionRequest,
    RecommendationResponse,
    SeenBooksRequest,
    SeedBookRequest,
    SeedBookResponse,
    SuggestionResponse,
    SuggestionsRequest,
)
from prompts import build_recommendations_prompt, build_suggestions_prompt
from google_books import lookup_cover, lookup_metadata
from open_library import lookup_cover as open_library_lookup_cover
from nyt_bestsellers import lookup_bestseller
from nyt_history import fetch_next_pages as nyt_history_fetch_next_pages, lookup_bestseller_history
from lists import get_list_metadata, load_catalog, load_list_books

from concurrent.futures import ThreadPoolExecutor, as_completed
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
claude = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])

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
MAX_EXCLUSION_LIST = 150  # cap to keep prompts bounded

# Sampling temperatures (tunable). For You uses a moderate temperature to move
# off the conservative, "obvious" default picks without drifting off-taste. The
# similar-books path stays lower because "closely related" wants less spread.
# Tune toward 0 to make a path more conservative without a code revert.
REC_TEMPERATURE = 0.7
SIMILAR_TEMPERATURE = 0.4

# Phase B lookback: how many of the user's most recent DELIVERED batches feed
# the cross-session genre/era counterbalance histogram. Bounded for token cost.
RECENT_BATCH_LOOKBACK = 3


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


def _enrich_book(b: dict, client: httpx.Client) -> None:
    """Add cover_url, NYT bestseller status, reading time, normalized fields
    to a book dict in-place. Used by both /v1/recommendations and
    /v1/onboarding/suggestions before persistence / response."""
    title = b.get("title", "")
    author = b.get("author", "")

    # Prefer Open Library for covers — far better data quality than Google Books.
    # Fall back to Google Books if Open Library has nothing.
    meta = lookup_metadata(title, author, client=client)   # still need for pageCount
    if not b.get("cover_url"):
        ol_cover = open_library_lookup_cover(title, author, client=client)
        b["cover_url"] = ol_cover or meta.get("cover_url", "")

    # Reading time: ~1.7 min per page on average (200wpm, ~340 words/page)
    page_count = meta.get("page_count")
    b["reading_time_minutes"] = round(page_count * 1.7) if isinstance(page_count, int) and page_count > 0 else None

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
        return _generate_recommendations(user_id, domain)

    # Otherwise return any undelivered cached recommendations.
    # CRITICAL: mark them delivered=True as we return, so the SAME books aren't
    # served on every poll — that was the source of the "I keep seeing the same
    # recs back-to-back" bug.
    unseen_docs = list(
        recommendation_col(user_id)
        .where("domain", "==", domain)
        .where("delivered", "==", False)
        .limit(10)
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
    return _generate_recommendations(user_id, domain)


def _generate_recommendations(user_id: str, domain: str, mark_delivered: bool = True) -> list[RecommendationResponse]:
    """Generate a fresh batch and persist to Firestore.

    mark_delivered=True (default) is used when the user is requesting recs right
    now — those go straight to delivered=True so we don't re-serve them.
    Cron-generated batches use mark_delivered=False so they're picked up by
    the next /v1/recommendations call.
    """
    # Gather seed books
    seeds = [d.to_dict() for d in seed_col(user_id).where("domain", "==", domain).stream()]
    if not seeds:
        return []

    # Build exclude list as "Title by Author" strings — Claude needs human-readable
    # context, not opaque UUIDs. Include every rec we've EVER generated for this user
    # (so the same book never appears in two consecutive Generate-more sessions),
    # plus the seed books themselves (no need to recommend what they already love),
    # plus any reaction that carries a title/author (e.g. list-saved/passed books
    # from Phase 1 don't have a corresponding recommendation_col entry).
    # Stream the user's full recommendation history once and reuse it for both
    # the exclusion list and the Phase B recent-mix histogram below.
    all_recs = [r.to_dict() for r in recommendation_col(user_id).stream()]
    exclude_set: set[str] = set()
    for d in all_recs:
        t, a = (d.get("title") or "").strip(), (d.get("author") or "").strip()
        if t:
            exclude_set.add(f"{t} by {a}" if a else t)
    for s in seeds:
        t, a = (s.get("title") or "").strip(), (s.get("author") or "").strip()
        if t:
            exclude_set.add(f"{t} by {a}" if a else t)
    for rxn in reaction_col(user_id).stream():
        d = rxn.to_dict()
        t, a = (d.get("title") or "").strip(), (d.get("author") or "").strip()
        if t:
            exclude_set.add(f"{t} by {a}" if a else t)
    exclude_list = sorted(exclude_set)[:MAX_EXCLUSION_LIST]

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

    prompt = build_recommendations_prompt(
        seeds=seeds,
        liked=liked,
        disliked=disliked,
        exclude_ids=exclude_list,
        domain=domain,
        count=10,
        recent_mix=recent_mix,
    )

    message = claude.messages.create(
        model="claude-opus-4-5",
        max_tokens=4096,
        temperature=REC_TEMPERATURE,
        messages=[{"role": "user", "content": prompt}],
    )
    raw = message.content[0].text
    books: list[dict] = json.loads(raw)

    # Validate `because_of` against the user's actual seed titles. If Claude
    # invents or distorts a title, drop the field rather than show a confusing
    # "Because you loved <book you don't own>" line in the UI. Also defensive
    # against Claude returning a non-string value for the field.
    seed_title_lookup = {s["title"].strip().lower(): s["title"] for s in seeds if s.get("title")}
    for b in books:
        raw_because = b.get("because_of")
        if isinstance(raw_because, str) and raw_because.strip():
            b["because_of"] = seed_title_lookup.get(raw_because.strip().lower())
        else:
            b["because_of"] = None

    # Enrich with Google Books cover + NYT bestseller + reading time
    with httpx.Client(timeout=5.0) as client:
        for b in books:
            _enrich_book(b, client=client)

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
            "delivered": mark_delivered,
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
@app.post("/v1/onboarding/suggestions", response_model=list[SuggestionResponse])
def get_suggestions(body: SuggestionsRequest, user_id: UserID):
    prompt = build_suggestions_prompt(
        seed_title=body.seed_book_title,
        seed_author=body.seed_book_author,
        domain=body.domain,
        count=body.count,
        exclude=body.exclude,
    )
    message = claude.messages.create(
        model="claude-opus-4-5",
        max_tokens=2048,  # bumped — blurbs need more tokens
        temperature=SIMILAR_TEMPERATURE,
        messages=[{"role": "user", "content": prompt}],
    )
    raw = message.content[0].text
    books: list[dict] = json.loads(raw)

    # Server-side dedup against the supplied exclude list (lowercased title|author)
    exclude_keys = {item.lower().strip() for item in (body.exclude or [])}
    def _key(b: dict) -> str:
        return f"{b.get('title','').lower().strip()}|{b.get('author','').lower().strip()}"
    books = [b for b in books if _key(b) not in exclude_keys]

    # Enrich with Google Books cover + NYT bestseller + reading time
    with httpx.Client(timeout=5.0) as client:
        for b in books:
            _enrich_book(b, client=client)

    return [SuggestionResponse(id=str(uuid.uuid4()), **b) for b in books]


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

    processed = 0
    skipped = 0
    failed = 0
    for user in db.collection("users").stream():
        user_id = user.id
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
        try:
            _generate_recommendations(user_id, "books", mark_delivered=False)
            processed += 1
        except Exception as exc:
            log.exception("cron generation failed for user %s: %s", user_id, exc)
            failed += 1
    return {"processed": processed, "skipped": skipped, "failed": failed}


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
            if d.get("cover_url"):
                cached[snap.id] = d["cover_url"]

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
    return ListCatalogResponse(
        lists=[ListMetadata(**entry) for entry in load_catalog()]
    )


# ---------------------------------------------------------------------------
# GET /v1/lists/{slug}  (metadata + books + per-user status)
# ---------------------------------------------------------------------------
@app.get("/v1/lists/{slug}", response_model=ListDetailResponse)
def get_list_detail(slug: str, user_id: UserID, domain: str = "books"):
    meta = get_list_metadata(slug)
    if not meta:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="list not found")
    try:
        books = load_list_books(slug)
    except FileNotFoundError:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="list books not found")

    covers = _resolve_list_covers(books)
    user_status = _user_list_status_map(user_id, domain)

    decorated = []
    for b in books:
        key = (b["title"].lower().strip(), b["author"].lower().strip())
        decorated.append(ListBookResponse(
            book_id=b["book_id"],
            title=b["title"],
            author=b["author"],
            year=b.get("year"),
            cover_url=covers.get(b["book_id"], ""),
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
# Health check
# ---------------------------------------------------------------------------
@app.get("/healthz")
def healthz():
    return {"status": "ok"}
