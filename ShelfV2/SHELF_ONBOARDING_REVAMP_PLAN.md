# Shelf — Onboarding Friction Removal + List Descriptions
## Implementation Plan & Claude Code Prompt

---

## PROJECT CONTEXT (read first — this session has no prior history)

**What Shelf is.** A personal iOS book-recommendation app (SwiftUI + SwiftData) distributed via
the App Store to friends and family. It generates personalized book recommendations using the
Claude API based on a user's taste profile, which is seeded with books they love. The owner
(Yaron) is not a professional developer and drives the codebase through Claude Code; favor
complete, correct, self-contained edits over clever partial diffs, and explain anything
non-obvious in commit messages.

**Architecture.**
- iOS app: `/Users/ysole/Desktop/ShelfApp/ShelfV2/` — SwiftUI + SwiftData. Auth is an anonymous
  UUID token in Keychain, sent as a Bearer header. SwiftData models live in
  Models/SwiftDataModels.swift. Networking is in Services/APIClient.swift.
- Backend: `/Users/ysole/Desktop/ShelfApp/backend/` — Python FastAPI, Firestore per-user storage
  keyed by anonymous token, Claude API (`claude-opus-4-5`) for recommendations. Curated lists
  live as JSON in backend/data/lists/.
- The two talk over the endpoints defined in main.py; APIConfig.swift holds the base URL.

**Product philosophy (drives the UX decisions below).**
- Recommendations and copy should sound like a well-read friend giving honest, specific opinions
  — NOT generic press-release / publisher-marketing copy. This is why list descriptions are
  rewritten through Claude rather than shipped raw (Phase 0).
- Prioritize low friction and surprise-and-delight for a non-technical audience over technical
  sophistication. The entire point of this change is that forcing a new user to select books
  they've read BEFORE seeing anything is too much friction for a first run.
- The owner absorbs API costs (~$10/mo target), so per-user runtime LLM calls are avoided where
  a build-time job will do.

