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


def _query_books(query: str, client: httpx.Client) -> dict:
    """Run a single Google Books query and return a dict with cover/page count/etc.,
    or an empty dict if nothing matched."""
    params = {"q": query, "maxResults": "1", "printType": "books", "key": _API_KEY}
    url = f"{_BASE_URL}?{urllib.parse.urlencode(params)}"
    resp = client.get(url)
    if resp.status_code != 200:
        log.warning("google_books non-200: %s %s", resp.status_code, resp.text[:200])
        return {}
    items = resp.json().get("items") or []
    if not items:
        return {}
    info = items[0].get("volumeInfo", {})
    links = info.get("imageLinks") or {}
    cover = links.get("thumbnail") or links.get("smallThumbnail") or ""
    return {
        "cover_url": cover.replace("http://", "https://"),
        "page_count": info.get("pageCount"),
    }


def lookup_metadata(title: str, author: str, client: httpx.Client | None = None) -> dict:
    """Return cover URL + page count for the given title/author.

    Always returns a dict with keys cover_url (str), page_count (int|None).
    Falls back to a loose query if the strict one fails.
    """
    empty = {"cover_url": "", "page_count": None}
    if not _API_KEY:
        return empty

    owns_client = client is None
    if owns_client:
        client = httpx.Client(timeout=5.0)
    try:
        result = _query_books(f'intitle:"{title}" inauthor:{author}', client)
        if not result.get("cover_url"):
            result = _query_books(f"{title} {author}", client)
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
