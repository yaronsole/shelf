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
    exclude_ids: list[str],
    domain: str,
    count: int,
) -> str:
    def _fmt(reaction: dict) -> str | None:
        title, author = reaction.get("title", "").strip(), reaction.get("author", "").strip()
        if not title:
            return None
        return f"- {title} by {author}" if author else f"- {title}"

    seed_list = "\n".join(f"- {s['title']} by {s['author']}" for s in seeds)
    liked_list = "\n".join(line for r in liked[:30] if (line := _fmt(r))) or "none"
    disliked_list = "\n".join(line for r in disliked[:30] if (line := _fmt(r))) or "none"
    exclude_json = json.dumps(exclude_ids[:150])

    return f"""You are a literary expert generating personalized book recommendations.

The reader's taste profile (books they explicitly love):
{seed_list}

Books they saved or rated positively after we recommended them — these are STRONG positive signals:
{liked_list}

Books they dismissed or rated negatively — these are STRONG negative signals; avoid recommending books with similar appeal:
{disliked_list}

Use both the seed list and the reaction history to refine your picks. The reactions are recent feedback and should weigh more heavily than the original seeds when they conflict.

Do NOT recommend any book whose ID appears in this exclusion list: {exclude_json}

Generate exactly {count} book recommendations for domain "{domain}".
For each book include roughly 80% books that clearly match their taste, and 20% that are a gentle stretch outside their comfort zone (set is_comfort_zone_push true for those).

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
"""


def build_suggestions_prompt(
    seed_title: str,
    seed_author: str,
    domain: str,
    count: int,
    exclude: list[str] | None = None,
) -> str:
    exclude_section = ""
    if exclude:
        exclude_section = (
            "\nDo NOT suggest any of these books (already shown):\n"
            + "\n".join(f"- {item}" for item in exclude[:50])
            + "\n"
        )
    return f"""You are a literary expert helping a reader discover books similar to one they love.

Seed book: "{seed_title}" by {seed_author} (domain: {domain})
{exclude_section}
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
