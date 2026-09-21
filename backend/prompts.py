"""
LLM prompt builders for Shelf API.
Output shape is enforced by structured outputs (the *Out models in models.py carry
the per-field guidance), so these prompts carry only the taste logic.
"""
from __future__ import annotations
import re

# Seed descriptions are truncated to this many chars in the recs prompt so the
# taste profile stays bounded (SEED_CONTEXT_MAX seeds x this).
SEED_DESCRIPTION_CHARS = 240


def _seed_line(seed: dict) -> str:
    """Render a seed as '- Title by Author (year) — description…', including only
    the parts the seed doc actually carries (older seeds are title/author only)."""
    line = f"- {seed.get('title', '')} by {seed.get('author', '')}"
    year = seed.get("year")
    if year:
        line += f" ({year})"
    desc = re.sub(r"<[^>]+>", "", seed.get("description") or "")
    desc = re.sub(r"\s+", " ", desc).strip()
    if desc:
        if len(desc) > SEED_DESCRIPTION_CHARS:
            desc = desc[:SEED_DESCRIPTION_CHARS].rsplit(" ", 1)[0] + "…"
        line += f" — {desc}"
    return line


def build_recommendations_prompt(
    seeds: list[dict],
    liked: list[dict],
    disliked: list[dict],
    exclude_ids: list[str],  # actually "Title by Author" strings now — name kept for back-compat
    domain: str,
    count: int,
    recent_mix: dict | None = None,
) -> str:
    def _fmt(reaction: dict) -> str | None:
        title, author = reaction.get("title", "").strip(), reaction.get("author", "").strip()
        if not title:
            return None
        return f"- {title} by {author}" if author else f"- {title}"

    seed_titles_only = [s["title"] for s in seeds]
    seed_list = "\n".join(_seed_line(s) for s in seeds)
    because_of_options = ", ".join(f'"{t}"' for t in seed_titles_only) or "(no seeds)"
    liked_list = "\n".join(line for r in liked[:30] if (line := _fmt(r))) or "none"
    disliked_list = "\n".join(line for r in disliked[:30] if (line := _fmt(r))) or "none"
    exclude_lines = "\n".join(f"- {e}" for e in exclude_ids) or "(none)"

    # Phase B: cross-session counterbalance. Only present when the reader has a
    # delivered history; describes what they've recently been shown so the model
    # can lean LIGHTLY away from a genre/era that has dominated many feeds in a row.
    recent_section = ""
    if recent_mix:
        g = recent_mix.get("genres") or {}
        e = recent_mix.get("eras") or {}
        nb = recent_mix.get("batches", 0)
        genre_str = ", ".join(f"{k} (×{v})" for k, v in sorted(g.items(), key=lambda kv: -kv[1])) or "none"
        era_str = ", ".join(f"{k} (×{v})" for k, v in sorted(e.items(), key=lambda kv: -kv[1])) or "none"
        recent_section = f"""
Across this reader's last {nb} recent batches we have ALREADY shown them:
  Genres: {genre_str}
  Eras: {era_str}
If a single genre or era has dominated MANY of these recent batches, lean LIGHTLY against piling more of it on here — give them some freshness within what they already like. This is a mild anti-monotony nudge ONLY: do NOT push toward genres or eras the reader has never signaled, and do NOT override clear taste — relevance to their taste profile always wins. EXCEPTION: a pick that is another work by an author the reader clearly loves (or a very close-in-voice author) is exempt from this counterbalance — never drop a strong same-author pick just to vary genre or era.
"""

    return f"""You are a literary expert generating personalized book recommendations.

The reader's taste profile (books they explicitly love). Where a line carries a year and a short description, that is what the book actually IS — let those descriptions, not just the titles, drive your read of this reader's taste:
{seed_list}

Books they saved or rated positively after we recommended them — these are STRONG positive signals:
{liked_list}

Books they dismissed or rated negatively — these are STRONG negative signals; avoid recommending books with similar appeal:
{disliked_list}

Use both the seed list and the reaction history to refine your picks. The reactions are recent feedback and should weigh more heavily than the original seeds when they conflict.

CRITICAL: Do NOT recommend any of the following books — they have already been shown to this reader or are in their taste profile. Pick entirely new titles.
{exclude_lines}

Generate exactly {count} book recommendations for domain "{domain}". If a loved author's backlist is exhausted or excluded, widen to close-in-voice authors and adjacent picks rather than returning fewer; a shorter list is acceptable only if you genuinely cannot find {count} books that fit this reader.
For each book include roughly 80% books that clearly match their taste, and 20% that are a gentle stretch outside their comfort zone (set is_comfort_zone_push true for those).
Settle each pick before you write it. The title and author fields must contain only the exact published title and author — never alternatives, corrections, or commentary.

AUTHOR AFFINITY (a top-priority signal): First identify the authors this reader clearly loves — those recurring across their taste profile and positive signals above. Treat (a) OTHER books by those authors that they haven't already read, and (b) authors very close in voice and style, as among your STRONGEST candidates — ahead of generic genre matching. This is priority-weighted, NOT a quota: if a loved author has more eligible work, lead with it; if their backlist is thin or already shown, let the slot fall through to close-in-voice authors and other taste matches. Never invent books an author didn't write, and never use an excluded title.

Aim for some natural variety across the batch — try not to make every pick the same genre or era. This is a gentle nudge, NOT a quota: do NOT force breadth that isn't reflected in this reader's taste. If their profile is genuinely narrow, honor that and stay true to it. There is no required number of genres or eras; relevance to their taste always comes first, and a coherent on-taste batch beats a scattered one. This variety nudge applies ONLY to the non-author-driven picks — the author-affinity picks are exempt, since their genre/era similarity is the whole point.
{recent_section}
Two things should shape the batch:
  1. If there are dislikes, work out what those disliked books have in COMMON — the shared appeal, tone, tropes, or subject matter — and steer clear of it.
  2. Build the list seed-first: for each pick, start from a SPECIFIC seed book in their taste profile and choose a genuinely new book that follows from it — the seed should DRIVE the selection, not be attached as a label afterward. Set because_of to that exact seed title, and set because_of_reason to the specific thing this pick shares with that seed. For an occasional stretch pick that isn't anchored to any single seed, use because_of "" and because_of_reason "".

because_of MUST be one of these exact strings, copied verbatim: {because_of_options}. Use the empty string "" only if no seed title genuinely drove this recommendation. Do NOT invent a title that isn't in that list.
"""


