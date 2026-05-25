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


class SeenBooksRequest(BaseModel):
    book_ids: list[str]
    domain: str = "books"


class SuggestionsRequest(BaseModel):
    seed_book_title: str
    seed_book_author: str
    domain: str = "books"
    count: int = Field(default=3, ge=1, le=10)
    # "title|author" strings already shown to the user — Claude will avoid these
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


class DebugInfoResponse(BaseModel):
    last_generation_timestamp: Optional[datetime]
    last_batch_size: Optional[int]


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
