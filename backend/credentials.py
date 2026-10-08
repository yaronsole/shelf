"""Verified credentials for a book's card description: a review quote and accolades
lifted VERBATIM from its publisher description (Google Books). Nothing here is
generated, so nothing can be invented: a quote is used only if it appears word for
word in the source text with an attribution, and the source text has to be about
this book (it names the title or the author).

Publisher copy follows a few standard shapes:
  “A marvelous nonfiction thriller.” —The Wall Street Journal
  "Truly magnificent . . . definitive" —Andrew Roberts, The Wall Street Journal
  #1 NEW YORK TIMES BESTSELLER • NOW A MAJOR MOTION PICTURE • WINNER OF THE ...
"""

from __future__ import annotations

import re

from book_match import main_title, norm

# A quoted span (curly or straight quotes), then a dash, then the source (trimmed below).
_QUOTE_RE = re.compile(r"[“\"]([^“”\"]{25,320}?)[”\"]\s*(?:[—–]|--|-)\s*([^“”\"•\n]{2,90})")
_SOURCE_STOP = re.compile(r"^(?:he|she|they|i|we|you|it|said|says|asks|wrote|from)\b", re.I)
# Upper-case accolade runs separated by bullets, e.g. "#1 NEW YORK TIMES BESTSELLER •".
_ACCOLADE_RE = re.compile(r"(?:^|•|\n|\.\s)\s*([#0-9A-Z][A-Z0-9#'’&.,:\- ]{8,90}?)\s*(?=•|\n|$|\s[A-Z][a-z])")
_ACCOLADE_WORDS = re.compile(
    r"BESTSELL|WINNER|PRIZE|AWARD|FINALIST|LONGLIST|SHORTLIST|BEST BOOK|NOTABLE|"
    r"MAJOR MOTION PICTURE|LIMITED SERIES|NETFLIX|HBO|BOOK CLUB PICK|SELECTION", re.I)
MAX_QUOTE_CHARS = 200


def _clean(s: str | None) -> str:
    s = re.sub(r"<[^>]+>", " ", s or "")
    return re.sub(r"\s+", " ", s).strip()


def is_about(description: str, title: str, author: str) -> bool:
    """Cheap relevance check: publisher copy for a book almost always names its
    title or its author. Copy that names neither may belong to another book."""
    text = norm(_clean(description))
    t = main_title(title)
    surname = norm(author).split(" ")[-1] if norm(author) else ""
    return bool((len(t) >= 4 and t in text) or (len(surname) >= 3 and re.search(rf"\b{re.escape(surname)}\b", text)))


