"""Google Books cover-art enrichment.

Used to look up cover URLs for Claude-generated suggestions and recommendations
before returning them to the client. Falls back gracefully (returns "") on any
error so a failed enrichment never blocks the response.
"""

from __future__ import annotations

import logging
import os
import urllib.parse

import httpx

log = logging.getLogger(__name__)

_BASE_URL = "https://www.googleapis.com/books/v1/volumes"
_API_KEY = os.environ.get("GOOGLE_BOOKS_API_KEY", "")


_JUNK_PUBLISHERS = {"createspace", "independently published", "lulu", "scholar select"}


def _score_volume(item: dict, expected_title: str) -> int:
    """Score a Google Books volume. Higher = cleaner / more representative edition."""
    info = item.get("volumeInfo", {}) or {}
    links = info.get("imageLinks") or {}
    if not (links.get("thumbnail") or links.get("smallThumbnail")):
        return -1000  # disqualify if no cover

    score = 0
    raw_title = (info.get("title", "") or "").lower().strip()
    expected = expected_title.lower().strip()
    if raw_title == expected:
        score += 100
    if raw_title.startswith(expected):
        score += 30
    if ":" in raw_title and ":" not in expected:
        score -= 25  # "Author Name: Title" edition

    if (info.get("categories") or []):
        score += 20
    if len(info.get("description", "") or "") > 100:
        score += 15
    if isinstance(info.get("pageCount"), int) and info["pageCount"] >= 100:
        score += 10

    publisher = (info.get("publisher", "") or "").lower()
    if any(jp in publisher for jp in _JUNK_PUBLISHERS):
        score -= 40

    # Strongly prefer English editions — langRestrict alone lets some through,
    # which produced foreign-language descriptions/years in the community list.
    if (info.get("language") or "en").lower() != "en":
        score -= 200

    cover = links.get("thumbnail") or links.get("smallThumbnail") or ""
    if "edge=curl" in cover:
        score += 5
    return score


def _query_books(query: str, client: httpx.Client, expected_title: str = "") -> dict:
    """Run a Google Books query and pick the highest-scoring volume.

    Returns {cover_url, page_count} or {} if nothing matched.
    """
    params = {
        "q": query,
        "maxResults": "10",  # pull more so we can pick the best edition
        "printType": "books",
        "langRestrict": "en",
        "key": _API_KEY,
    }
    url = f"{_BASE_URL}?{urllib.parse.urlencode(params)}"
    resp = client.get(url)
    if resp.status_code != 200:
        log.warning("google_books non-200: %s %s", resp.status_code, resp.text[:200])
        return {}
    items = resp.json().get("items") or []
    # Skip Google Books catalog-only editions (volume id ending "AAJ"): they serve
    # an "image not available" placeholder cover and frequently carry a wrong or
    # empty description. Prefer real (preview/ebook) editions; if only catalog
    # editions exist, treat as no result (cover falls back / book is filtered).
    items = [it for it in items if not (it.get("id") or "").endswith("AAJ")]
    if not items:
        return {}

    target = expected_title or ""
    best = max(items, key=lambda it: _score_volume(it, target))
    if _score_volume(best, target) < 0:
        return {}
    info = best.get("volumeInfo", {}) or {}
    links = info.get("imageLinks") or {}
    cover = links.get("thumbnail") or links.get("smallThumbnail") or ""
    published = (info.get("publishedDate", "") or "")[:4]
    return {
        "cover_url": cover.replace("http://", "https://"),
        "page_count": info.get("pageCount"),
        "description": info.get("description", "") or "",
        "year": int(published) if published.isdigit() else None,
    }


def lookup_metadata(title: str, author: str, client: httpx.Client | None = None) -> dict:
    """Return cover URL + page count for the given title/author.

    Always returns a dict with keys cover_url (str), page_count (int|None).
    Falls back to a loose query if the strict one fails.
    """
    empty = {"cover_url": "", "page_count": None, "description": "", "year": None}
    if not _API_KEY:
        return empty

    owns_client = client is None
    if owns_client:
        client = httpx.Client(timeout=5.0)
    try:
        result = _query_books(f'intitle:"{title}" inauthor:{author}', client, expected_title=title)
        if not result.get("cover_url"):
            result = _query_books(f"{title} {author}", client, expected_title=title)
        return result or empty
    except Exception as exc:
        log.warning("google_books lookup failed for %r / %r: %s", title, author, exc)
        return empty
    finally:
        if owns_client:
            client.close()


# Back-compat for existing callers that only want a cover URL.
def lookup_cover(title: str, author: str, client: httpx.Client | None = None) -> str:
    return lookup_metadata(title, author, client=client).get("cover_url", "")
