"""Pure community ranking rules. No accounts, network calls or model generation."""
from datetime import datetime, timezone
from lists import book_id_hash

EPOCH = datetime.min.replace(tzinfo=timezone.utc)
READ_KINDS = {"alreadyReadLiked", "alreadyReadDisliked"}


def timestamp(value):
    if isinstance(value, datetime):
        return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value
    if isinstance(value, str):
        try:
            return timestamp(datetime.fromisoformat(value.replace("Z", "+00:00")))
        except ValueError:
            pass
    return EPOCH


def rank_loves(readers):
    """One current reading sentiment per book per contributing device identity.

    A later dislike retracts a love. Saves/passes do not rewrite reading sentiment.
    Repeated love submissions cannot add votes. Domain and missing-title guards
    also apply to legacy reaction documents.
    """
    totals = {}
    for uid, contributes, reactions in readers:
        if not contributes:
            continue
        latest = {}
        for reaction in reactions:
            if reaction.get("domain", "books") != "books" or reaction.get("kind") not in READ_KINDS:
                continue
            title = (reaction.get("title") or "").strip()
            author = (reaction.get("author") or "").strip()
            if not title:
                continue
            key = book_id_hash(title, author)
            # Dislike wins an exact-time tie; independent of Firestore iteration.
            order = (timestamp(reaction.get("created_at")), reaction["kind"] == "alreadyReadDisliked")
            if key not in latest or order > latest[key][0]:
                latest[key] = (order, reaction, title, author)
        for key, (order, reaction, title, author) in latest.items():
            if reaction["kind"] != "alreadyReadLiked":
                continue
            entry = totals.setdefault(key, dict(book_id=key, title=title, author=author,
                                                readers=set(), latest_loved_at=EPOCH))
            entry["readers"].add(uid)
            entry["latest_loved_at"] = max(entry["latest_loved_at"], order[0])
    books = [{"book_id": b["book_id"], "title": b["title"], "author": b["author"],
              "loved_count": len(b["readers"]), "latest_loved_at": b["latest_loved_at"]}
             for b in totals.values()]
    return sorted(books, key=lambda b: (-b["loved_count"], -b["latest_loved_at"].timestamp(),
                                       b["title"].casefold(), b["book_id"]))


def recently_loved(books):
    return sorted((b for b in books if timestamp(b.get("latest_loved_at")) > EPOCH),
                  key=lambda b: (-timestamp(b["latest_loved_at"]).timestamp(),
                                 -b["loved_count"], b["book_id"]))


def with_ranks(books):
    """Competition ranks: 1, 1, 3. Date breaks display ties, never vote ties."""
    result, previous, rank = [], None, 0
    for index, book in enumerate(books, 1):
        if book["loved_count"] != previous:
            rank = index
        result.append({**book, "rank": rank})
        previous = book["loved_count"]
    return result


def taste_signals(reactions, domain="books"):
    """Resolve current sentiment before selecting prompt signals; passes only exclude."""
    ordered = sorted((r for r in reactions if r.get("domain", "books") == domain),
                     key=lambda r: (timestamp(r.get("created_at")),
                                    r.get("kind") == "alreadyReadDisliked"), reverse=True)
    sentiment, saves = {}, {}
    for r in ordered:
        title = (r.get("title") or "").strip()
        if not title:
            continue
        key = book_id_hash(title, r.get("author") or "")
        if r.get("kind") in READ_KINDS:
            sentiment.setdefault(key, r)
        elif r.get("kind") == "save":
            saves.setdefault(key, r)
    liked = [r for r in sentiment.values() if r["kind"] == "alreadyReadLiked" and not r.get("taste_excluded")]
    liked += [r for key, r in saves.items() if key not in sentiment and not r.get("taste_excluded")]
    disliked = [r for r in sentiment.values() if r["kind"] == "alreadyReadDisliked" and not r.get("taste_excluded")]
    return liked[:30], disliked[:30]