# Review sources seen in publisher copy (most frequent first in our data). A source
# is accepted only if it is one of these or a person's name, because Google Books
# strips line breaks and the next sentence runs straight on ("—Stephen King New
# York City, 1976 ...").
_PUBLICATIONS = sorted([
    "The New York Times Book Review", "New York Times Book Review", "The New York Times", "New York Times",
    "The Wall Street Journal", "Wall Street Journal", "Publishers Weekly", "Kirkus Reviews", "Entertainment Weekly",
    "USA Today", "The Washington Post Book World", "Washington Post Book World", "The Washington Post",
    "Washington Post", "ALA Booklist", "Booklist", "Los Angeles Times Book Review", "Los Angeles Times", "NPR",
    "San Francisco Chronicle", "The Boston Globe", "Boston Globe", "People", "Time", "TIME", "Library Journal",
    "School Library Journal", "Chicago Tribune", "Cosmopolitan", "Newsweek", "O, The Oprah Magazine",
    "O: The Oprah Magazine", "O Magazine", "Oprah Daily", "Minneapolis Star Tribune", "Star Tribune",
    "The Economist", "BookPage", "The New Yorker", "The Horn Book", "Vanity Fair", "The Seattle Times",
    "Seattle Times", "The Buffalo News", "Financial Times", "The New York Review of Books", "The Guardian",
    "Salon", "St. Louis Post-Dispatch", "BuzzFeed", "Family Circle", "Richmond Times-Dispatch", "The Atlantic",
    "The New Republic", "Slate", "The Times", "The Sunday Times", "The Observer", "The Independent",
    "The Telegraph", "The Daily Telegraph", "The Spectator", "New Statesman", "The Times Literary Supplement",
    "Times Literary Supplement", "Associated Press", "Elle", "Vogue", "Esquire", "Rolling Stone",
    "The Daily Beast", "Harper's Magazine", "Harper's Bazaar", "Marie Claire", "Glamour", "Real Simple",
    "Good Housekeeping", "Bustle", "The Christian Science Monitor", "Christian Science Monitor",
    "The Dallas Morning News", "Houston Chronicle", "The Miami Herald", "Miami Herald", "The Philadelphia Inquirer",
    "Philadelphia Inquirer", "The Plain Dealer", "The Oregonian", "The Denver Post", "Denver Post", "Newsday",
    "New York Post", "New York Magazine", "Wired", "Forbes", "Fortune", "Bloomberg", "Scientific American",
    "Smithsonian", "National Geographic", "The Irish Times", "The Globe and Mail", "Toronto Star",
    "Shelf Awareness", "Locus", "Tor.com", "The Sydney Morning Herald", "Kansas City Star", "The Root",
    "Ebony", "Essence", "The Millions", "Lit Hub", "Literary Hub", "Book Riot", "Bookreporter",
], key=len, reverse=True)
_PERSON_RE = re.compile(r"^([A-Z][\w'’-]+(?:\s(?:[A-Z]\.\s?){1,2})?(?:\s[A-Z][\w'’-]+){1,2})(?=,|\s*$)")
# Words that end a person's name: the next sentence ("Ann Patchett The ...") or an
# organization ("Timeless Books") rather than a person.
_NOT_NAME_WORDS = {"The", "A", "An", "In", "On", "At", "From", "This", "Now", "With", "And", "Of", "For",
                   "Books", "Press", "Publishing", "Publishers", "Review", "Reviews", "Magazine", "Times",
                   "Journal", "News", "Weekly", "Daily", "Post", "Tribune", "Herald", "Chronicle", "Library"}
_STARRED_RE = re.compile(r"^[,(\s]*starred review\)?", re.I)


def _known_publication(raw: str) -> str:
    """The publication `raw` starts with, if it is a whole-word match not followed by
    a lowercase word ("New York Times bestselling author ..." is not the Times)."""
    low = raw.lower()
    for pub in _PUBLICATIONS:
        if low.startswith(pub.lower()):
            rest = raw[len(pub):]
            if rest[:1].isalnum():
                continue                           # "Timeless", not "Time"
            nxt = rest.strip().split(" ")[0] if rest.strip() else ""
            if nxt[:1].islower() and not _STARRED_RE.match(rest):
                return ""                          # an adjective phrase, not the source
            starred = " (starred review)" if _STARRED_RE.match(rest) else ""
            return raw[:len(pub)] + starred
    return ""


def _trim_source(raw: str) -> str:
    """A clean source name from the text after a quote's dash, or "" if there is no
    recognizable publication or person name there."""
    raw = raw.strip().lstrip("*").strip()
    pub = _known_publication(raw)
    if pub:
        return pub
    m = _PERSON_RE.match(raw.split(",")[0].strip() + ("," if "," in raw else ""))
    if not m:
        return ""
    name = m.group(1)
    words = name.split()
    if any(w in _NOT_NAME_WORDS for w in words[1:]):
        words = words[:next(i for i, w in enumerate(words) if i and w in _NOT_NAME_WORDS)]
        if len(words) < 2:
            return ""
        name = " ".join(words)
        if raw[len(name):len(name) + 1] not in (",", ""):
            return name                            # "Ann Patchett The ..." -> "Ann Patchett"
    after = raw[len(name):].lstrip(" ,")
    pub = _known_publication(after) if raw[len(name):].startswith(",") else ""
    return f"{name}, {pub}" if pub else name


