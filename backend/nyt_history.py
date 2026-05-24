"""NYT Bestseller HISTORY backfill via dated-list endpoint.

NYT's /history.json endpoint is broken (returns 400 "invalid date"), so we
instead walk backwards through time hitting the dated-list endpoint:
  GET /lists/{YYYY-MM-DD}/{list-name}.json

For each week we fetch the major lists (hardcover-fiction and
hardcover-nonfiction have existed since 1950s). 15 books per list × 2 lists
× 52 weeks/yr × 50 years = ~7,800 unique entries. At 480 cron ticks/day,
full backfill in ~10 days.

State (Firestore `nyt_backfill_state/state`):
  cursor_date     ISO date string we're working on (decremented weekly)
  list_index      which list we're on for that date (0 or 1)
  earliest_date   stop when cursor_date <= this
  done            true when finished

Results stored in Firestore `nyt_history` collection, doc id = normalized
title|author key, content = {title, author, max_weeks_on_list, list_name}.
"""

from __future__ import annotations

import logging
import os
from datetime import date, timedelta
from typing import Optional

import httpx
from google.cloud import firestore

from nyt_bestsellers import _book_key

log = logging.getLogger(__name__)

_BASE_URL = "https://api.nytimes.com/svc/books/v3/lists"
_HISTORY_COLLECTION = "nyt_history"
_STATE_DOC = ("nyt_backfill_state", "state")

# Major lists with the longest run; ordered roughly by importance
_LISTS = ["hardcover-fiction", "hardcover-nonfiction"]

# Walk backwards from "today" by 7-day increments. Stop at this earliest date.
_EARLIEST_DATE = "1980-01-01"

_LOOKUP_CACHE: dict[str, Optional[dict]] = {}


def _api_key() -> str:
    return os.environ.get("NYT_API_KEY", "")


def _initial_state() -> dict:
    # Round today's date down to a Sunday (NYT publishes Sundays)
    today = date.today()
    return {
        "cursor_date": today.isoformat(),
        "list_index": 0,
        "earliest_date": _EARLIEST_DATE,
        "done": False,
    }


def fetch_next_pages(db: firestore.Client, pages: int = 1) -> dict:
    """Fetch the next list-for-a-week from the dated-list endpoint and persist.

    Each "page" here is one (date, list) pair = 15 books.
    """
    if not _api_key():
        return {"error": "NYT_API_KEY not set"}

    state_ref = db.collection(_STATE_DOC[0]).document(_STATE_DOC[1])
    state = state_ref.get().to_dict() or _initial_state()
    if state.get("done"):
        return {"done": True, "cursor_date": state.get("cursor_date"), "pages_fetched": 0, "books_upserted": 0}

    cursor = date.fromisoformat(state["cursor_date"])
    list_index = int(state.get("list_index", 0))
    earliest = date.fromisoformat(state.get("earliest_date", _EARLIEST_DATE))

    books_upserted = 0
    pages_fetched = 0
    done = False

    with httpx.Client(timeout=15.0) as client:
        for _ in range(pages):
            if cursor < earliest:
                done = True
                break

            list_name = _LISTS[list_index]
            url = f"{_BASE_URL}/{cursor.isoformat()}/{list_name}.json"
            try:
                resp = client.get(url, params={"api-key": _api_key()})
            except Exception as exc:
                log.warning("NYT dated-list request failed for %s/%s: %s", cursor, list_name, exc)
                break
            if resp.status_code == 429:
                log.warning("NYT dated-list rate-limited at %s/%s", cursor, list_name)
                break

            # 200 with no books, or 404 ("list not found" for a date that didn't have it yet)
            # are both fine — advance and continue
            if resp.status_code == 200:
                data = resp.json()
                books = (data.get("results") or {}).get("books", []) or []
                if books:
                    batch = db.batch()
                    for b in books:
                        title = (b.get("title", "") or "").strip()
                        author = (b.get("author", "") or "").strip()
                        if not title or not author:
                            continue
                        weeks = int(b.get("weeks_on_list", 0) or 0)
                        key = _book_key(title, author)
                        doc_ref = db.collection(_HISTORY_COLLECTION).document(key)
                        # Read-then-write so we keep the max weeks across appearances
                        existing = doc_ref.get().to_dict() or {}
                        prior_weeks = int(existing.get("max_weeks_on_list", 0) or 0)
                        if weeks >= prior_weeks:
                            batch.set(doc_ref, {
                                "title": title,
                                "author": author,
                                "max_weeks_on_list": weeks,
                                "list_name": data.get("results", {}).get("display_name", list_name),
                            }, merge=True)
                            books_upserted += 1
                    batch.commit()
            elif resp.status_code != 404:
                log.warning("NYT dated-list non-200 for %s/%s: %s %s", cursor, list_name, resp.status_code, resp.text[:200])

            # Advance: next list for same date, or back one week if we've done all lists
            list_index += 1
            if list_index >= len(_LISTS):
                list_index = 0
                cursor = cursor - timedelta(days=7)
            pages_fetched += 1

    state_ref.set({
        "cursor_date": cursor.isoformat(),
        "list_index": list_index,
        "earliest_date": earliest.isoformat(),
        "done": done,
    }, merge=True)
    return {
        "pages_fetched": pages_fetched,
        "books_upserted": books_upserted,
        "cursor_date": cursor.isoformat(),
        "list_index": list_index,
        "done": done,
    }


def lookup_bestseller_history(db: firestore.Client, title: str, author: str) -> Optional[dict]:
    """Return historical bestseller data for the given book or None."""
    if not _api_key():
        return None
    key = _book_key(title, author)
    if key in _LOOKUP_CACHE:
        return _LOOKUP_CACHE[key]
    doc = db.collection(_HISTORY_COLLECTION).document(key).get()
    result = doc.to_dict() if doc.exists else None
    _LOOKUP_CACHE[key] = result
    return result
