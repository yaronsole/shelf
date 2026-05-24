from __future__ import annotations
from datetime import datetime
from enum import StrEnum
from typing import Optional
from pydantic import BaseModel, Field


class ReactionKind(StrEnum):
    save = "save"
    dismiss = "dismiss"
    already_read_liked = "alreadyReadLiked"
    already_read_disliked = "alreadyReadDisliked"


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