def review_quotes(description: str, title: str = "", author: str = "") -> list[tuple[str, str]]:
    """(quote, source) pairs attributed in the publisher description, in order.
    Skips quotes about a different book ("[The Book Club Cookbook] illustrates")."""
    text = _clean(description)
    surname = norm(author).split(" ")[-1] if norm(author) else ""
    out = []
    for m in _QUOTE_RE.finditer(text):
        quote, src = m.group(1).strip().rstrip(" ,"), _trim_source(m.group(2))
        if not src or _SOURCE_STOP.match(src):
            continue
        if surname and norm(src).split(" ")[-1:] == [surname]:   # the author quoting themself
            continue
        bracketed = re.findall(r"\[([^\]]+)\]", quote)
        if title and any(b[:1].isupper() and len(b.split()) >= 2 and main_title(b) != main_title(title)
                         and not (surname and surname in norm(b)) for b in bracketed):
            continue
        out.append((quote, src))
    return out


def accolades(description: str) -> list[str]:
    """Upper-case accolade phrases from the publisher description, title-cased."""
    text = _clean(description)
    seen, out = set(), []
    for m in _ACCOLADE_RE.finditer(text):
        phrase = m.group(1).strip(" •.,:-")
        if (phrase.upper() == phrase and len(phrase.split()) >= 2 and _ACCOLADE_WORDS.search(phrase)
                and not phrase.endswith((" A", " AN", " THE", " OF", " AND"))):
            nice = re.sub(r"^(?:A|An)\s+", "", _titlecase(phrase))
            if nice.lower() not in seen:
                seen.add(nice.lower()); out.append(nice)
    return out


_SMALL = {"a", "an", "the", "of", "and", "for", "in", "on", "by", "to", "or", "at"}
_UPPER_WORDS = {"nyt", "hbo", "naacp", "npr", "pbs", "bbc", "usa", "us", "uk", "pen"}


def _titlecase(phrase: str) -> str:
    out = []
    for i, w in enumerate(phrase.lower().split()):
        core = w.strip("’'.,:")
        if core in _UPPER_WORDS or re.fullmatch(r"#?\d+(?:st|nd|rd|th)?", core):
            out.append(w.upper() if core in _UPPER_WORDS else w)
        elif i and w in _SMALL:
            out.append(w)
        else:
            out.append(w[:1].upper() + w[1:])
    return " ".join(out)


def credentials(description: str, title: str, author: str) -> tuple[tuple[str, str] | None, list[str]]:
    """The best verified quote (shortest-first among the first three, capped at
    MAX_QUOTE_CHARS) and the accolades, or (None, []) when the copy isn't about
    this book."""
    if not description or not is_about(description, title, author):
        return None, []
    quotes = review_quotes(description, title, author)[:3]
    quote = None
    fitting = [q for q in quotes if len(q[0]) <= MAX_QUOTE_CHARS]
    if fitting:
        quote = fitting[0]
    elif quotes:
        q, src = quotes[0]
        cut = q[:MAX_QUOTE_CHARS].rsplit(" ", 1)[0].rstrip(" ,;:.—–-")
        quote = (cut + "…", src)
    return quote, accolades(description)


# A quote framed as praise: followed by an attribution dash, or introduced by
# critic wording. A quoted story or poem title ("“A Good Man Is Hard to Find”") is not.
_ATTRIBUTION_RE = re.compile(r"[”\"]\s*(?:[—–]|--)\s*[A-Z]")
_PRAISE_CUE_RE = re.compile(r"\b(?:critic|critics|review|reviewer|reviewers|called it|calls it|hailed|praised|"
                            r"raved|acclaimed|described it as|wrote that|declared)\b", re.I)


def strip_unverified_quotes(text: str, description: str) -> str:
    """Drop every sentence of model-written text that presents 4+ quoted words as
    praise (attributed, or framed by critic wording) when those words are not in
    the publisher description. The model is told not to quote reviews; this
    enforces it without leaving a sentence with a hole in it."""
    source = norm(_clean(description))
    sentences = re.split(r"(?<=[.!?”\"])\s+(?=[“\"A-Z])", (text or "").strip())
    kept = []
    for sentence in sentences:
        quoted = re.findall(r"[“\"]([^“”\"]+)[”\"]", sentence)
        praise = _ATTRIBUTION_RE.search(sentence) or _PRAISE_CUE_RE.search(sentence)
        if praise and any(len(q.split()) >= 4 and norm(q) not in source for q in quoted):
            continue
        kept.append(sentence)
    return " ".join(kept).strip()