**Why each decision in this plan is what it is (so you don't "improve" it back into a problem).**
- *Land on Discover, not For You, for new users:* Discover is purely editorial (same for
  everyone, no personalization) so it's never empty — it's a safe, content-rich first screen.
  For You is empty until there's taste signal, so it must not be the cold-open.
- *Don't kill the popular-picks grid:* `EmptyForYouView` already contains the seeding UI
  (search + a grid of popular books to mark read + list shortcuts). It is effectively the old
  onboarding wizard, relocated. We KEEP it as the For You empty state and soften its copy; we do
  NOT rebuild or remove it. Tapping covers there is the fastest path to 3 seeds.
- *Sentiment via reactions, not a new seed field (Option B):* the backend rec prompt (prompts.py)
  already takes three separate inputs — seeds, liked, disliked — where liked/disliked come from
  REACTION history and are weighted more heavily than seeds. So "I read this and liked it" is
  correctly expressed as a seed PLUS a like/dislike reaction. Adding a sentiment field to the
  seed model would mean a SwiftData migration + API contract change for no benefit and worse
  rollback safety. Do not do that.
- *Discover detail sheet (Option A) instead of overloading gestures:* in ListDetailView, tap is
  the Amazon affiliate deeplink and long-press is save — both load-bearing. Adding "mark as read"
  as a third gesture is cramped, so tap now opens a small detail sheet that hosts all three
  actions (Read it / Save / Buy on Amazon). The affiliate path must survive as the Buy button.

**Working conventions.**
- Phased, one commit per phase, stop at each ship gate for human verification.
- Keep changes revertable; Phase 3's user-visible switch is behind an AppState flag.
- Honor the Regression Guard at the bottom — these are real bugs already fixed once.

---

## OBJECTIVE
Remove the mandatory seed-wizard gate. A new user sees one Welcome screen, then lands on the
**Discover** tab (editorial lists). The **For You** tab self-seeds from its existing grid/search
AND from Discover, unlocking personalized recs at **3 seeds**. Every "mark as read" writes a
seed PLUS a like/dislike reaction via the existing `AlreadyReadSheet`. Discover list books get
friend-voice descriptions (currently none exist) so the new detail sheet has content to show.

---

## CONFIRMED CODEBASE FACTS (verified — do not re-derive)

### iOS (`/Users/ysole/Desktop/ShelfApp/ShelfV2/`)
- `ShelfApp.swift` → `RootView` gates whole app on `appState.hasCompletedOnboarding`.
- `AppState.swift`: `completeOnboarding()` flips it; `init` has fresh-install Keychain logic
  keyed on `hasLaunchedOnce` + `onboardingComplete` — DO NOT BREAK.
- `MainTabView.swift`: ForYou=tag0 (default selected), Discover=tag1, ReadingList=2, Taste=3.
  `pendingInitialTab` selects a tab on first appear then clears. `hasForYouBadge` shows a dot.
- `ForYouView.swift`: gates on `seedBooks.count < 3` (`seedThreshold`) → `EmptyForYouView`,
  else real feed. `seedBooks` = `@Query [LocalSeedBook]`.
- `EmptyForYouView.swift`: already has search + popular-picks grid + Oprah/Reese shortcuts.
  Seeds SILENTLY today (addAsSeed / addPopularAsSeed call submitSeedBook with NO sentiment).
- `AlreadyReadSheet.swift` (Shared): sentiment prompt — `onLoved` / `onDidntLike` callbacks.
- `Discover/ListDetailView.swift`: tap=Amazon deeplink, long-press=save. NO "mark read".
  `ListUserStatus` has `.read` + badge rendering ALREADY WIRED but never set.
- `OnboardingCoordinatorView.swift`: welcome → seedSearch. `WelcomeView` has a CTA closure.
  `SeedBookSearchView.submitAndFinish` is the ONLY current path that completes onboarding.
- `LocalSeedBook` (Models/SwiftDataModels.swift): id,title,author,coverURL,addedAt,domain,
  + similarBooks cache fields. NO sentiment field (and we won't add one).
- `APIClient.swift`: `submitSeedBook(title:author:coverURL:domain:)` — NO sentiment.
  `submitReaction(bookId:kind:domain:)` EXISTS with `ReactionKind`. `ListBookDTO` has no description.

### Backend (`/Users/ysole/Desktop/ShelfApp/backend/`)
- `prompts.py`: rec prompt takes THREE separate inputs — `seeds`, `liked`, `disliked`.
  liked/disliked come from REACTION history and are weighted MORE heavily than seeds.
  ⇒ Sentiment belongs in reactions, NOT on the seed. (This is why Option B below is correct.)
- `data/lists/*.json`: 7 lists, 330 books. Fields: title, author, year, (mostly) isbn_13.
  ZERO descriptions anywhere.
- `google_books.py`: `lookup_metadata()` returns cover_url + page_count only — NO description.
  Need a new call pulling volumeInfo.description.
- `open_library.py`: `lookup_cover()` only.
- `lists.py`: `load_list_books(slug)` loads JSON, adds `book_id` hash per book.
- `models.py`: `ListBookResponse` = book_id,title,author,year,cover_url,user_status —
  NO description. `ListMetadata` HAS description (list-level, unused at book level).
- `main.py` ~line 592: builds `ListBookResponse(...)` from `load_list_books`.

### Sentiment design decision: **OPTION B (locked)**
"Mark as read" writes a `LocalSeedBook` + `submitSeedBook(...)` AND fires
`submitReaction(bookId:kind: .liked/.disliked)`. No model migration, no contract change,
matches what the backend prompt actually consumes. Fully revertable.

---

## PHASES (each ships independently; each is revertable)

### PHASE 0 — List descriptions (build-time enrichment + plumbing)
Must land before Phase 2 (the detail sheet needs body content).

**0a. Enrichment script** `backend/enrich_descriptions.py` (standalone, one-off):
- For each book in each `data/lists/*.json`: fetch a raw description from Google Books
  (query by isbn_13 when present, else title+author), Open Library as fallback.
- Rewrite each raw description into a 1–2 sentence friend-voice blurb via the Claude API
  (model `claude-opus-4-5`, matching the backend). Voice: well-read friend, honest, specific —
  NOT publisher marketing. System prompt must instruct: if no source description is available,
  return empty string — DO NOT invent a blurb.
- Write `description` back into each book object in the JSON. Idempotent (skip if already
  filled unless `--force`). Print a summary (filled / skipped / failed) for the review pass.
- Does NOT run at request time. Output is committed after a human skim (~330 blurbs).

**0b. Surface the field through the API + iOS:**
- `models.py`: add `description: str = ""` to `ListBookResponse`.
- `main.py` (~592): pass `description=b.get("description", "")` into `ListBookResponse`.
- iOS `ListBookDTO`: add `description: String` (default "" / optional-decoded for safety).

**Rollback:** revert the model/DTO field + main.py line; JSON descriptions are inert if unused.

### PHASE 1 — Seed plumbing + sentiment (invisible; ships before entry change)
- Add a shared helper `SeedWriter` (free function or small service) that, given title/author/
  coverURL + a `liked: Bool`: writes `LocalSeedBook` (dedup on shared id space "title|author"
  lowercased), calls `submitSeedBook(...)`, then `submitReaction(bookId:kind: liked ? .liked : .disliked)`.
  Books with no cover: still seeded, never displayed (existing rule).
- Rewire `EmptyForYouView` popular-grid tap and search "mark read" to present `AlreadyReadSheet`
  first, then call `SeedWriter`. (Fixes today's silent-seed inconsistency.)

**Rollback:** revert SeedWriter wiring; seeds return to silent. App otherwise unchanged.
**Ship gate:** grid tap shows sheet → writes seed + reaction; `seedBooks.count` increments.

### PHASE 2 — Discover detail sheet (Option A; needs Phase 0 descriptions)
- New lightweight sheet presented when a cover in `ListDetailView` is tapped (REPLACES the
  current tap=straight-to-Amazon). Sheet shows: cover, title, author, one context line
  ("<List Title> · <year>"), the Phase-0 `description`, and three actions:
  **Read it** → `AlreadyReadSheet` → `SeedWriter`; **Save** (existing ReadingListItem path);
  **Buy on Amazon** (existing `AmazonLinkService.searchURL` — affiliate path PRESERVED).
- On Read success, set `ListUserStatus.read` (badge already renders).
- Long-press = save stays as-is. Render gracefully when description is "".

**Rollback:** restore direct tap=Amazon, remove sheet. Discover reverts to today.
**Ship gate:** marking read in Discover increments seeds; Amazon still reachable via button.

### PHASE 3 — Entry-point change (headline; ships last)
- `WelcomeView` CTA calls `appState.completeOnboarding()` directly.
- Collapse `OnboardingCoordinatorView` to welcome-only; retire `SeedBookSearchView` as the gate
  (keep file if reachable elsewhere; otherwise remove from the onboarding path).
- On completion with `seedBooks.count == 0`, set `appState.pendingInitialTab = 1` (Discover).
  Returning seeded users keep landing on For You — do NOT hard-reorder tab tags.
- Set `hasForYouBadge = true` on first launch so For You advertises itself.
- Soften `EmptyForYouView` copy: remove "unlock" / "Pick at least 3"; use progress framing
  (e.g. "<n> of 3 — your shelf starts filling up soon ✦"). Keep the grid + search intact.

**Rollback:** point `RootView` back at full `OnboardingCoordinatorView`; restore default tab 0.
Because Phases 0–2 already shipped, even a full Phase-3 rollback leaves seeding-from-anywhere
and descriptions intact — no stranded new-user state.

---

## ROLLBACK MECHANICS
- Each phase = one self-contained commit. Recommended: gate Phase 3's entry switch behind an
  `AppState` bool (e.g. `useNewOnboarding`) for one TestFlight round before deleting the old
  coordinator path.

## REGRESSION GUARD — NEVER reintroduce
1. Amazon links: use ISBN/title-author search URLs, never ISBN_10-as-ASIN. Discover tap must
   still reach the affiliate link (now via the sheet's Buy button).
2. No duplicate recommendations: seeds + wishlist still in the LLM exclusion list.
3. Books without covers: saved to prevent re-recommendation, NEVER displayed.
4. Badges: use `AwardBadge` / existing status badge styling, not inline yellow capsules.
5. `RecommendationsView` keeps `navigationBarHidden` (no stray headers).
6. Exclusion list stays capped (~100) — don't regress token costs.
7. Refresh UX: pull-to-refresh + rotating taglines; no standalone refresh button.
8. `AppState.init` fresh-install Keychain logic intact; Welcome completion still flips
   `onboardingComplete`.
9. Don't double-write seeds when the same book is acted on in two surfaces (shared id space).
10. Enrichment must never hallucinate a blurb with no source — empty string instead.

═══════════════════════════════════════════════════════════════════════════
## CLAUDE CODE PROMPT (paste below this line)
═══════════════════════════════════════════════════════════════════════════

FIRST: read the "PROJECT CONTEXT" and "CONFIRMED CODEBASE FACTS" sections at the top of this
same file (SHELF_ONBOARDING_REVAMP_PLAN.md). They explain what the app is, why each decision was
made, and the verified state of the code. Do not re-litigate those decisions — if something looks
worth changing, surface it to me as a question rather than silently doing it. The facts were
verified before this prompt was written, but the code may have changed since, so confirm against
the actual files as you go.

You are working in two roots:
- iOS: /Users/ysole/Desktop/ShelfApp/ShelfV2/
- Backend: /Users/ysole/Desktop/ShelfApp/backend/

Implement the onboarding-friction-removal + list-descriptions work in FOUR PHASES, in order.
Commit after each phase with the message prefix shown. After each phase, STOP and print a short
"ship gate" check for me to verify before continuing. Do not collapse phases together.

Read these files before touching anything so your edits match real signatures:
ShelfApp.swift, AppState.swift, MainTabView.swift, ForYou/ForYouView.swift,
ForYou/EmptyForYouView.swift, Shared/AlreadyReadSheet.swift, Discover/ListDetailView.swift,
Discover/DiscoverView.swift, Onboarding/*, Models/SwiftDataModels.swift, Services/APIClient.swift,
and backend: prompts.py, models.py, main.py, lists.py, google_books.py, open_library.py,
and one file in data/lists/.

### PHASE 0 — List descriptions  [commit: "feat(p0): friend-voice list descriptions"]
1. Write backend/enrich_descriptions.py (standalone, run manually, NOT at request time):
   - Iterate every data/lists/*.json except _index.json. For each book: fetch a raw description
     from Google Books (prefer isbn_13 query, fall back to title+author); if empty, try Open
     Library. Add a new Google Books helper that returns volumeInfo.description (lookup_metadata
     currently returns only cover_url/page_count — do not break it; add a separate function).
   - Rewrite each raw description into a 1–2 sentence blurb via the Anthropic API
     (model "claude-opus-4-5"). Voice: a well-read friend giving an honest, specific take — not
     publisher marketing, no "sweeping tale" clichés. SYSTEM PROMPT MUST SAY: if there is no
     source description, return an empty string; never invent details.
   - Write description back into each book. Idempotent: skip already-filled unless --force.
     Print summary counts (filled/skipped/failed). Use ANTHROPIC_API_KEY from env.
   - DO NOT run it automatically. Tell me the command to run it, then pause for my review of the
     generated blurbs before I commit the JSON.
2. models.py: add `description: str = ""` to ListBookResponse.
3. main.py (~line 592): pass description=b.get("description","") into the ListBookResponse(...).
4. iOS ListBookDTO: add a `description` field (decode-safe default ""). Don't render it yet.
STOP. Ship gate: /v1/lists/{slug} returns description per book; iOS still builds.

### PHASE 1 — Seed plumbing + sentiment  [commit: "feat(p1): seeds write sentiment"]
1. Add a shared SeedWriter (function or tiny service, reachable from EmptyForYouView and
   ListDetailView) taking title, author, coverURL, liked: Bool, modelContext. It: dedups on
   "title|author".lowercased(); inserts LocalSeedBook; calls APIClient.submitSeedBook(...);
   then APIClient.submitReaction(bookId: <same id space the backend expects>, kind: liked ?
   .liked : .disliked). Roll back the local insert if the network calls throw (mirror existing
   addAsSeed error handling). No-cover books: still seed, never display.
2. In EmptyForYouView, change popular-grid tap and search "mark read" so they present
   AlreadyReadSheet first, then call SeedWriter with the chosen sentiment. Keep "save"
   (long-press / bookmark) on the existing ReadingListItem path unchanged.
STOP. Ship gate: tapping a grid cover shows the loved/didn't-like sheet, then seedBooks.count
increases and a reaction is posted.

### PHASE 2 — Discover detail sheet  [commit: "feat(p2): discover book sheet + seeding"]
1. In ListDetailView, change cover TAP to present a new sheet (ListBookDetailSheet) instead of
   opening Amazon directly. Sheet shows cover, title, author, a context line
   "<list title> · <year>", the description (render nothing if empty), and three buttons:
   Read it → presents AlreadyReadSheet → SeedWriter (then set ListUserStatus.read);
   Save → existing toggleSave path; Buy on Amazon → existing AmazonLinkService.searchURL(...).
2. Keep long-press = save. Keep the existing first-run long-press tooltip.
STOP. Ship gate: marking a Discover book read increments seeds AND Amazon is still reachable
from the sheet.

### PHASE 3 — Entry-point change  [commit: "feat(p3): land on discover, retire gate"]
Gate this phase's entry switch behind a new AppState bool `useNewOnboarding` (default true) so
it can be flipped back without code revert.
1. WelcomeView CTA → appState.completeOnboarding() directly. Collapse OnboardingCoordinatorView
   to welcome-only; remove SeedBookSearchView from the onboarding path (leave the file).
2. On completion, if seedBooks.count == 0 set appState.pendingInitialTab = 1 (Discover) and
   hasForYouBadge = true. Returning seeded users still default to For You — do not reorder tags.
3. Soften EmptyForYouView copy: remove "unlock"/"Pick at least 3 to unlock"; use progress
   framing showing <count> of 3. Keep grid + search.
4. Preserve AppState.init fresh-install Keychain logic exactly.
STOP. Final ship gate: fresh install → Welcome → Discover; For You shows softened grid; reaching
3 seeds from any surface unlocks the real feed.

REGRESSION GUARD — do not reintroduce any of: ISBN_10-as-ASIN Amazon links; duplicate recs
(seeds+wishlist must stay in exclusion list); displaying no-cover books; inline yellow badges
(use existing status/AwardBadge styling); stray nav headers; uncapped exclusion lists; a
standalone refresh button; hallucinated blurbs (empty string when no source); double-writing
seeds across surfaces.
