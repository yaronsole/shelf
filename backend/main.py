"""
Shelf API – Cloud Run backend
Python 3.12 / FastAPI / Firestore / Claude API
"""
from __future__ import annotations

import json
import logging
import os
import uuid
from datetime import datetime, timezone
from typing import Annotated

import anthropic
from fastapi import Depends, FastAPI, Header, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from google.cloud import firestore

from models import (
    DebugInfoResponse,
    ReactionKind,
    ReactionRequest,
    RecommendationResponse,
    SeenBooksRequest,
    SeedBookRequest,
    SeedBookResponse,
    SuggestionResponse,
    SuggestionsRequest,
)
from prompts import build_recommendations_prompt, build_suggestions_prompt
from google_books import lookup_cover

import httpx

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Clients (module-level singletons, initialised once at cold start)
# ---------------------------------------------------------------------------
db = firestore.Client()
claude = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
app = FastAPI(title="Shelf API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Auth helper
# ---------------------------------------------------------------------------
MAX_EXCLUSION_LIST = 150  # cap to keep prompts bounded


def get_user_id(authorization: Annotated[str | None, Header()] = None) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED)
    return authorization.removeprefix("Bearer ").strip()


UserID = Annotated[str, Depends(get_user_id)]


# ---------------------------------------------------------------------------
# Firestore helpers
# ---------------------------------------------------------------------------
def user_ref(user_id: str) -> firestore.DocumentReference:
    return db.collection("users").document(user_id)


def seed_col(user_id: str):
    return user_ref(user_id).collection("seed_books")


def reaction_col(user_id: str):
    return user_ref(user_id).collection("reactions")


def recommendation_col(user_id: str):
    return user_ref(user_id).collection("recommendations")


# ---------------------------------------------------------------------------
# POST /v1/seed-books
# ---------------------------------------------------------------------------
@app.post("/v1/seed-books", status_code=status.HTTP_201_CREATED)
def add_seed_book(body: SeedBookRequest, user_id: UserID):
    doc_id = str(uuid.uuid4())
    seed_col(user_id).document(doc_id).set(
        {**body.model_dump(), "id": doc_id, "created_at": datetime.now(timezone.utc)}
    )
    return {"id": doc_id}


# ---------------------------------------------------------------------------
# GET /v1/seed-books
# ---------------------------------------------------------------------------
@app.get("/v1/seed-books", response_model=list[SeedBookResponse])
def list_seed_books(user_id: UserID, domain: str = "books"):
    docs = seed_col(user_id).where("domain", "==", domain).stream()
    return [SeedBookResponse(**d.to_dict()) for d in docs]


