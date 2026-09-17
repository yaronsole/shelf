# Phase 0 — Findings (Feed, PDP & Polish Plan)

> Read-only investigation for `SHELF_FEED_PDP_POLISH_PLAN2.md`. **Zero code changes made.**
> Date: 2026-06-27 · Backend traced in `backend/`, iOS in `ShelfV2/Shelf/`.
> This is a *different* plan than the existing `PHASE0_FINDINGS.md` (that one covered the community-list/App-Store work). Findings here are fresh and independently verified against current code.
> **Ship gate 0:** Yaron reviews this and confirms the approach for Phases 4–6 before implementation. Phases 1–3 can start once the relevant sections are confirmed.

---

## ★ Headline answer — the sparse-feed question (0.1)

**Yes, there is a real, live overnight batch job.** Verified via `gcloud scheduler jobs list` (not just code): three ENABLED Cloud Scheduler jobs exist in project `shelf-488022` / `us-central1`:

| Job | Schedule | Target |
|---|---|---|
| `shelf-nightly-gen` | `0 3 * * *` (3am PT daily) | `POST /v1/cron/generate-all` |
| `shelf-community-recompute` | `0 4 * * *` (4am PT daily) | `POST /v1/cron/recompute-community` |
| `shelf-nyt-backfill` | `*/3 * * * *` (every 3 min) | `POST /v1/cron/nyt-backfill` |

⚠️ **These jobs are NOT codified in `deploy.sh`** — they were created manually via `gcloud` and live only in GCP. `deploy.sh` only has a *commented-out* example for the community job ([deploy.sh:108-113](ShelfApp/backend/deploy.sh)). If the project is ever recreated, the nightly generation job is lost silently.

**Where generated recs are persisted:** Firestore `users/{uid}/recommendations/{doc}`. Doc shape = the `RecommendationResponse` fields ([models.py:78-96](ShelfApp/backend/models.py)) **plus** `batch_id`, `delivered` (bool), `created_at`, written in [main.py:449-470](ShelfApp/backend/main.py). It is a **queue keyed by a `delivered` flag**, not regenerated-on-read.

**The concrete causes of sparseness, in code (not a guess — traced end to end):**

1. **Every generation produces exactly 10, and there is no "fill to a target" anywhere.** `count=10` is hardcoded in `_generate_recommendations` ([main.py:416](ShelfApp/backend/main.py)). Both the nightly cron and inline on-demand generation produce 10. Nothing tops the feed up toward a target size.

2. **Delivery is throttled to ≤10 per pull and is one-shot.** `GET /v1/recommendations` returns at most 10 undelivered recs and immediately marks them `delivered=True` ([main.py:302-316](ShelfApp/backend/main.py), `.limit(10)`). So even if a multi-day-absent user has 40–50 undelivered recs waiting (cron runs nightly regardless), **one app-open drains only 10**; the rest sit server-side until the next foreground/refresh. This is the single biggest reason "recs were generated but the feed still looks thin."

3. **The exclusion list is capped at 150 and sorted ALPHABETICALLY.** `_generate_recommendations` builds an exclude set from *every* rec ever generated + all seeds + all reactions, then `sorted(...)[:150]` ([main.py:343-358](ShelfApp/backend/main.py), `MAX_EXCLUSION_LIST=150` at [main.py:89](ShelfApp/backend/main.py)). For a heavy user with >150 prior titles, books past the alphabetical cutoff are **not** sent to Claude → Claude re-suggests them → the client then dedups them away (next point) → net new inserts drop well below 10. Alphabetical truncation (vs. recency) is the concrete defect.

4. **The client dedups re-served books against its entire local cache, shrinking net inserts.** On fetch, iOS drops any rec whose `title|author` already exists in SwiftData — including already-reacted and already-seen rows, which are never deleted (only flagged) ([ForYouViewModel.swift:91-94](ShelfApp/ShelfV2/Shelf/ViewModels/ForYouViewModel.swift)). Combined with #3, a "batch of 10" routinely lands as 2–6 genuinely new cards.

