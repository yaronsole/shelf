# Shelf — Session Handoff

You're continuing work on **Shelf**, an iOS book-recommendation app.
Repo root: `/Users/ysole/Desktop/ShelfApp`. This Claude project's working dir is
`/Users/ysole/Desktop`, and persistent memories under it already capture the key
operational gotchas — **read `MEMORY.md` first.**

## Product
SwiftUI + SwiftData iOS app. Tabs: **For You** (personalized rec feed), **Discover**
(curated + community book lists), **Taste** (seed books you've read), **Shelf**
(saved/reading list). Each book has a PDP (detail sheet): cover, blurb, a structured
**overview** (synopsis + pull-quote cards + accolade badges), and CTAs (Amazon buy,
save, "read it" with loved/disliked sentiment). Tapping a search result also opens
this PDP.

## Architecture
- **Frontend:** `ShelfV2/Shelf.xcodeproj` (scheme `Shelf`, target `Shelf`, bundle
  `com.ysole.shelf`, team `B464PS28T6`, iOS 17+). Views in
  `ShelfV2/Shelf/Views/{ForYou,Discover,TasteProfile,ReadingList,Shared,Onboarding}`,
  models in `Models/`, networking in `Services/APIClient.swift`, base URL in
  `Config/APIConfig.swift` (defaults to prod Cloud Run; override only via the
  `SHELF_API_BASE_URL` scheme env var, so Release/TestFlight always hits prod).
- **Backend:** Python/FastAPI on **Google Cloud Run** — project `shelf-488022`,
  region `us-central1`, service `shelf-api`, URL
  `https://shelf-api-q2fr45guva-uc.a.run.app`. Code in `backend/`: `main.py` (routes),
  `models.py` (Pydantic), `prompts.py` (LLM prompts), `google_books.py`, `lists.py`,
  `data/lists/*.json` (curated lists). Firestore for caches + user data.
- **LLM:** Anthropic API, model `claude-opus-4-5` — used for rec generation and to
  structure messy publisher descriptions into `{synopsis, pull_quotes, accolades}`,
  cached per book in Firestore `book_overview_cache`, versioned by
  `OVERVIEW_CACHE_VERSION` (currently **4**; bump to invalidate all overviews).
- **Metadata:** Open Library (preferred for covers) + Google Books (covers +
  descriptions; **1,000 queries/day quota**). Amazon deeplinks for "buy".

## Overview pipeline (recently hardened — know this)
`POST /v1/book-overview {title, author, description, description_is_fallback}`:
- **For You** passes the rec's stored full GB description (authoritative → skips GB).
- **Discover** passes the curated list description with `description_is_fallback=true`
  → server prefers a live GB fetch (richer) but falls back to the curated text if GB
  is empty/over-quota. The Discover PDP shows the curated text instantly in the
  overview slot and upgrades to the structured version when it loads.
- `_structure_overview` runs one LLM call with a **relevance guard** (returns all-empty
  if the text is clearly about a different book). On failure it sets `_failed`; the
  caller **never caches failures** (self-heal) and **never returns unverified GB text
  on failure** (blanks it → no wrong-book blurbs).
- Catalog-only GB editions (volume id ending `AAJ`) are filtered — they serve
  "image not available" covers + wrong descriptions.

## Git / status
- Branch **`feed-pdp-polish`**, PR **#2** open against `main`
  (https://github.com/yaronsole/shelf). Latest commit `a15df14`.
- Version **2.1**, build **100**.
- Untracked scratch/planning `.md` files at root (`PHASE0_*`, `*_PLAN.md`,
  `SHELF_DESIGN_TOKENS.md`) — not committed; ignore unless asked.

## Build & deploy
**iOS compile-check:**
```
xcodebuild -project ShelfV2/Shelf.xcodeproj -scheme Shelf \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build
```
⚠️ `xcrun simctl` (booting/launching a simulator) **hangs in this environment** — you
can compile and archive but cannot run the app headlessly. The user verifies on a
physical iPhone via TestFlight.

**iOS archive (TestFlight/App Store):** run `./bump_build.sh` first (sets build = git
commit count, always increasing), then:
```
xcodebuild -project ShelfV2/Shelf.xcodeproj -scheme Shelf -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$HOME/Library/Developer/Xcode/Archives/<YYYY-MM-DD>/Shelf-<ver>.xcarchive" \
  -allowProvisioningUpdates archive
```
Archive lands in Xcode Organizer; the **user** does Distribute → Upload (only an Apple
Development cert is in the local keychain — distribution signing happens in the Xcode
GUI). Marketing-version bumps are manual (edit `MARKETING_VERSION`). A closed App Store
"train" (e.g. 2.0 was) requires bumping the marketing version, not just the build.

**Backend deploy:** `backend/deploy.sh` deploys to Cloud Run, warms cover caches, and
(unless `SKIP_COMMUNITY_RECOMPUTE=1`) recomputes the community list. Secrets are **not**
stored locally — read them back from the running service at deploy time:
```
cd backend
export GCP_PROJECT=shelf-488022
eval "$(gcloud run services describe shelf-api --region=us-central1 --project=shelf-488022 \
  --format='json(spec.template.spec.containers[0].env)' \
  | python3 -c 'import json,sys,shlex
e=json.load(sys.stdin)["spec"]["template"]["spec"]["containers"][0]["env"]
[print("export "+x["name"]+"="+shlex.quote(x["value"])) for x in e if "value" in x]')"
export SKIP_COMMUNITY_RECOMPUTE=1   # use while GB quota / Claude credits are tight
./deploy.sh
```
gcloud is authed as `yaronsole@gmail.com`. Deploys take ~3–5 min. After deploying,
verify against the live URL with a `curl`/python hit to `/v1/book-overview` before
pushing.

## Operational gotchas (also in MEMORY.md)
- **Google Books quota (1,000/day):** exhaustion → HTTP 429 → blank/degraded Discover
  overviews. Bumping `OVERVIEW_CACHE_VERSION` or the per-list pre-warm (~12/list) burns
  it fast. Durable remedy (the user **parked** this): raise the Books API quota in the
  GCP console — only revisit if it recurs. See `shelf-google-books-quota`.
- **Anthropic credits:** exhaustion → HTTP 400 "credit balance too low" → structuring
  fails → raw/unstructured overviews + wrong-book matches (guard bypassed). Fix: add
  credits / enable auto-reload at console.anthropic.com → Plans & Billing. Recognize via
  Cloud Run logs (`overview structuring failed: Error code: 400`). See
  `shelf-anthropic-credits`.

## Working norms (user's preferences)
- Additive, focused changes; one logical commit per change; **build/verify before
  committing**; **deploy + verify against the live service before pushing**; push to the
  `feed-pdp-polish` PR branch.
- Commit trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- Surface design decisions you make and offer alternatives; challenge/ask when unsure.

## Open items / next steps
- **App Store submission of 2.1 (build 100) is in progress.** A `Shelf-2.1-100.xcarchive`
  is in Organizer ready to upload. In App Store Connect: upload → wait for processing
  (builds stay grayed/unselectable until processed) → create/select version **2.1** →
  fill "What's New" → select build **2.1 (100)** → **Submit for Review**.
- Enable **Anthropic auto-reload** (and consider raising the GB quota) to prevent
  capacity-exhaustion recurrences.
- Overview structuring is healthy again (credits restored); the v4 cache re-structures
  lazily on read.

## To orient at the start of a session
1. Read `MEMORY.md` (+ the linked memory files).
2. `cd /Users/ysole/Desktop/ShelfApp && git log --oneline -12` on `feed-pdp-polish`.
3. For backend behavior questions, hit the live endpoint with a quick `curl`/python
   probe before changing code.
