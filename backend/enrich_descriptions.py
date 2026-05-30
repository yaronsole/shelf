#!/usr/bin/env python3
"""One-off script: enrich every book in data/lists/*.json with a friend-voice blurb.

Run manually — NOT imported at request time.

Usage:
    python enrich_descriptions.py [--force]

    --force  Overwrite descriptions that are already filled.

Env vars required:
    ANTHROPIC_API_KEY
    GOOGLE_BOOKS_API_KEY  (optional but improves coverage)

Output: prints a summary (filled / skipped / failed) and writes descriptions
        back into the JSON files in place. Commit the updated JSON after
        reviewing a sample of the generated blurbs.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import urllib.parse
from pathlib import Path

import httpx
import anthropic

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
log = logging.getLogger(__name__)

LISTS_DIR = Path(__file__).parent / "data" / "lists"
ANTHROPIC_MODEL = "claude-opus-4-5"

SYSTEM_PROMPT = """\
You are a well-read friend giving honest, specific takes on books — not a publisher or marketer.
When I give you a book title, author, and a raw description, rewrite it as 1–2 tight sentences in
that friend voice: concrete, opinionated, specific. No sweeping adjectives like "sweeping",
"breathtaking", "powerful", or "compelling". No phrases like "a tale of" or "a story about".
Just say what the book actually does and why a reader might care.

CRITICAL RULE: If the raw description field is empty, return an empty string exactly ("").
Never invent or hallucinate details when you have no source description. Return "" only.\
"""

# ---------------------------------------------------------------------------
# Google Books description fetch (separate from lookup_metadata which only
# returns cover_url + page_count)
# ---------------------------------------------------------------------------

_GB_BASE = "https://www.googleapis.com/books/v1/volumes"
_GB_KEY = os.environ.get("GOOGLE_BOOKS_API_KEY", "")


def _fetch_google_description(title: str, author: str, isbn: str | None, client: httpx.Client) -> str:
    if not _GB_KEY:
        return ""
    queries = []
    if isbn:
        queries.append(f"isbn:{isbn}")
    queries.append(f'intitle:"{title}" inauthor:{author}')
    queries.append(f"{title} {author}")

    for q in queries:
        params = {"q": q, "maxResults": "5", "printType": "books", "langRestrict": "en", "key": _GB_KEY}
        url = f"{_GB_BASE}?{urllib.parse.urlencode(params)}"
        try:
            resp = client.get(url, timeout=8.0)
            if resp.status_code != 200:
                continue
            items = resp.json().get("items") or []
            for item in items:
                desc = (item.get("volumeInfo", {}) or {}).get("description", "") or ""
                if len(desc) > 80:
                    return desc
        except Exception as exc:
            log.debug("google_books description error for %r: %s", title, exc)
    return ""


# ---------------------------------------------------------------------------
# Open Library description fetch
# ---------------------------------------------------------------------------

_OL_SEARCH = "https://openlibrary.org/search.json"
_OL_WORKS = "https://openlibrary.org/works/{work_key}.json"


def _fetch_ol_description(title: str, author: str, client: httpx.Client) -> str:
    try:
        params = {
            "title": title, "author": author,
            "limit": "3", "fields": "key,title,author_name,description",
        }
        url = f"{_OL_SEARCH}?{urllib.parse.urlencode(params)}"
        resp = client.get(url, timeout=8.0, headers={"User-Agent": "ShelfApp/2.0"})
        if resp.status_code != 200:
            return ""
        for doc in (resp.json().get("docs") or []):
            work_key = doc.get("key", "")
            if not work_key:
                continue
            work_resp = client.get(
                f"https://openlibrary.org{work_key}.json",
                timeout=8.0,
                headers={"User-Agent": "ShelfApp/2.0"},
            )
            if work_resp.status_code != 200:
                continue
            raw = work_resp.json().get("description") or ""
            if isinstance(raw, dict):
                raw = raw.get("value", "")
            if len(raw) > 80:
                return raw
    except Exception as exc:
        log.debug("open_library description error for %r: %s", title, exc)
    return ""


# ---------------------------------------------------------------------------
# Claude rewrite
# ---------------------------------------------------------------------------

def _rewrite_with_claude(title: str, author: str, raw: str, client: anthropic.Anthropic) -> str:
    if not raw.strip():
        return ""
    prompt = f'Title: {title}\nAuthor: {author}\nRaw description: """{raw}"""'
    message = client.messages.create(
        model=ANTHROPIC_MODEL,
        max_tokens=120,
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": prompt}],
    )
    result = (message.content[0].text or "").strip()
    # Guard: if the model returned something suspiciously short with no source,
    # honour the contract and return "".
    if not raw.strip() or result.lower() in {"", "n/a", "none"}:
        return ""
    return result


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Enrich list-book descriptions with friend-voice blurbs.")
    parser.add_argument("--force", action="store_true", help="Re-enrich already-filled descriptions.")
    args = parser.parse_args()

    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        sys.exit("ANTHROPIC_API_KEY env var is not set.")

    anthropic_client = anthropic.Anthropic(api_key=api_key)
    http_client = httpx.Client(timeout=10.0)

    list_files = sorted(f for f in LISTS_DIR.glob("*.json") if f.name != "_index.json")
    if not list_files:
        sys.exit(f"No list JSON files found in {LISTS_DIR}")

    total_filled = total_skipped = total_failed = 0

    for list_path in list_files:
        with open(list_path, "r", encoding="utf-8") as fp:
            data = json.load(fp)

        books = data.get("books", [])
        changed = False
        filled = skipped = failed = 0

        for book in books:
            existing = book.get("description", "")
            if existing and not args.force:
                skipped += 1
                continue

            title = book.get("title", "")
            author = book.get("author", "")
            isbn = book.get("isbn_13") or book.get("isbn") or None

            log.info("  %s / %s", title, author)

            # 1. Try Google Books
            raw = _fetch_google_description(title, author, isbn, http_client)

            # 2. Fall back to Open Library
            if not raw:
                raw = _fetch_ol_description(title, author, http_client)

            # 3. Rewrite (returns "" if raw is empty — never hallucinates)
            try:
                blurb = _rewrite_with_claude(title, author, raw, anthropic_client)
            except Exception as exc:
                log.warning("Claude error for %r: %s", title, exc)
                failed += 1
                total_failed += 1
                continue

            book["description"] = blurb
            changed = True
            filled += 1
            total_filled += 1

        if changed:
            with open(list_path, "w", encoding="utf-8") as fp:
                json.dump(data, fp, indent=2, ensure_ascii=False)
                fp.write("\n")

        log.info("%s → filled=%d skipped=%d failed=%d", list_path.name, filled, skipped, failed)
        total_skipped += skipped

    http_client.close()
    print(f"\nDone. filled={total_filled}  skipped={total_skipped}  failed={total_failed}")
    print("Review a sample of the generated blurbs before committing the JSON.")


if __name__ == "__main__":
    main()
