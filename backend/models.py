from __future__ import annotations
from datetime import datetime
from enum import StrEnum
from typing import Literal, Optional
from pydantic import BaseModel, Field


class ReactionKind(StrEnum):
    save = "save"
    dismiss = "dismiss"
    already_read_liked = "alreadyReadLiked"
    already_read_disliked = "alreadyReadDisliked"


class ListReactionKind(StrEnum):
    """Reactions a user can leave on a book from a curated list.

    Mapping to the internal model:
      - read  → adds a seed_book (so Claude exclusion list covers it)
      - saved → reaction kind=save (lands in the Shelf tab)
      - passed → reaction kind=dismiss
    """
    read = "read"
    saved = "saved"
    passed = "passed"


# ---------------------------------------------------------------------------
# Requests
# ---------------------------------------------------------------------------
class SeedBookRequest(BaseModel):
    title: str
    author: str
    cover_url: str
    domain: str = "books"


class ReactionRequest(BaseModel):
    book_id: str
    kind: ReactionKind
    domain: str = "books"
    # Optional taste-context, sent by surfaces that act on books with no
    # recommendation_col entry (popular-picks grid, search, Discover detail).
    # When present, add_reaction persists these so the reaction carries a
    # title/author — which is what makes a "didn't like" register as a negative
    # signal AND land in the recommendation exclusion list. Backwards-compatible:
    # existing callers omit them and behaviour is unchanged.
    title: str = ""
    author: str = ""
    cover_url: str = ""


class SeenBooksRequest(BaseModel):
    book_ids: list[str]
    domain: str = "books"


class BookOverviewRequest(BaseModel):
    title: str
    author: str = ""
    # Optional caller-provided description to structure (For You recs already have
    # it). When present AND authoritative, the server skips the Google Books fetch.
    description: str = ""
    # When True, `description` is only a FALLBACK (e.g. a short curated list blurb):
    # the server prefers Google Books (richer — quotes/accolades) and uses this text
    # only if GB is empty or over quota, so the overview is never blank. When False
    # (default), a provided description is authoritative and GB is skipped.
    description_is_fallback: bool = False


class SuggestionsRequest(BaseModel):
    seed_book_title: str
    seed_book_author: str
    domain: str = "books"
    count: int = Field(default=3, ge=1, le=25)  # le raised for the cache-pool / refresh path
    # "title|author" strings already shown to the user — filtered out after the cache
    exclude: list[str] = Field(default_factory=list)


# ---------------------------------------------------------------------------
# Responses
# ---------------------------------------------------------------------------
class SeedBookResponse(BaseModel):
    id: str
    title: str
    author: str
    cover_url: str
    domain: str


class RecommendationResponse(BaseModel):
    id: str
    title: str
    author: str
    cover_url: str
    blurb: str
    genre: str
    era: str
    is_comfort_zone_push: bool
    batch_id: str
    domain: str
    awards: list[str] = []
    # v2.2: replace ratings with richer context signals
    context_tag: str = ""           # Claude-authored editorial hook
    acclaim: str = ""               # Claude-authored critical acclaim line
    nyt_bestseller: bool = False    # currently on a NYT list
    nyt_weeks_on_list: int | None = None
    reading_time_minutes: int | None = None  # derived from Google Books pageCount
    because_of: Optional[str] = None  # exact title of the seed book driving this pick, validated against seeds
    because_of_reason: str = ""       # Phase 3: short, specific clause on why this pick follows from the seed
    description: str = ""             # Phase 3: full Google Books description (expandable in the PDP)


class SuggestionResponse(BaseModel):
    id: str
    title: str
    author: str
    cover_url: str = ""
    blurb: str = ""
    genre: str = ""
    era: str = ""
    awards: list[str] = []
    context_tag: str = ""
    acclaim: str = ""
    nyt_bestseller: bool = False
    nyt_weeks_on_list: int | None = None
    reading_time_minutes: int | None = None
    description: str = ""             # Phase 3: full Google Books description (expandable in the PDP)


class DebugInfoResponse(BaseModel):
    last_generation_timestamp: Optional[datetime]
    last_batch_size: Optional[int]
    # Phase 0: diversity measurability — populated from the most recent batch
    genre_distribution: Optional[dict[str, int]] = None   # genre → count
    era_distribution: Optional[dict[str, int]] = None     # era → count
    comfort_push_count: Optional[int] = None              # # of is_comfort_zone_push=True in batch
    batch_id: Optional[str] = None                        # UUID of the most recent batch


# ---------------------------------------------------------------------------
# Curated lists (Phase 1)
# ---------------------------------------------------------------------------
class ListMetadata(BaseModel):
    slug: str
    title: str
    subtitle: str = ""
    description: str = ""
    curator: str = ""
    book_count: int = 0
    last_updated: str = ""
    color_start: str = ""
    color_end: str = ""
    sort_order: int = 0


class ListCatalogResponse(BaseModel):
    lists: list[ListMetadata]


class ListBookResponse(BaseModel):
    book_id: str
    title: str
    author: str
    year: Optional[int] = None
    cover_url: str = ""
    user_status: Optional[Literal["read", "saved", "passed"]] = None
    description: str = ""


