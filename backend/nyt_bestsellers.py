"""NYT Bestsellers integration.

We cache the current "full overview" of all NYT bestseller lists in-memory at
backend startup, refreshed lazily (24h TTL). Lookups during recommendation
enrichment are O(1) by normalized "title|author" key.

The history endpoint would give us books that were *ever* on a list, but
that's 40k+ books across thousands of pages and would require multi-day
backfill against NYT's strict 500-req/day quota. Current overview hits the
hot books most users will recognize.
"""

from __future__ import annotations

import logging
import os
import re
import time
from typing import Optional

import httpx

log = logging.getLogger(__name__)

_API_KEY = os.environ.get("NYT_API_KEY", "")
_OVERVIEW_URL = "https://api.nytimes.com/svc/books/v3/lists/full-overview.json"

_CACHE: dict[str, dict] = {}   # normalized key → {list_name, rank, weeks_on_list}
_CACHE_TS: float = 0.0
_TTL = 24 * 60 * 60   # refresh once a day


def _normalize(s: str) -> str:
    """Lowercase, strip punctuation+articles, collapse whitespace."""
    s = s.lower().strip()
    # Remove "the", "a", "an" prefix to improve matching (NYT often uses "The X" vs Claude "X")
    s = re.sub(r"^(the|a|an)\s+", "", s)
    # Strip subtitle after a colon ("Sapiens: A Brief History of Humankind" → "sapiens")
    s = s.split(":", 1)[0]
    # Strip non-alphanumerics
    s = re.sub(r"[^a-z0-9 ]", "", s)
    return re.sub(r"\s+", " ", s).strip()


def _book_key(title: str, author: str) -> str:
    return f"{_normalize(title)}|{_normalize(author)}"


def _refresh_cache() -> None:
    """Pull NYT full-overview into _CACHE. Safe to call from request path —
    only hits the network when TTL has expired and the API key is set."""
    global _CACHE, _CACHE_TS
    if not _API_KEY:
        return
    if _CACHE and (time.time() - _CACHE_TS) < _TTL:
        return

    try:
        with httpx.Client(timeout=8.0) as client:
            resp = client.get(_OVERVIEW_URL, params={"api-key": _API_KEY})
        if resp.status_code != 200:
            log.warning("NYT overview returned %s: %s", resp.status_code, resp.text[:200])
            return
        data = resp.json()
        new_cache: dict[str, dict] = {}
        for lst in data.get("results", {}).get("lists", []):
            list_name = lst.get("display_name", "")
            for book in lst.get("books", []):
                title = book.get("title", "")
                author = book.get("author", "")
                if not title or not author:
                    continue
                key = _book_key(title, author)
                existing = new_cache.get(key)
                # If a book is on multiple lists, keep the one with the most weeks
                if existing and existing.get("weeks_on_list", 0) >= book.get("weeks_on_list", 0):
                    continue
                new_cache[key] = {
                    "list_name": list_name,
                    "rank": book.get("rank"),
                    "weeks_on_list": book.get("weeks_on_list"),
                }
        _CACHE = new_cache
        _CACHE_TS = time.time()
        log.info("NYT bestseller cache refreshed — %d entries", len(_CACHE))
    except Exception as exc:
        log.warning("NYT cache refresh failed: %s", exc)


def lookup_bestseller(title: str, author: str) -> Optional[dict]:
    """Return {list_name, rank, weeks_on_list} or None if not on any current
    NYT bestseller list."""
    _refresh_cache()
    return _CACHE.get(_book_key(title, author))
