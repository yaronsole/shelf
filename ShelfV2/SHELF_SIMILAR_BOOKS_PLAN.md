# Shelf — Similar Books: Stop Showing the Same Results
## Implementation Plan & Claude Code Prompt (iOS-only; backend already supports it)

---

## PROJECT CONTEXT (read first — a fresh session has no prior history)

**What Shelf is.** A personal iOS book-recommendation app (SwiftUI + SwiftData) for friends and
family. Recommendations come from a Python FastAPI backend calling the Claude API. Owner (Yaron)
is non-technical and drives changes through Claude Code; favor complete, correct edits and explain
non-obvious choices in commits. Owner absorbs API cost (~$10/mo target), so avoid spending an LLM
call on idle browsing — the Taste tab is a low-intent, click-around surface.

**The problem.** In the Taste tab, tapping one of your seed books opens `SimilarBooksSheet`
("books similar to this"). It shows the SAME 5 results almost every time. This is the symptom to
fix: opening the same book should not feel identical each time.

**Root cause (verified — this is by-design behavior, not a crash bug):**
- `SimilarBooksCacheService` caches 10 candidate suggestions per seed.
  `staleThreshold` = 8h (background refresh), `validThreshold` = 24h (still shown in modal).
- `SimilarBooksSheet.initialLoad()` serves from cache whenever `isCacheUsable` (cache ≤24h old) —
  so for 24h every open re-uses the same 10 candidates with no new fetch.
- `displaySuggestions(for:sessionId:)` picks 5 of the 10 via a DETERMINISTIC shuffle keyed on
  `"\(sessionId)|\(generationToken)"`. Intent (per code comment): stable within a session, rotates
  across sessions. But within one app session BOTH inputs are constant ⇒ the same book opened
  repeatedly in one sitting yields the IDENTICAL 5. Rotation only happens across sessions, and even
  then it reshuffles the SAME 10 — never new books until the 24h window lapses.
- `candidateCount = 10`, `displayCount = 5`. Cover-image filter is applied on cache write
  (regression guard — never show cover-less books).

**Already present (so Phase 3 is mostly wiring, not new infra):**
- `SimilarBooksSheet` already has `loadMoreLive()` and `forceRefresh()` that fetch from the backend
  with the suggestion HISTORY in the exclude list (genuinely new books). `APIClient.fetchSuggestions
  (for:count:exclude:)` exists. Suggestion history persists in UserDefaults per seed key.
- Backend `/v1/onboarding/suggestions` already honors `exclude` and (after the recs-quality plan's
  Phase C/E, if applied) taste-awareness. NO backend change is required for THIS plan.

**Chosen approach: HYBRID (free variety by default, paid novelty on demand).**
Keep the cache as the instant-display layer. (1) Re-roll the display shuffle on EVERY sheet open so
within-session repeats vanish at zero cost. (2) Widen the cached pool so the reshuffle has more to
draw from before any network call. (3) Wire an explicit "more like this" affordance to the existing
on-demand history-excluded fetch — the ONLY path that spends an LLM call, gated on user intent.
Known limit (acceptable): 1–2 reshuffle a fixed deck, so a user opening the same book many times
will eventually cycle through the pool; lever 3 is the escape valve for that.

**Constraints / conventions.**
- iOS-only. No backend change. No endpoint/response-model change.
- Preserve the cover-image regression guard (never display cover-less books).
- Don't spend an LLM call on a plain sheet open — only on the explicit "more" affordance.
- Phased, one commit per phase, STOP at each ship gate. Each phase independently shippable.

---

## PHASES

### PHASE 1 — Per-open re-roll (the symptom fix; zero cost)  [commit: "feat(sim-p1): per-open rotation"]
- Replace the session-stable shuffle seed with a per-OPEN nonce. In `SimilarBooksSheet`, generate a
  fresh rotation nonce each time the sheet appears (e.g. a `UUID().uuidString` stored in `@State`
  set in `onAppear`/`task`), and pass it to `displaySuggestions` instead of (or in addition to)
  `sessionId`. Change `displaySuggestions(for:sessionId:)` to take a `rotationKey: String` used in
  the hash input. The deck still comes from cache; only WHICH 5 show changes per open.
- Keep the cover-image filter and the cached-deck source intact.
STOP. Ship gate: open the same Taste book 3× in one session → a visibly different 5 each time
(until the pool is exhausted). No new network calls fire on open.

### PHASE 2 — Widen the candidate pool  [commit: "feat(sim-p2): bigger candidate pool"]
- Raise `candidateCount` from 10 to ~18 (keep `displayCount` = 5). The refresh already fetches
  `candidateCount` and filters cover-less results, so a bigger pool means more genuinely-unseen
  cards before the reshuffle repeats. One slightly larger response on refresh; NOT more calls.
- Sanity: ensure nothing assumes exactly 10 (display logic uses `all.count`, so it's fine, but
  verify).
