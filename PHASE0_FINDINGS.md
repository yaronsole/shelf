# Phase 0 — Findings & Reuse Plan

> Read-only investigation for the *Community List, Sharing, Search Fix & App Store Readiness* plan.
> Date: 2026-06-19 · Branch: `main` (1 commit ahead of origin) · No code changed.
> **Ship gate:** Yaron reads this, confirms the reuse plan + the 5 corrections + the open decisions, before any edits.

---

## TL;DR

- **The "reuse, don't rebuild" plan holds.** Every feature maps onto an existing component. The community list needs **zero new iOS components** — lists are 100% backend-driven and auto-appear. The share icon is one toolbar item. The cover fix is contained in `BookCoverView`. The search fix is contained in `BookSearchView`.
- **One unavoidable new surface:** there is **no Settings screen at all** today (the v2 redesign deleted it). The contribute toggle, delete-data button, AI disclosure, and privacy link have nowhere to live. A new Settings/About sheet must be *created*. It's additive (touches no existing screen) but it is a genuinely new surface — needs your sign-off on placement.
- **5 corrections to the plan's stated assumptions** (details below): 7 lists not 2; the iOS card renders no emoji/tags; `ITSAppUsesNonExemptEncryption` is **not** set yet; there are **two** distinct "positive" reaction signals (not one "liked"); one cover path bypasses `BookCoverView`.
- **A few decisions are yours** (reaction signal to count, seeding token, list placement/colors, `LIST_SIZE`).

---

## Confirmations (per Phase 0 checklist)

