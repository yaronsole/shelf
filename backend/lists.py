"""Curated lists support — pure helpers (no FastAPI/Firestore dependencies).

Route handlers live in main.py so they can use the shared `db`, `get_user_id`,
and httpx client patterns established there. This module just owns the data
files, the stable book_id derivation, and the load logic.
"""
from __future__ import annotations

import hashlib
import json
import os
from functools import lru_cache
from pathlib import Path

LISTS_DIR = Path(os.path.dirname(__file__)) / "data" / "lists"
INDEX_FILE = LISTS_DIR / "_index.json"
BOOK_ID_LEN = 16  # chars from the sha1 hex digest — collision-safe at our scale


def book_id_hash(title: str, author: str) -> str:
    """Stable client-facing book id derived from (title, author). The same
    book always hashes to the same id so iOS can track read/saved status
    across sessions and devices."""
    key = f"{title.lower().strip()}|{author.lower().strip()}"
    return hashlib.sha1(key.encode("utf-8")).hexdigest()[:BOOK_ID_LEN]


@lru_cache(maxsize=1)
def load_catalog() -> list[dict]:
    """Load the list catalog from _index.json, augmented with book_count
    derived from each list's books file. Cached for the lifetime of the
    Cloud Run instance — bust by redeploying."""
    with open(INDEX_FILE, "r", encoding="utf-8") as fp:
        data = json.load(fp)
    entries = data.get("lists", [])
    for entry in entries:
        slug = entry["slug"]
        try:
            books = load_list_books(slug)
            entry["book_count"] = len(books)
        except FileNotFoundError:
            entry["book_count"] = 0
    entries.sort(key=lambda e: e.get("sort_order", 999))
    return entries


@lru_cache(maxsize=16)
def load_list_books(slug: str) -> list[dict]:
    """Load the books for a given list slug. Each entry gets `book_id`
    added if missing. Raises FileNotFoundError if the slug has no data file."""
    path = LISTS_DIR / f"{slug}.json"
    with open(path, "r", encoding="utf-8") as fp:
        data = json.load(fp)
    books = data.get("books", [])
    for b in books:
        if "book_id" not in b:
            b["book_id"] = book_id_hash(b["title"], b["author"])
    return books


def get_list_metadata(slug: str) -> dict | None:
    for entry in load_catalog():
        if entry["slug"] == slug:
            return entry
    return None