5. **A passive launch-time prune removes cards the user never reacted to.** On every launch, `CoverBackfillService.pruneSeenItems` increments `viewCount` for any scrolled-past rec and **permanently filters it (`isReacted=true`) once `viewCount >= 2`** ([CoverBackfillService.swift:11-25](ShelfApp/ShelfV2/Shelf/Services/CoverBackfillService.swift), called from [ShelfApp.swift:38-44](ShelfApp/ShelfV2/Shelf/ShelfApp.swift)). So merely browsing across two sessions burns the feed down without any save/pass.

6. **The daily rotation can net-shrink the feed.** `DailyRotationService` retires the oldest 5 unreacted recs once per calendar day, but only inserts up to 5 *new, non-dupe, covered* ones — and it **retires all 5 whenever it inserts even 1** ([DailyRotationService.swift:60, 99-103](ShelfApp/ShelfV2/Shelf/Services/DailyRotationService.swift)). On a day where generation is mostly repeats, the feed shrinks by up to 4.

7. **Reactions remove cards; replenishment is gated on app lifecycle.** Every save/pass/already-read flips `isReacted=true` ([ForYouViewModel.swift:181-236](ShelfApp/ShelfV2/Shelf/ViewModels/ForYouViewModel.swift)) and the feed `@Query` filters on `!isReacted` ([ForYouView.swift:9-14](ShelfApp/ShelfV2/Shelf/Views/ForYou/ForYouView.swift)). Refill only happens on `onAppear`/foreground/`Generate more`/pull-to-refresh, each netting ≤10. An active reactor empties faster than it refills.

**Net:** there is no persistent, compounding, target-sized feed. The server hands out 10 at a time behind an alphabetically-truncated exclusion list; the client both dedups and actively prunes. That is the sparseness, and it maps directly onto Phase 4's "compound to 50" goal.

---

## 0.1 — Recommendation generation (full trace)

- **Generated in:** `_generate_recommendations` ([main.py:322-470](ShelfApp/backend/main.py)), reached two ways:
  - `GET /v1/recommendations` ([main.py:291-319](ShelfApp/backend/main.py)) — `force=false` returns cached undelivered (≤10, marks delivered); if none, generates inline with `mark_delivered=True`. `force=true` always generates inline (used by "Generate more").
  - `POST /v1/cron/generate-all` ([main.py:579-614](ShelfApp/backend/main.py)) — nightly, every user, `mark_delivered=False`; **skips a user who already has ≥60 undelivered** ([main.py:599-606](ShelfApp/backend/main.py)).
- **On-demand / batch / mix?** **Mix.** Cron pre-generates a nightly undelivered batch; the client also triggers inline generation when no undelivered remain. New users almost always hit the inline path (their seeds postdate the last 3am run).
- **Feed assembly on open:** client renders a SwiftData `@Query` of locally-accumulated `CachedRecommendation` (filter `!isReacted`, [ForYouView.swift:9-14](ShelfApp/ShelfV2/Shelf/Views/ForYou/ForYouView.swift)) **and** fetches up to 10 from the server on appear/foreground ([ForYouView.swift:42, 60](ShelfApp/ShelfV2/Shelf/Views/ForYou/ForYouView.swift) → [ForYouViewModel.swift:42-137](ShelfApp/ShelfV2/Shelf/ViewModels/ForYouViewModel.swift)). So: read-from-store **and** top-up.
- **Exclusion list:** yes — see headline #3. Bounded at 150 but alphabetically, which both risks dupes and (for very heavy users) can crowd out recent titles. The local SwiftData rec store is **unbounded** (rows are flagged, never deleted) — relevant to Phase 4's 50-cap.

## 0.2 — First-time / seed experience

