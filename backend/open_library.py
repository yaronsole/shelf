"""Open Library cover lookup.

Open Library has much better cover-art coverage and quality than Google Books
(which often returns back-cover scans, text-only pages, or partial-cover
images). No API key required.

Lookup flow:
  1. GET https://openlibrary.org/search.json?title=X&author=Y&limit=5
  2. Pick the first result that has a `cover_i` field
  3. Cover URL: https://covers.openlibrary.org/b/id/{cover_i}-L.jpg
"""

from __future__ import annotations

import logging
import urllib.parse
from typing import Optional

import httpx

log = logging.getLogger(__name__)

_SEARCH_URL = "https://openlibrary.org/search.json"
_COVER_URL_FMT = "https://covers.openlibrary.org/b/id/{cid}-L.jpg"


def lookup_cover(title: str, author: str, client: httpx.Client | None = None) -> Optional[str]:
    """Return a high-quality Open Library cover URL or None if not found."""
    if not title:
        return None
    owns_client = client is None
    if owns_client:
        client = httpx.Client(timeout=5.0)
    try:
        params = {"title": title, "author": author, "limit": "5", "sort": "editions", "fields": "title,author_name,cover_i,first_publish_year,edition_count"}
        url = f"{_SEARCH_URL}?{urllib.parse.urlencode(params)}"
        resp = client.get(url, headers={"User-Agent": "ShelfApp/2.0 (yaronsole@github)"})
        if resp.status_code != 200:
            log.warning("open_library non-200: %s %s", resp.status_code, resp.text[:200])
            return None
        docs = resp.json().get("docs") or []
        for d in docs:
            cid = d.get("cover_i")
            if cid:
                return _COVER_URL_FMT.format(cid=cid)
        return None
    except Exception as exc:
        log.warning("open_library lookup failed for %r / %r: %s", title, author, exc)
        return None
    finally:
        if owns_client:
            client.close()
