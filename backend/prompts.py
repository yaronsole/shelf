"""
LLM prompt builders for Shelf API.
All prompts instruct Claude to return raw JSON only — no markdown fences.
"""
from __future__ import annotations
import json


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
    seed_list = "\n".join(f"- {s['title']} by {s['author']}" for s in seeds)
    because_of_options = ", ".join(f'"{t}"' for t in seed_titles_only) or "(no seeds)"
    liked_list = "\n".join(line for r in liked[:30] if (line := _fmt(r))) or "none"
    disliked_list = "\n".join(line for r in disliked[:30] if (line := _fmt(r))) or "none"
    exclude_lines = "\n".join(f"- {e}" for e in exclude_ids[:150]) or "(none)"

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

The reader's taste profile (books they explicitly love):
{seed_list}

Books they saved or rated positively after we recommended them — these are STRONG positive signals:
{liked_list}

Books they dismissed or rated negatively — these are STRONG negative signals; avoid recommending books with similar appeal:
{disliked_list}

Use both the seed list and the reaction history to refine your picks. The reactions are recent feedback and should weigh more heavily than the original seeds when they conflict.

CRITICAL: Do NOT recommend any of the following books — they have already been shown to this reader or are in their taste profile. Pick entirely new titles.
{exclude_lines}

Generate exactly {count} book recommendations for domain "{domain}".
For each book include roughly 80% books that clearly match their taste, and 20% that are a gentle stretch outside their comfort zone (set is_comfort_zone_push true for those).

Aim for some natural variety across the batch — try not to make every pick the same genre or era. This is a gentle nudge, NOT a quota: do NOT force breadth that isn't reflected in this reader's taste. If their profile is genuinely narrow, honor that and stay true to it. There is no required number of genres or eras; relevance to their taste always comes first, and a coherent on-taste batch beats a scattered one.
{recent_section}
Before writing your answer, reason through these two steps SILENTLY — do NOT include this reasoning, any headings, or any preamble in your response:
  1. Look at the books they dislike and infer what those disliked books have in COMMON — the shared appeal, tone, tropes, or subject matter to AVOID. (If there are no dislikes, skip this step.)
  2. Build the list seed-first: for each pick, start from a SPECIFIC seed book in their taste profile and choose a genuinely new book that follows from it — the seed should DRIVE the selection, not be attached as a label afterward. Set because_of to that exact seed title. For an occasional stretch pick that isn't anchored to any single seed, use because_of "".

After reasoning silently, output ONLY the JSON array described below — no preamble, no explanation, no step labels.

Respond with ONLY a JSON array. No markdown, no explanation. Each object must have:
  title          (string)
  author         (string)
  cover_url      (string — leave as empty string "")
  blurb          (string — 1-2 sentences, personal and specific, like a well-read friend recommending it)
  genre          (string)
  era            (string — e.g. "1990s", "Contemporary", "Classic")
  is_comfort_zone_push (boolean)
  awards         (array of strings — major awards this book won or was shortlisted for. Short canonical names
                 e.g. "Pulitzer Prize", "National Book Award", "Booker Prize", "Hugo Award", "Nebula Award".
                 Empty array if none. Only include if certain.)
  context_tag    (string — ONE short editorial hook that makes this book interesting, max 8 words. Examples:
                 "Adapted into HBO series", "Translated from Korean", "Author's debut at 24",
                 "Obama's 2023 favorite", "Made into Oscar-winning film", "30 years in the making".
                 Empty string if no notable hook. Only include if certain.)
  acclaim        (string — short publication-praise line, max 10 words. Examples:
                 "Acclaimed by The New Yorker and NYT", "A New York Times Notable Book",
                 "Praised by The Atlantic". Empty string if uncertain.)
  because_of     (string — the SINGLE seed book title most responsible for this pick.
                 MUST be one of these exact strings, copied verbatim: {because_of_options}.
                 Use the empty string "" only if no seed title genuinely drove this recommendation.
                 Do NOT invent a title that isn't in the list above.)
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

Respond with ONLY a JSON array. No markdown, no explanation. Each object must have:
  title         (string)
  author        (string)
  blurb         (string — 1-2 sentences, specific to this book's appeal vs the seed)
  genre         (string)
  era           (string — e.g. "1990s", "Contemporary", "Classic")
  awards        (array of strings — short canonical names. Empty if none.)
  context_tag   (string — ONE editorial hook max 8 words. e.g. "Adapted into HBO series",
                "Translated from Korean", "Author's debut at 24". Empty if none.)
  acclaim       (string — short publication-praise line max 10 words. Empty if uncertain.)
"""
