"""Optional, server-only aggregate ratings. Never retrieve individual reviews.

Audited work IDs handle known aliases and adaptations. Other books require one
exact title AND full-author match; ambiguity is absence, never a popularity tie-break.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
import hashlib
import json
import logging
import math
from pathlib import Path
import threading
import unicodedata

import httpx

log = logging.getLogger(__name__)
ENDPOINT = "https://api.hardcover.app/v1/graphql"
MIN_RATINGS = 100
CACHE_VERSION = 1
MAX_AGE = timedelta(days=7)
SEARCH = """query ShelfRatingSearch($q: String!) {
  search(query: $q, query_type: "Book", per_page: 10, page: 1) { results }
}"""
DETAILS = """query ShelfBookRatings($ids: [Int!]!) {
  books(where: {id: {_in: $ids}}) {
    id title slug rating ratings_count book_status_id canonical_id is_partial_book
    contributions { author { name } }
  }
}"""


def normalized(value: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFKD", value).casefold() if c.isalnum())


def identity(title: str, author: str) -> str:
    return normalized(title) + "|" + normalized(author)


def load_mappings() -> dict:
    rows = json.loads((Path(__file__).parent / "data" / "hardcover_matches.json").read_text())["books"]
    return {identity(b["title"], b["author"]): b for b in rows}


def verified_match(book: dict, title: str, author: str, mapping: dict | None = None) -> bool:
    if book.get("book_status_id") != 1 or book.get("canonical_id") or book.get("is_partial_book"):
        return False
    expected_title = mapping["hardcover_title"] if mapping else title
    expected_authors = mapping["hardcover_authors"] if mapping else [author]
    authors = [c.get("author", {}).get("name", "") for c in book.get("contributions", []) if c.get("author")]
    # No subtitle stripping or fuzzy author token overlap: those accepted excerpts
    # and adaptations in the audit. Known short-title aliases are explicitly mapped.
    return (bool(normalized(expected_title)) and bool(normalized(author))
            and normalized(book.get("title", "")) == normalized(expected_title)
            and any(normalized(a) == normalized(b) for a in authors for b in expected_authors))


def public_rating(record: dict | None, now: datetime) -> dict | None:
    if not record or record.get("source") != "Hardcover":
        return None
    score, count, fetched = record.get("score"), record.get("ratings_count"), record.get("fetched_at")
    if not isinstance(fetched, datetime) or fetched.tzinfo is None or not timedelta(0) <= now - fetched < MAX_AGE:
        return None
    if (type(score) not in (int, float) or not math.isfinite(score) or not 0 < score <= 5
            or type(count) is not int or count < MIN_RATINGS):
        return None
    # Keep volume and provider IDs internal. The client gets only display data.
    return {"score": score, "source": "Hardcover", "fetched_at": fetched.isoformat()}


class RatingService:
    def __init__(self, db, token: str, *, mappings=None, client_factory=None, clock=None):
        self.db = db
        self.token = token.removeprefix("Bearer ").strip()
        self.mappings = load_mappings() if mappings is None else mappings
        self.client_factory = client_factory or (lambda: httpx.Client(timeout=3.0))
        self.clock = clock or (lambda: datetime.now(timezone.utc))
        self.locks = [threading.Lock() for _ in range(32)]
        self.retry_after = datetime.min.replace(tzinfo=timezone.utc)

    def query(self, client, query, variables):
        response = client.post(ENDPOINT, json={"query": query, "variables": variables},
                               headers={"Authorization": "Bearer " + self.token,
                                        "User-Agent": "Shelf-Book-Ratings/1.0"})
        if response.status_code in (401, 403, 429):
            # Prevent a key/quota failure from cascading across different books.
            self.retry_after = self.clock() + timedelta(minutes=5)
        response.raise_for_status()
        payload = response.json()
        if payload.get("errors") or not isinstance(payload.get("data"), dict):
            raise ValueError("Invalid rating provider response")
        return payload["data"]

    def lookup(self, title, author):
        mapping = self.mappings.get(identity(title, author))
        # Audited duplicates remain hidden until an explicit work mapping is made.
        if mapping and mapping.get("hardcover_id") is None:
            return None
        with self.client_factory() as client:
            if mapping:
                ids = [mapping["hardcover_id"]]
            else:
                results = self.query(client, SEARCH, {"q": f"{title} {author}"})["search"]["results"]
                if isinstance(results, str):
                    results = json.loads(results)
                ids = list({int(h["document"]["id"]) for h in results["hits"]
                            if str(h.get("document", {}).get("id", "")).isdigit()})[:10]
                if not ids:
                    return None
            books = self.query(client, DETAILS, {"ids": ids})["books"]
            redirects = list({b["canonical_id"] for b in books if b.get("canonical_id")})
            if redirects:
                books += self.query(client, DETAILS, {"ids": redirects})["books"]
            matches = {b["id"]: b for b in books if verified_match(b, title, author, mapping)}
            if len(matches) != 1:
                return None
            book = next(iter(matches.values()))
            return {"source": "Hardcover", "hardcover_id": book["id"],
                    "source_url": "https://hardcover.app/books/" + book["slug"],
                    "score": book.get("rating"), "ratings_count": book.get("ratings_count"),
                    "fetched_at": self.clock()}

    def get(self, title: str, author: str) -> dict | None:
        if not self.token or not normalized(title) or not normalized(author):
            return None
        key = hashlib.sha256(identity(title, author).encode()).hexdigest()
        # Bounded stripe locks coalesce repeated requests without retaining a lock
        # per arbitrary title. A busy stripe fails quietly rather than delaying UI.
        lock = self.locks[int(key[:4], 16) % len(self.locks)]
        if not lock.acquire(timeout=0.1):
            return None
        try:
            now = self.clock()
            ref = self.db.collection("book_rating_cache").document(key)
            cached = ref.get(timeout=2, retry=None).to_dict() or {}
            expires = cached.get("expires_at")
            if (cached.get("v") == CACHE_VERSION and isinstance(expires, datetime)
                    and expires.tzinfo is not None and now < expires):
                return public_rating(cached.get("rating"), now)
            if now < self.retry_after:
                return None
            try:
                rating = self.lookup(title, author)
                ttl = MAX_AGE if public_rating(rating, self.clock()) else timedelta(days=1)
            except (httpx.HTTPError, ValueError, KeyError, TypeError):
                # Never log headers, credentials or provider payloads.
                log.warning("Book rating provider unavailable; rating omitted")
                rating, ttl = None, timedelta(minutes=5)
            ref.set({"v": CACHE_VERSION, "title": title, "author": author,
                     "rating": rating, "expires_at": self.clock() + ttl}, timeout=2, retry=None)
            return public_rating(rating, self.clock())
        except Exception:
            # Firestore outages must not make this optional feature break the PDP.
            log.warning("Book rating cache unavailable; rating omitted")
            return None
        finally:
            lock.release()