# ---------------------------------------------------------------------------
# DELETE /v1/seed-books/{id}
# ---------------------------------------------------------------------------
@app.delete("/v1/seed-books/{book_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_seed_book(book_id: str, user_id: UserID):
    seed_col(user_id).document(book_id).delete()


# ---------------------------------------------------------------------------
# POST /v1/reactions
# ---------------------------------------------------------------------------
@app.post("/v1/reactions", status_code=status.HTTP_201_CREATED)
def add_reaction(body: ReactionRequest, user_id: UserID):
    doc_id = str(uuid.uuid4())
    reaction_col(user_id).document(doc_id).set(
        {**body.model_dump(), "id": doc_id, "created_at": datetime.now(timezone.utc)}
    )
    return {"id": doc_id}


# ---------------------------------------------------------------------------
# POST /v1/seen-books
# ---------------------------------------------------------------------------
@app.post("/v1/seen-books", status_code=status.HTTP_204_NO_CONTENT)
def mark_seen(body: SeenBooksRequest, user_id: UserID):
    batch = db.batch()
    ref = user_ref(user_id)
    for book_id in body.book_ids:
        batch.set(
            ref.collection("seen_books").document(book_id),
            {"book_id": book_id, "domain": body.domain,
             "seen_at": datetime.now(timezone.utc)},
        )
    batch.commit()


# ---------------------------------------------------------------------------
# GET /v1/recommendations  (generate if needed, else return cached batch)
# ---------------------------------------------------------------------------
@app.get("/v1/recommendations", response_model=list[RecommendationResponse])
def get_recommendations(user_id: UserID, domain: str = "books"):
    # Return any unseen cached recommendations first
    unseen = (
        recommendation_col(user_id)
        .where("domain", "==", domain)
        .where("delivered", "==", False)
        .limit(10)
        .stream()
    )
    cached = [RecommendationResponse(**d.to_dict()) for d in unseen]
    if cached:
        return cached

    # Otherwise generate a fresh batch
    return _generate_recommendations(user_id, domain)


def _generate_recommendations(user_id: str, domain: str) -> list[RecommendationResponse]:
    # Gather seed books
    seeds = [d.to_dict() for d in seed_col(user_id).where("domain", "==", domain).stream()]
    if not seeds:
        return []

    # Build exclusion list (cap to avoid token blowup)
    seen_ids = [d.id for d in user_ref(user_id).collection("seen_books").select([]).stream()]
    dismissed = [
        d.to_dict().get("book_id", "")
        for d in reaction_col(user_id)
        .where("kind", "==", ReactionKind.dismiss)
        .stream()
    ]
    exclude_ids = list(dict.fromkeys(seen_ids + dismissed))[:MAX_EXCLUSION_LIST]

    # Positive / negative taste signals
    liked = [
        d.to_dict()
        for d in reaction_col(user_id)
        .where("kind", "in", [ReactionKind.save, ReactionKind.already_read_liked])
        .stream()
    ]
    disliked = [
        d.to_dict()
        for d in reaction_col(user_id)
        .where("kind", "in", [ReactionKind.already_read_disliked, ReactionKind.dismiss])
        .limit(50)
        .stream()
    ]

    prompt = build_recommendations_prompt(
        seeds=seeds,
        liked=liked,
        disliked=disliked,
        exclude_ids=exclude_ids,
        domain=domain,
        count=6,
    )

    message = claude.messages.create(
        model="claude-opus-4-5",
        max_tokens=2048,
        messages=[{"role": "user", "content": prompt}],
    )
    raw = message.content[0].text
    books: list[dict] = json.loads(raw)

    # Enrich with Google Books cover art before persisting to Firestore
    with httpx.Client(timeout=5.0) as client:
        for b in books:
            if not b.get("cover_url"):
                b["cover_url"] = lookup_cover(b.get("title", ""), b.get("author", ""), client=client)

    batch_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc)
    results: list[RecommendationResponse] = []

    firestore_batch = db.batch()
    for book in books:
        doc_id = str(uuid.uuid4())
        rec = {
            "id": doc_id,
            "batch_id": batch_id,
            "domain": domain,
            "delivered": False,
            "created_at": now,
            **book,
        }
        firestore_batch.set(recommendation_col(user_id).document(doc_id), rec)
        results.append(RecommendationResponse(**rec))

    # Store generation metadata on user doc
    firestore_batch.set(
        user_ref(user_id),
        {"last_generation_timestamp": now, "last_batch_size": len(books)},
        merge=True,
    )
    firestore_batch.commit()
    return results


# ---------------------------------------------------------------------------
# POST /v1/onboarding/suggestions
# ---------------------------------------------------------------------------
@app.post("/v1/onboarding/suggestions", response_model=list[SuggestionResponse])
def get_suggestions(body: SuggestionsRequest, user_id: UserID):
    prompt = build_suggestions_prompt(
        seed_title=body.seed_book_title,
        seed_author=body.seed_book_author,
        domain=body.domain,
        count=body.count,
    )
    message = claude.messages.create(
        model="claude-opus-4-5",
        max_tokens=512,
        messages=[{"role": "user", "content": prompt}],
    )
    raw = message.content[0].text
    books: list[dict] = json.loads(raw)

    # Enrich with Google Books cover art (sequential — only 3 books per call)
    with httpx.Client(timeout=5.0) as client:
        for b in books:
            if not b.get("cover_url"):
                b["cover_url"] = lookup_cover(b.get("title", ""), b.get("author", ""), client=client)

    return [SuggestionResponse(id=str(uuid.uuid4()), **b) for b in books]


# ---------------------------------------------------------------------------
# GET /v1/debug/generation-info
# ---------------------------------------------------------------------------
@app.get("/v1/debug/generation-info", response_model=DebugInfoResponse)
def debug_info(user_id: UserID):
    doc = user_ref(user_id).get()
    if not doc.exists:
        return DebugInfoResponse(last_generation_timestamp=None, last_batch_size=None)
    data = doc.to_dict()
    return DebugInfoResponse(
        last_generation_timestamp=data.get("last_generation_timestamp"),
        last_batch_size=data.get("last_batch_size"),
    )


# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------
@app.get("/healthz")
def healthz():
    return {"status": "ok"}
