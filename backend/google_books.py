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


def _query_books(query: str, client: httpx.Client) -> str:
    """Run a single Google Books query and return the first cover URL, or ""."""
    params = {"q": query, "maxResults": "1", "printType": "books", "key": _API_KEY}
    url = f"{_BASE_URL}?{urllib.parse.urlencode(params)}"
    resp = client.get(url)
    if resp.status_code != 200:
        log.warning("google_books non-200: %s %s", resp.status_code, resp.text[:200])
        return ""
    items = resp.json().get("items") or []
    if not items:
        return ""
    links = items[0].get("volumeInfo", {}).get("imageLinks") or {}
    cover = links.get("thumbnail") or links.get("smallThumbnail") or ""
    return cover.replace("http://", "https://")


def lookup_cover(title: str, author: str, client: httpx.Client | None = None) -> str:
    """Return a HTTPS cover URL for the given title/author, or "" if not found.

    Tries a strict `intitle:"..." inauthor:...` query first, then falls back
    to a loose `title author` query if nothing matched.
    """
    if not _API_KEY:
        return ""

    owns_client = client is None
    if owns_client:
        client = httpx.Client(timeout=5.0)

    try:
        cover = _query_books(f'intitle:"{title}" inauthor:{author}', client)
        if not cover:
            cover = _query_books(f"{title} {author}", client)
        return cover
    except Exception as exc:
        log.warning("google_books lookup failed for %r / %r: %s", title, author, exc)
        return ""
    finally:
        if owns_client:
            client.close()
