"""Edition matching for cover and metadata lookups.

Google Books and Open Library searches are fuzzy. A query can come back with a
knockoff "Summary of <Title>" edition or a study guide, and when a generated pick
has its title and author swapped ("Hampton Sides" by "The Wide Wide Sea") the
best-scoring hit is an unrelated book. Its cover, description, and page count
then land on the card. A candidate edition is accepted only if:

  - its title matches the requested title (subtitles, leading articles,
    punctuation, and accents are ignored; near-identical wording is tolerated),
  - one of its authors shares a name with the requested author, and
  - it is not a derivative edition (summary, study guide, workbook, ...).
"""

from __future__ import annotations

import re
import unicodedata

# Derivative editions, matched against the CANDIDATE's title/subtitle. Skipped
# when the requested title itself matches (e.g. Scottoline's "Summary Judgment").
_DERIVATIVE_TITLE_RE = re.compile(
    r"\bsummary\b|\bsummaries\b|\bstudy guide\b|\bworkbook\b|\bspark ?notes\b|\bcliff'?s? ?notes\b"
    r"|\bconversation starters\b|\btrivia\b|\bquiz(?:zes)?\b|\bkey takeaways\b|\banalysis of\b"
    r"|\bbook companion\b|\breader'?s guide\b|\bteacher'?s guide\b|\blesson plans?\b",
    re.I)
# Summary mills that publish under a house name instead of a person's name.
_DERIVATIVE_AUTHOR_RE = re.compile(
    r"summar|instaread|quickread|bookhabits|readtrepreneur|worth books|bookrags|gradesaver"
    r"|shmoop|spark ?notes|cliffs ?notes|book tigers|dailybooks|supersummary",
    re.I)
# Openings and disclaimers that only summary editions carry.
_DERIVATIVE_DESC_RE = re.compile(
    r"^\W*(?:summary of|summary &|summary and analysis|disclaimer)\b"
    r"|does not in any capacity mean to replace|this (?:book|summary) is (?:not|an? (?:unofficial )?summary)"
    r"|summarized book|is an? (?:unofficial |independent )?summary of",
    re.I)

_STOP = {"the", "and", "a", "an", "of", "by", "jr", "sr", "dr", "mr", "mrs", "ms"}


def norm(s: str | None) -> str:
    """Lowercase, accents stripped, '&' as 'and', punctuation as spaces, no
    leading article."""
    s = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode()
    s = s.lower().replace("&", " and ")
    s = re.sub(r"[^a-z0-9 ]+", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return re.sub(r"^(?:the|a|an) ", "", s)


def main_title(s: str | None) -> str:
    """The title before any subtitle, series note, or edition note."""
    return norm(re.split(r"[:(\[]| - | — | – ", s or "", maxsplit=1)[0])


def _tokens(s: str) -> set[str]:
    return {t for t in norm(s).split() if t not in _STOP}


def title_matches(requested: str, candidate: str) -> bool:
    req_main, cand_main = main_title(requested), main_title(candidate)
    if not req_main or not cand_main:
        return False
    if req_main == cand_main or norm(requested) == norm(candidate):
        return True
    # Near-identical wording ("Sorcerer's" vs "Philosopher's" Stone): most of the
    # title's words shared. Unrelated books share almost none.
    a, b = _tokens(req_main), _tokens(cand_main)
    return bool(a and b) and len(a & b) / len(a | b) >= 0.6


def author_matches(requested: str, candidates: list[str] | None) -> bool:
    """True when any candidate author shares a name token (3+ letters) with the
    requested author. Missing or unreadable data on either side passes: the
    title check still applies."""
    req = {t for t in _tokens(requested) if len(t) >= 3}
    if not req or not candidates:
        return True
    readable = False
    for c in candidates:
        cand = {t for t in _tokens(c) if len(t) >= 3}
        if cand:
            readable = True
            if req & cand:
                return True
    return not readable


def looks_derivative(requested_title: str, title: str, subtitle: str = "",
                     authors: list[str] | None = None, description: str = "") -> bool:
    """True for summary / study-guide style editions of a book."""
    if not _DERIVATIVE_TITLE_RE.search(requested_title or ""):
        if _DERIVATIVE_TITLE_RE.search(f"{title or ''} {subtitle or ''}"):
            return True
    if any(_DERIVATIVE_AUTHOR_RE.search(a or "") for a in (authors or [])):
        return True
    return bool(_DERIVATIVE_DESC_RE.search((description or "")[:600]))


def is_derivative_description(description: str | None) -> bool:
    """For already-stored text: does this description belong to a summary edition?"""
    return bool(_DERIVATIVE_DESC_RE.search((description or "")[:600]))


def edition_matches(requested_title: str, requested_author: str, title: str,
                    subtitle: str = "", authors: list[str] | None = None,
                    description: str = "") -> bool:
    """The single acceptance rule for a search hit (see module docstring)."""
    if looks_derivative(requested_title, title, subtitle, authors, description):
        return False
    full = f"{title}: {subtitle}" if subtitle else title
    if not (title_matches(requested_title, title) or title_matches(requested_title, full)):
        return False
    return author_matches(requested_author, authors)