def build_overview_structure_prompt(raw: str, title: str = "", author: str = "") -> str:
    """Prompt to split a messy publisher description into clean structured parts.
    Used once per book (cached) so the detail page can show a clean synopsis,
    distinct pull-quotes, and accolade badges instead of one dense blob."""
    book_id = f'"{title}" by {author}' if title else "the book below"
    return f"""You are formatting the description for {book_id} for a clean app detail page. The raw publisher text below mixes the actual synopsis together with marketing taglines, bestseller/award accolades, and review quotes. Separate it into the actual synopsis, the strongest attributed review quotes, and short accolade badges.

CRITICAL: If the text below is clearly NOT about {book_id} — e.g. it describes a different, unrelated book (wrong title, wrong subject) — return an empty synopsis, no pull quotes, and no accolades. Never attach another book's content to this one.

Raw description:
<<<
{raw}
>>>
"""


def build_suggestions_prompt(
    seed_title: str,
    seed_author: str,
    domain: str,
    count: int,
    exclude: list[str] | None = None,
    liked: list[dict] | None = None,
    disliked: list[dict] | None = None,
) -> str:
    def _fmt(reaction: dict) -> str | None:
        title, author = reaction.get("title", "").strip(), reaction.get("author", "").strip()
        if not title:
            return None
        return f"- {title} by {author}" if author else f"- {title}"

    exclude_section = ""
    if exclude:
        exclude_section = (
            "\nDo NOT suggest any of these books (already shown):\n"
            + "\n".join(f"- {item}" for item in exclude[:50])
            + "\n"
        )

    # Phase C: optional taste context. When present, suggestions stay anchored to
    # the seed but lean toward the reader's positives and away from their dislike
    # patterns. Absent (new users / no reactions) → original taste-blind behavior.
    liked_lines = "\n".join(line for r in (liked or [])[:25] if (line := _fmt(r)))
    disliked_lines = "\n".join(line for r in (disliked or [])[:25] if (line := _fmt(r)))
    taste_section = ""
    if liked_lines or disliked_lines:
        taste_section = "\nThe seed book above is the PRIMARY anchor. As a secondary signal, here is this reader's broader taste:\n"
        if liked_lines:
            taste_section += f"Books they like:\n{liked_lines}\n"
        if disliked_lines:
            taste_section += f"Books they dislike:\n{disliked_lines}\n"
        taste_section += (
            "Stay closely related to the seed book; among options that are equally close, prefer ones that fit "
            "this reader's positive signals and steer clear of the patterns in their dislikes. Never suggest a "
            "book that shares the core appeal of one they disliked.\n"
        )

    return f"""You are a literary expert helping a reader discover books similar to one they love.

Seed book: "{seed_title}" by {seed_author} (domain: {domain})
{exclude_section}{taste_section}
Suggest exactly {count} books that readers of this book often enjoy next.
Choose books that are closely related in theme, style, or readership — not just the same genre.
Prioritize by author first: if {seed_author} has OTHER notable books the reader likely hasn't read (and that aren't excluded above), lead with 1–2 of them, then branch out to closely related authors and books. If {seed_author} has no suitable other work, skip straight to adjacent authors — do NOT pad with weak filler, and never invent titles the author didn't write.
"""