STOP. Ship gate: a freshly-refreshed seed holds ~15+ candidates; repeated opens stay varied
longer before any repeat.

### PHASE 3 — On-demand "more like this" (the paid escape valve)  [commit: "feat(sim-p3): more-like-this CTA"]
- Surface a user-tappable affordance in `SimilarBooksSheet` (e.g. a "Show me different ones" /
  "More like this" button, in keeping with the collector-themed, playful CTA voice — not a generic
  "Refresh") that calls the EXISTING `loadMoreLive()` (preferred — it excludes history so results
  are genuinely new) or `forceRefresh()`. Do NOT trigger this automatically on open.
- Ensure newly fetched results append to the seed's suggestion history (the existing
  `appendHistory` path) so subsequent fetches keep excluding them.
- Maintain the cover-image filter on any newly fetched results.
STOP. Ship gate: tapping the CTA fetches books not previously shown for that seed; a plain open
still costs nothing; cover-less books never appear.

---

## ROLLBACK MECHANICS
- One commit per phase. Phase 1 is the high-value, lowest-risk change and ships alone if desired.
- Reverting any phase is clean: Phase 1 restores the session-keyed shuffle; Phase 2 restores
  `candidateCount = 10`; Phase 3 removes the CTA wiring (the underlying `loadMoreLive`/`forceRefresh`
  already existed and stay).

## REGRESSION GUARD — NEVER reintroduce
1. NEVER display books with empty `coverURL` (cover filter on cache write AND on any live fetch).
   Cover-less books may still be tracked but not shown.
2. Don't fetch from the backend on a plain sheet open — only the explicit Phase 3 CTA spends a call.
   (Protects the API-cost ceiling.)
3. Don't break the suggestion-history exclusion: newly shown titles must be appended to history so
   they're excluded from future fetches (prevents duplicate suggestions).
4. The deterministic shuffle was INTENTIONAL (stable within a session) — we are deliberately
   changing it to per-open. Don't "fix" it back to session-stable.
5. No backend change; no endpoint/response-model change; iOS-only.
6. Keep `invalidate(seed:)` behavior on seed removal intact.

═══════════════════════════════════════════════════════════════════════════
## CLAUDE CODE PROMPT (paste below this line)
═══════════════════════════════════════════════════════════════════════════

FIRST: read the "PROJECT CONTEXT", "PHASES", and "REGRESSION GUARD" sections at the top of this
same file (SHELF_SIMILAR_BOOKS_PLAN.md). This is an iOS-ONLY task in
/Users/ysole/Desktop/ShelfApp/ShelfV2/. Do NOT change the backend, any endpoint, or any response
model. The facts here were verified before this prompt was written; confirm against the actual
files as you go, since code may have changed.

The problem: tapping a seed book in the Taste tab opens SimilarBooksSheet and shows the same 5
results almost every time. Cause: a 24h-usable cache of 10 candidates plus a display shuffle keyed
on session+generationToken (both constant within a session), so repeated opens in one sitting are
identical. Fix = hybrid: free per-open rotation by default, paid fresh fetch only on an explicit CTA.

Before editing, read: Services/SimilarBooksCacheService.swift (displaySuggestions, refresh,
candidateCount/displayCount, thresholds) and Views/TasteProfile/SimilarBooksSheet.swift
(initialLoad, liveFetchInitial, loadMoreLive, forceRefresh, sessionId). Match real signatures.

Implement THREE phases IN ORDER. One commit per phase with the prefix shown. After each phase,
STOP and print the ship-gate check for me to verify before continuing. Do not collapse phases.

Phase 1 (zero cost, the symptom fix): change displaySuggestions to take a per-OPEN rotationKey
(fresh UUID generated in the sheet on each appear) used in the shuffle hash, instead of the
session-stable key. Repeated opens of the same book now show a different 5 from the cached deck.
Keep the cover filter and cached-deck source. STOP at ship gate.

Phase 2: raise candidateCount from 10 to ~18 (displayCount stays 5) so the reshuffle has more
unseen cards before repeating. Verify nothing assumes exactly 10. One bigger refresh response, not
more calls. STOP at ship gate.

Phase 3: add a user-tappable "more like this / show different ones" CTA (collector-themed, playful
voice — not a generic Refresh) that calls the EXISTING loadMoreLive() (history-excluded → genuinely
new) — never auto-triggered on open. Ensure new results append to suggestion history and pass the
cover filter. STOP at ship gate.

REGRESSION GUARD — do not reintroduce: showing books with empty coverURL; fetching from backend on
a plain sheet open (only the Phase 3 CTA may spend a call); breaking suggestion-history exclusion
(append shown titles so they're excluded next time); reverting the shuffle to session-stable; any
backend/endpoint/response-model change; breaking invalidate(seed:) on seed removal.