- **Default new-user flow** (`useNewOnboarding=true`, [AppState.swift:33](ShelfApp/ShelfV2/Shelf/AppState/AppState.swift)): Welcome → `finishWelcomeOnly()` lands the user on **Discover** with `forYouFeedUnlocked=false` and **no seeds and no generation yet** ([OnboardingCoordinatorView.swift:43-52](ShelfApp/ShelfV2/Shelf/Views/Onboarding/OnboardingCoordinatorView.swift)). The user accrues seeds from the popular-picks grid / search in `EmptyForYouView`. At 3 seeds ([ForYouView.swift:28](ShelfApp/ShelfV2/Shelf/Views/ForYou/ForYouView.swift)) a one-time "See my picks" prompt triggers the first generation ([EmptyForYouView.swift:86-99](ShelfApp/ShelfV2/Shelf/Views/ForYou/EmptyForYouView.swift) → [ForYouView.swift:31-37](ShelfApp/ShelfV2/Shelf/Views/ForYou/ForYouView.swift)).
- **How many on first load?** Up to **10** — the same hardcoded `count=10` ([main.py:416](ShelfApp/backend/main.py)) as steady-state, minus client coverless/dupe drops. This is exactly Phase 5's "handful of cards that run out."
- **Distinct first-run path?** Only the *trigger/timing* differs (unlock gate, `isFirstGeneration` loading copy). The generation **count and logic are identical** to steady-state — there is no richer first batch. First gen runs inline and can take 30–55s (client timeouts set to 60s/90s to match, [APIClient.swift:10-18](ShelfApp/ShelfV2/Shelf/Services/APIClient.swift)).

## 0.3 — Cover filtering (inconsistent across surfaces — this is the Phase 2 surface map)

A "missing cover" = an **empty string** `cover_url`/`coverURL`. Google Books disqualifies imageless volumes (score −1000, [google_books.py:29-30](ShelfApp/backend/google_books.py)); Open Library returns `None`; `_enrich_book` then stores `""` ([main.py:177-179](ShelfApp/backend/main.py)). The canonical `BookCoverView` renders a `book.closed` **placeholder** for empty/failed URLs ([BookCoverView.swift:95-99](ShelfApp/ShelfV2/Shelf/Views/Shared/BookCoverView.swift)) — i.e. exactly the "blank placeholder" Phase 2 forbids.

| Surface | Coverless filtered? | Where |
|---|---|---|
| For You feed (insert) | ✅ client | [ForYouViewModel.swift:90](ShelfApp/ShelfV2/Shelf/ViewModels/ForYouViewModel.swift), [DailyRotationService.swift:76](ShelfApp/ShelfV2/Shelf/Services/DailyRotationService.swift) |
| Rec generation (backend) | ❌ **persists coverless** | [main.py:177-179, 449-470](ShelfApp/backend/main.py) — no filter before write |
| Similar books | ✅ client (live + cache) | [SimilarBooksSheet.swift:334](ShelfApp/ShelfV2/Shelf/Views/TasteProfile/SimilarBooksSheet.swift), [SimilarBooksCacheService.swift:137](ShelfApp/ShelfV2/Shelf/Services/SimilarBooksCacheService.swift) |
| Community list (backend) | ✅ at compute | [main.py:967-974](ShelfApp/backend/main.py) |
| Curated lists | ❌ **none** → placeholder tiles | [main.py:760-771](ShelfApp/backend/main.py) returns `""`; [ListDetailView.swift:137](ShelfApp/ShelfV2/Shelf/Views/Discover/ListDetailView.swift) renders it raw |
| Search results (Taste/Discover/For-You) | ❌ **none** → placeholder rows | [BookSearchView.swift:225](ShelfApp/ShelfV2/Shelf/Views/Shared/BookSearchView.swift), [EmptyForYouView.swift:438](ShelfApp/ShelfV2/Shelf/Views/ForYou/EmptyForYouView.swift) |
| Discover catalog cards | N/A (gradient cards, no book covers) | [DiscoverView.swift:63-103](ShelfApp/ShelfV2/Shelf/Views/Discover/DiscoverView.swift) |
| Popular-picks grid | ⚠️ pre-dropped at load | [EmptyForYouView.swift:374-394](ShelfApp/ShelfV2/Shelf/Views/ForYou/EmptyForYouView.swift) drops failed lookups |

**Takeaway:** there is **no single shared helper**; filtering is ad-hoc and three surfaces (backend rec persistence, curated lists, search) currently leak coverless items. Phase 2's "centralize one `has valid cover` check + filter backend-first" is a real gap.

## 0.4 — PDP enrichment