### 1 + Phase 2 — Taste search anchor bug ✅ root cause nailed
- The Taste "Add a book" flow is a `.sheet` → `SeedBookAddSheet` → wraps the shared **`BookSearchView`** in a `NavigationStack`. ([TasteProfileView.swift:73-75, 121-136](ShelfV2/Shelf/Views/TasteProfile/TasteProfileView.swift))
- `BookSearchView`'s root is `VStack(spacing: 0)` with `searchBox` first, then `if isSearchingMode { resultsList } else { idle }`. ([BookSearchView.swift:39-51](ShelfV2/Shelf/Views/Shared/BookSearchView.swift))
- For the Taste sheet, `idle == EmptyView` (convenience init, [BookSearchView.swift:187-191](ShelfV2/Shelf/Views/Shared/BookSearchView.swift)).
- **Exact cause:** when idle, the VStack's content is just the short search box (no height-fill), so its parent **centers it vertically → box renders mid-page**. On the first keystroke (`query.count >= 2`, [line 35-37](ShelfV2/Shelf/Views/Shared/BookSearchView.swift)) `resultsList` — a `ScrollView` ([line 85-86](ShelfV2/Shelf/Views/Shared/BookSearchView.swift)) — expands to fill height, snapping the box to the top. That's the jump.
- **Minimal fix (Phase 2):** pin the root VStack to the top regardless of state, e.g. `.frame(maxHeight: .infinity, alignment: .top)` on the `VStack`. Contained entirely in `BookSearchView`; no layout change to Discover/For-You hosts (their `idle` content already fills the height, so it's a no-op there — to be confirmed at the Phase 2 ship gate).
- ⚠️ **Do NOT** use the "wrap everything in an outer ScrollView" approach — it would nest a ScrollView inside `resultsList`'s ScrollView and alter the idle layouts. The `.frame` approach is the safe one.

### 2 + Phase 1 — Cover-loading bug ✅ every claim confirmed
All in [BookCoverView.swift](ShelfV2/Shelf/Views/Shared/BookCoverView.swift):
- Wraps stock `AsyncImage` (line 43); hi-res transform `&zoom=1→&zoom=3` / `?zoom=1→?zoom=3` (lines 58-63).
- Public API is exactly `init(url:width:)` + `init(url:)` (lines 16-24) — must stay unchanged.
- Placeholder `book.closed` on `.empty`/`.failure` (line 48); 2:3 ratio (lines 30/33), `cornerRadius: 4` (line 36).
- Feed: `LazyVStack` with `.id(rec.id)` + `.onDisappear { markSeenIfScrolledPast }`, which writes to `modelContext` and mutates the `@Query` feed → row teardown/recreation. ([ForYouView.swift:96, 104-118, 222-229](ShelfV2/Shelf/Views/ForYou/ForYouView.swift))
- PDP: cover in a non-lazy `VStack` inside `ScrollView`. ([BookDetailView.swift:102-105](ShelfV2/Shelf/Views/ForYou/BookDetailView.swift))
- **The documented root cause is correct.** Fix = swap the bare `AsyncImage` for a small `NSCache`/`URLCache`-backed loader that reloads in `.task(id: url)` and retries on reappearance. Same visuals, same API → fixes every cover at once. *(See correction #5 for the one exception.)*

### 3 — Reactions schema ✅ (see correction #4 for the important nuance)
- Collection: `users/{user_id}/reactions/` ([main.py:143-144](backend/main.py)). Token comes from `Authorization: Bearer <token>`, used as the doc path, not stored on the doc ([main.py:123-129](backend/main.py)).
- Reaction doc fields: `id, book_id, kind, domain, title, author, cover_url, created_at`, plus `source` when written via a list ([main.py:246-252, 790-800](backend/main.py)).
- `kind` enum ([models.py:8-12](backend/models.py)): `save`, `dismiss`, `alreadyReadLiked`, `alreadyReadDisliked`.
- The recs engine treats `save` **and** `alreadyReadLiked` as "liked", `dismiss`/`alreadyReadDisliked` as disliked ([main.py:345-357](backend/main.py)).

### 4 — List-serving mechanism ✅ reuse confirmed end-to-end
- **Backend:** `GET /v1/lists` → `load_catalog()` reads `data/lists/_index.json`, adds `book_count`, sorts by `sort_order`, `@lru_cache` (busts on redeploy). ([main.py:710-714](backend/main.py), [lists.py:28-44](backend/lists.py)) · `GET /v1/lists/{slug}` → `load_list_books(slug)` + `_resolve_list_covers` (global `list_cover_cache/{book_id}` Firestore cache) + per-user status. ([main.py:720-750, 620-670](backend/main.py))
- **List schema** (`_index.json` entry): `slug, title, subtitle, description, curator, icon_emoji, category, color_start, color_end, featured, sort_order, last_updated`. **Per-list books**: `title, author, year, description` (+ runtime `book_id` = 16-char sha1 of `title|author`, [lists.py:20-25](backend/lists.py)).
- **iOS:** `DiscoverView` renders `ListCatalogCard` from whatever `GET /v1/lists` returns — **no hardcoded slugs** ([DiscoverView.swift:26-58, 63-103](ShelfV2/Shelf/Views/Discover/DiscoverView.swift); [DiscoverViewModel.swift](ShelfV2/Shelf/ViewModels/DiscoverViewModel.swift)). `ListDetailView` is a generic 2-per-row `LazyVGrid` keyed by slug ([ListDetailView.swift:18-46](ShelfV2/Shelf/Views/Discover/ListDetailView.swift)). DTOs: `ListMetadataDTO`, `ListBookDTO`, `ListDetailDTO`, `ListCatalogDTO` ([APIModels.swift:211-291](ShelfV2/Shelf/Models/APIModels.swift)).
- **➡️ A new list surfaces with ZERO iOS changes** — backend returns it in the catalog and it renders + navigates automatically.

### 5 — Settings/UserDefaults UI ⚠️ none exists (see correction #2)
- No `SettingsView`, no gear icon, no settings tab. Tabs are For you · Discover · Shelf · Taste.
- Existing persistence patterns to match: `@AppStorage("hasSeenListTooltip")` ([ListDetailView.swift:10](ShelfV2/Shelf/Views/Discover/ListDetailView.swift)); namespaced `UserDefaults` keys in `AppState` (`com.ysole.shelf.onboardingComplete`, `…hasLaunchedOnce`, `…forYouFeedUnlocked`).
- **Recommended host:** a "Settings & Legal" button in the **Taste tab footer** → presents a `.sheet` with a plain `List`/`Form` of rows. Taste is the de-facto "profile" tab. Needs your OK (correction #2).

### 6 — PDP header (share icon) ✅
- The For-You PDP `BookDetailView` is a `.sheet` → `NavigationStack` + `.toolbar`; `.topBarTrailing` currently holds the dismiss `xmark.circle.fill`. ([BookDetailView.swift:101-167](ShelfV2/Shelf/Views/ForYou/BookDetailView.swift))
- Add one `square.and.arrow.up` button in `.topBarTrailing` (HStack alongside dismiss). The `BookDisplay` model has `title`/`author` → `AmazonLinkService.searchURL(title:author:)` already exists for the payload. No gesture conflict (toolbar button, not a feed gesture).
- ❓ There is a **second** detail surface: the list's `ListBookDetailSheet` ([ListDetailView.swift:201-392](ShelfV2/Shelf/Views/Discover/ListDetailView.swift)). Decide in Phase 3 whether share goes on both or just the For-You PDP.

### 7 — Info.plist / encryption ⚠️ (see correction #3)
- `project.yml` uses `GENERATE_INFOPLIST_FILE: YES` with `INFOPLIST_KEY_*` settings. Current: `TARGETED_DEVICE_FAMILY: "1"` (**iPhone-only**), portrait-only, `MARKETING_VERSION 2.0`, iOS deployment target 17.0, Xcode 16 / Swift 5.10. ([project.yml:17-27](ShelfV2/project.yml))
- **No `ITSAppUsesNonExemptEncryption` key is set** and **no `NSPrivacy*` usage strings** (none needed today — no camera/location/etc.).

---

## Corrections to the plan's stated assumptions

| # | Plan said | Reality | Impact |
|---|-----------|---------|--------|
| 1 | "7 static lists" (Project Context) ↔ my memory said "only Oprah + Reese" | **7 lists confirmed live**: oprah, reese, obama_favorites, nyt_notable_2024, booker_prize_winners, pulitzer_fiction, goodreads_choice_fiction — all `featured`, sort 1-7 ([_index.json](backend/data/lists/_index.json)). My memory was stale. | Plan's context is correct. The new list should slot in at `sort_order: 8` (or 1 if you want it on top). |
| 2 | Settings additions "use the existing settings list pattern — new rows, not a redesigned settings screen" | **There is no settings screen.** It was deleted in the v2 redesign. | We must *create* a Settings/About sheet (additive, new surface). Needs your placement OK. This is the one "stop and surface" item the plan's Additive-only rule calls for. |
| 3 | Assumes "existing `ITSAppUsesNonExemptEncryption = NO`" | **Not set.** | Must add `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO` to `project.yml` in Phase 6, else every submission prompts for export compliance. |
| 4 | Community list scored by users who "enjoyed" each book; treat as one "liked" signal | **Two distinct positive signals:** `save` (want-to-read) and `alreadyReadLiked` (read & loved). They mean different things. | Decision needed (below). A list titled "Loved by readers" is most honest counting `alreadyReadLiked`; `save` adds volume but is aspirational. |
| 5 | "every cover funnels through `BookCoverView`" | **One bypass:** a raw 22×22 `AsyncImage` thumbnail in `SeedBookSearchView`'s `SelectedChip` (onboarding only, no zoom transform, no placeholder). ([SeedBookSearchView.swift:247-255](ShelfV2/Shelf/Views/Onboarding/SeedBookSearchView.swift)) | The `BookCoverView` fix won't touch it. Low impact (tiny onboarding chip). Optional: route it through `BookCoverView` too for completeness. |

---

## Design notes for Phase 4 (community list) — surfaced now to de-risk

- **Cross-user aggregation needs a collection-group query** (`db.collection_group("reactions")`) since reactions are per-user subcollections — likely a one-time **composite index** on the `reactions` collection group for the `kind` filter. Plan for it.
- **Respecting `contribute`:** the `users/{token}` doc **exists** (fields `last_generation_timestamp`, `last_batch_size`; written with `merge=True`, [main.py:448-451](backend/main.py)) — **no `contribute` field yet**. Cleanest: query `users where contribute == false` to get the opt-out set, then exclude their reactions during aggregation (absent flag = contributing).
- **Serve cheap, compute on schedule (matches the plan's cost model):** the daily cron computes the aggregate and **persists** it (Firestore doc or a written `loved_by_readers.json`); `load_list_books("loved_by_readers")` returns the persisted result. Do **not** run the collection-group aggregation on every `/v1/lists/{slug}` request. Metadata (title/colors/emoji) can be a static `_index.json` entry; only the **books** come from the computed blob.
- **Cron pattern exists:** add `POST /v1/cron/recompute-community` guarded by the same `X-Cloud-Scheduler-Auth == CRON_SECRET` check used by the 2 existing cron endpoints ([main.py:563-614](backend/main.py)).
- **Seeding from "Yaron's taste"** requires Yaron's specific **device token** (the backend has no concept of "Yaron"). The recompute job needs that token configured to pull `users/{yaron_token}/seed_books` as the seed set.
- **iOS card caveat:** `ListMetadataDTO` decodes `color_start`/`color_end`/`title`/`subtitle`/`book_count` only — **it does not render `icon_emoji` or `category` tags** ([DiscoverView.swift:63-103](ShelfV2/Shelf/Views/Discover/DiscoverView.swift)). So "same card styling (gradient, emoji, tags)" = gradient + text in practice. Don't add emoji/tags to chase the mockup; match the real card.

---

## Open decisions for Yaron

1. **Which reaction(s) count as "loved"?** (a) `alreadyReadLiked` only — truest to the title; (b) `alreadyReadLiked` + `save` — more volume for a small pool *(matches how recs define "liked")*. **My rec:** start with (b) for volume, revisit if the list looks aspirational rather than loved.
2. **New Settings/About sheet** — OK to create it, hosted as a "Settings & Legal" button in the **Taste tab footer**? (No existing screen to extend.)
3. **Community list placement & color** — `sort_order` (top = 1, or 8 to append) + a gradient `color_start`/`color_end` + `icon_emoji`. Decide at the Phase 5 mockup.
4. **`LIST_SIZE`** — default 30.
5. **Share on one PDP or both?** For-You `BookDetailView` only, or also the list `ListBookDetailSheet`?
6. **Seeding token** — confirm Yaron's device token to use as the seed source (or skip seeding).

## Recommended pre-work (plan calls for it)
- **No repo-root `CLAUDE.md` exists.** The plan wants build/run/deploy there so build-dependent ship gates work. I have all the commands (xcodegen + xcodebuild for iPhone 17 sim; `./deploy.sh` with env vars) in memory and can create it on your go-ahead.

---

## Sequencing reminder
Phases 1 & 2 (cover + search) are isolated, low-risk, and can ship immediately and independently. Phases 4-5 (community list) depend on decisions #1, #3, #6. Phase 6 (App Store) absorbs corrections #2 and #3.