class ListDetailResponse(BaseModel):
    slug: str
    metadata: ListMetadata
    books: list[ListBookResponse]


class ListReactionRequest(BaseModel):
    book_id: str
    title: str
    author: str
    cover_url: str = ""
    kind: ListReactionKind
    domain: str = "books"


# ---------------------------------------------------------------------------
# User settings (community contribution toggle)
# ---------------------------------------------------------------------------
class UserSettingsRequest(BaseModel):
    contribute: bool = True


class UserSettingsResponse(BaseModel):
    contribute: bool = True


# ---------------------------------------------------------------------------
# Claude structured-output schemas. These describe what the MODEL returns
# (passed as output_format to messages.parse); they are deliberately separate
# from the iOS response models above, which enrichment fills in afterwards
# (cover_url, NYT status, reading time, description). Field descriptions are the
# per-field guidance that used to live in the prompt text. Every field is
# required — the model always emits the full object.
# ---------------------------------------------------------------------------
class RecommendedBookOut(BaseModel):
    title: str = Field(description="The exact published title only — no alternatives, corrections, or commentary.")
    author: str = Field(description="The exact published author name only.")
    blurb: str = Field(description=(
        "1-2 sentences, personal and specific, like a well-read friend recommending it."))
    genre: str
    era: str = Field(description='e.g. "1990s", "Contemporary", "Classic".')
    is_comfort_zone_push: bool = Field(description=(
        "True for the roughly 20% of picks that are a gentle stretch outside the reader's comfort zone."))
    awards: list[str] = Field(description=(
        'Major awards this book won or was shortlisted for, as short canonical names, e.g. '
        '"Pulitzer Prize", "National Book Award", "Booker Prize", "Hugo Award", "Nebula Award". '
        "Empty list if none. Only include if certain."))
    context_tag: str = Field(description=(
        "ONE short editorial hook that makes this book interesting, max 8 words. Examples: "
        '"Adapted into HBO series", "Translated from Korean", "Author\'s debut at 24", '
        '"Obama\'s 2023 favorite", "Made into Oscar-winning film", "30 years in the making". '
        "Empty string if no notable hook. Only include if certain."))
    acclaim: str = Field(description=(
        "Short publication-praise line, max 10 words. Examples: "
        '"Acclaimed by The New Yorker and NYT", "A New York Times Notable Book", '
        '"Praised by The Atlantic". Empty string if uncertain.'))
    because_of: str = Field(description=(
        "The SINGLE seed book title most responsible for this pick, copied verbatim from the "
        "reader's taste profile. Empty string only if no seed title genuinely drove this "
        "recommendation. Never invent a title that isn't in the profile."))
    because_of_reason: str = Field(description=(
        "A SHORT, SPECIFIC phrase, MAX 12 words, naming what THIS book shares with the "
        "because_of seed: the concrete appeal/voice/theme/structure that makes it a natural "
        'next read (e.g. "the same spare, dread-soaked prose and father-son core", '
        '"another slow-unraveling unreliable narrator"). Do NOT restate the plot, repeat the '
        'blurb, or be generic ("a great read"). Empty string if because_of is empty or you '
        "cannot name a specific, honest connection."))


class RecommendationBatchOut(BaseModel):
    books: list[RecommendedBookOut]


class SuggestedBookOut(BaseModel):
    title: str = Field(description="The exact published title only — no alternatives, corrections, or commentary.")
    author: str = Field(description="The exact published author name only.")
    blurb: str = Field(description="1-2 sentences, specific to this book's appeal vs the seed book.")
    genre: str
    era: str = Field(description='e.g. "1990s", "Contemporary", "Classic".')
    awards: list[str] = Field(description=(
        "Major awards won or shortlisted, as short canonical names. Empty list if none. Only include if certain."))
    context_tag: str = Field(description=(
        'ONE editorial hook, max 8 words, e.g. "Adapted into HBO series", "Translated from Korean", '
        '"Author\'s debut at 24". Empty string if none.'))
    acclaim: str = Field(description=(
        "Short publication-praise line, max 10 words. Empty string if uncertain."))


class SuggestionBatchOut(BaseModel):
    books: list[SuggestedBookOut]


class PullQuoteOut(BaseModel):
    text: str = Field(description="The quote itself, without surrounding quotation marks.")
    source: str = Field(description="The reviewer or publication the quote is attributed to.")


class StructuredOverviewOut(BaseModel):
    synopsis: str = Field(description=(
        "The actual story / subject matter, as clean prose in 1-3 short paragraphs separated by "
        "a blank line. EXCLUDE marketing taglines, bestseller/award mentions, adaptation notes, "
        "and review quotes. Do NOT invent or embellish — only rephrase/condense what is actually "
        "in the text. Empty string if the text is not about this book."))
    pull_quotes: list[PullQuoteOut] = Field(description=(
        "The strongest review/praise quotes, at most 3. Only include a quote when an "
        "attribution/source is present in the text. Empty list if none."))
    accolades: list[str] = Field(description=(
        "SHORT badge strings for notable status — bestseller, awards, adaptations (e.g. "
        '"#1 New York Times Bestseller", "Pulitzer Prize Winner", "Now a major motion picture"). '
        "At most 4, each max ~6 words. Empty list if none."))