- **PDP = `BookDetailView`** ([BookDetailView.swift:100-188](ShelfApp/ShelfV2/Shelf/Views/ForYou/BookDetailView.swift)). Fields shown today: cover, title, author, era, a context row (NYT bestseller + weeks + reading time), genre/comfort-zone/awards tags, a "Because you loved X" *or* `contextTag` line, and the **`blurb`**. Data comes from the local `CachedRecommendation` (no live fetch at open). The curated-list detail sheet (`ListBookDetailSheet`, [ListDetailView.swift:201-283](ShelfApp/ShelfV2/Shelf/Views/Discover/ListDetailView.swift)) already shows a (truncated) description.
- **Full Google Books `description`:** it **is fetched** during enrichment ([google_books.py:93-98](ShelfApp/backend/google_books.py) returns it) but is **discarded for recs** — `_enrich_book` only uses cover + page count ([main.py:176-183](ShelfApp/backend/main.py)), and neither `RecommendationResponse` ([models.py:78-96](ShelfApp/backend/models.py)) nor `CachedRecommendation` ([SwiftDataModels.swift:8-34](ShelfApp/ShelfV2/Shelf/Models/SwiftDataModels.swift)) has a `description` field. **Phase 3 #1 needs only to *store* what's already fetched** — add `description` to the DTO/model and the enrich step. No new per-open fetch.
- **LLM rationale stored?** **Yes, and already shown.** `blurb` ("1-2 sentences, like a well-read friend," [prompts.py:81](ShelfApp/backend/prompts.py)) + `because_of` (validated seed attribution, [prompts.py:95-98](ShelfApp/backend/prompts.py), [main.py:432-438](ShelfApp/backend/main.py)) are persisted on the rec doc and rendered at [BookDetailView.swift:136-155](ShelfApp/ShelfV2/Shelf/Views/ForYou/BookDetailView.swift). There is **no separate "why we picked this" field** beyond these. → Phase 3 #2 is largely already satisfied; **decision needed** on whether you want something richer than the existing blurb (which would mean a prompt change at generation time).
- **`averageRating` / `ratingsCount`:** **not available** — `_query_books` never extracts them ([google_books.py:89-98](ShelfApp/backend/google_books.py)) and they're absent from the DTO/model. Phase 3 #3 needs them added to the same existing Google Books call (no new request) + DTO + a named threshold constant.

## 0.5 — Similar books

- **Generated by** `POST /v1/onboarding/suggestions` → `get_suggestions` → Claude (`claude-opus-4-5`, temp 0.4) ([main.py:476-527](ShelfApp/backend/main.py)). Triggered from the Taste tab's `SimilarBooksSheet` ([SimilarBooksSheet.swift:330-335](ShelfApp/ShelfV2/Shelf/Views/TasteProfile/SimilarBooksSheet.swift) → [APIClient.swift:97-112](ShelfApp/ShelfV2/Shelf/Services/APIClient.swift)).
- **Is the ~10s the LLM?** Yes, primarily — but **enrichment adds non-trivial time**: suggestion covers/NYT/reading-time are fetched **sequentially**, one book at a time ([main.py:523-525](ShelfApp/backend/main.py), each `_enrich_book` doing 2–3 HTTP calls), and the background cache refresh requests `candidateCount=18` ([SimilarBooksCacheService.swift:43](ShelfApp/ShelfV2/Shelf/Services/SimilarBooksCacheService.swift)). The modal's first live fetch is `count=5`.
- **Any caching today?** **Client-only.** `SimilarBooksCacheService` stores results on the `LocalSeedBook` SwiftData row (`similarBooksData`), 8h stale / 24h valid, **per-device** ([SimilarBooksCacheService.swift:41-42, 119-146](ShelfApp/ShelfV2/Shelf/Services/SimilarBooksCacheService.swift)). **No backend/Firestore cache exists.** Natural home for Phase 6: a Firestore collection keyed by `book_id_hash(title, author)` (same scheme as lists, [lists.py:20-25](ShelfApp/backend/lists.py)), checked at the top of `get_suggestions`.
- ⚠️ **Personalization tension to resolve at the gate.** `get_suggestions` currently injects the caller's `liked`/`disliked` taste into the prompt ([main.py:483-506](ShelfApp/backend/main.py)), so results are **user-specific**. Phase 6 says cache per-book, shared across all users ("never key by user"). A shared cache therefore means similar-books becomes **taste-blind** (seed-only). That's a deliberate trade — fine, but it must be a conscious choice. Options: (a) cache seed-only results and drop the per-user lean; (b) cache a seed-only base, keep a light per-user re-rank on top. **Needs your call.**

## 0.6 — Disclaimer / splash / settings

- **First-run disclaimer:** `AIConsentView` ([SettingsView.swift:123-170](ShelfApp/ShelfV2/Shelf/Views/Settings/SettingsView.swift)), shown by `RootView` **first**, before onboarding/splash, whenever `!appState.aiConsentAcknowledged` ([ShelfApp.swift:25-34](ShelfApp/ShelfV2/Shelf/ShelfApp.swift)). Flag persists in UserDefaults ([AppState.swift:47-49](ShelfApp/ShelfV2/Shelf/AppState/AppState.swift)).
- **Splash:** the "splash" is `WelcomeView`, whose background is the looping `SplashCoverScrollView` ([WelcomeView.swift:15](ShelfApp/ShelfV2/Shelf/Views/Onboarding/WelcomeView.swift)); it's the first onboarding step ([OnboardingCoordinatorView.swift:11-24](ShelfApp/ShelfV2/Shelf/Views/Onboarding/OnboardingCoordinatorView.swift)). **Ordering is controlled entirely by RootView's if/else chain** ([ShelfApp.swift:25-34](ShelfApp/ShelfV2/Shelf/ShelfApp.swift)) — today: **disclaimer → splash/welcome → main**.
- **Existing Settings/About to host the disclosure?** **Yes — it already lives there.** `SettingsView` (gear in the Taste tab) has an About section with an "AI" row → `AIDisclosureView`, same copy as the consent screen ([SettingsView.swift:27-30, 102-118](ShelfApp/ShelfV2/Shelf/Views/Settings/SettingsView.swift)). So **Phase 1 is essentially: delete the `AIConsentView` gate from RootView** ([ShelfApp.swift:27-28](ShelfApp/ShelfV2/Shelf/ShelfApp.swift)) so splash shows first; the disclosure stays discoverable in Settings unchanged. No new screen needed.
- ⚠️ **Compliance nuance:** the consent gate was added deliberately for "Apple (2026) requires … disclose it and obtain consent" ([SettingsView.swift:120-122](ShelfApp/ShelfV2/Shelf/Views/Settings/SettingsView.swift)). The plan says Settings/About placement is acceptable for *discoverability*, but it changes **active consent** → **passive disclosure**. Worth a conscious confirm before shipping Phase 1.

---

## Decisions needed before Phases 4–6 (Ship gate 0)

1. **Phase 4 (compounding):** confirm the approach — the core fixes are (a) raise/parametrize delivery beyond `.limit(10)` so a multi-day queue drains in one open, (b) make the exclusion list **recency-bounded** instead of alphabetical, (c) enforce a **50-cap** on the persisted feed with oldest-eviction, (d) reconcile the passive `viewCount>=2` prune + daily-rotation net-shrink with "compound to 50." Server already persists/appends, so this is mostly tuning + a cap, not a new store — but it touches existing culling behavior, so flagging per the additive-only rule.
2. **Phase 5 (rich first feed):** confirm the first-run target count (50-cap ceiling? a one-time larger batch?). Today it's the same 10 as steady-state.
3. **Phase 6 (similar-books cache):** resolve the **shared-vs-personalized** trade above.
4. **Phase 1 (disclosure):** confirm passive disclosure-in-Settings is acceptable vs. the current active consent gate.
5. **Phase 2 (covers):** confirm backend-first filtering for recs + curated lists + search, and that dropping coverless curated-list books (rather than showing placeholders) is desired even if it shortens a curated list.
6. **Phase 3 (PDP):** confirm "Why we picked this" is satisfied by the existing `blurb`/`because_of` (already shown) or whether you want a new, longer rationale captured at generation time.

**No code changed. Awaiting your review before Phase 1.**
