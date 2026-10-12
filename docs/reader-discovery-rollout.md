# Reader discovery: feedback, saved books and community rankings

Base: `feed-pdp-polish` at `46e56af` (2.2/build 123).

Deployment update, October 12, 2026: reader counts are hidden on both the leaderboard and book details at the owner's request. The backend was built as digest `sha256:32b16bb3c5e38834457933820154000e35c357757cb108c9b6ffff942c85855e` and deployed to Cloud Run revision `shelf-api-00055-xiz`, with 100% production traffic after candidate checks. The community aggregate was refreshed and both production leaderboard modes verified. Existing service configuration was preserved. Previous serving revision for rollback: `shelf-api-00051-5qc`.

The iOS archive is version 2.3/build 128. Version 2.2/build 127 was rejected by Apple because the approved 2.2 train was closed. The replacement archive built successfully with the existing release configuration and is being uploaded through Xcode.

## Product behavior

- Discover links to a global **Most loved on Shelf** book leaderboard. Most loved is all-time explicit loves from contributing anonymous device identities, one vote per book per identity. Later dislikes retract a vote; passes and saves do not. Equal counts share a competition rank (1, 1, 3).
- **Recently loved** uses a separate candidate pool, so recent books do not need to enter the popular list first. It is an ordering of recent love events, not a weekly trend or velocity score. Both views show the aggregate update time. Reader counts are deliberately hidden throughout the UI while the community is small; internal counts still determine ranking. Already-read books remain in the global ranking with a read marker.
- The original personalized community discovery endpoint remains compatible. The iOS Discover screen falls back to its existing catalog card if the leaderboard endpoint is unavailable. Before the first new-format recomputation, the recent pool is empty, not fabricated from an all-time list.
- Shelf rows open book details, retain the saved recommendation context, offer an explicit Amazon action, and support one **Up next** pin. Removing a saved book offers Undo.
- For You pass offers Undo and no longer supplies a generalized negative taste signal. Explicit, latest read sentiment drives that signal. The existing exclusion and feed-frequency rules remain.
- For You, Shelf and Similar Books read feedback reuse the existing shared writer used by search and curated list details. Saves from search, popular picks and Similar Books now send book identity/context as well as saving locally. Failed save sync exposes Retry; this is not a persistent offline outbox.
- New active-flow seed writes retain the server ID. Taste deletion also resolves older local UUIDs by title/author before deleting and waits for success before removing the local seed. The backend excludes prior reactions for that book from taste without retracting the community love. A later explicit reading reaction can influence taste again.

## Rollout order

1. Deploy the backend from this branch using the normal project deployment process. No new dependency, secret or scheduler is required. New endpoint: `GET /v1/community/leaderboard?order=popular|recent`; undo: `DELETE /v1/reactions/{reaction_id}`.
2. Run the existing authenticated community recomputation once. Verify both `books` and `recent_books`, their counts and `updated_at` in the resulting snapshot. Normal scheduled recomputation continues thereafter; opt-outs and changed reactions take effect in the aggregate at recomputation, not instantly.
3. Build the iOS app with the owner's existing configuration and inspect the on-device gates below before a TestFlight release. Backend-first matters for pass Undo and changed taste semantics.

No additional model calls are used for ranking, counts, Up next or the reaction fixes. Community recomputation can resolve/enrich more books because it now maintains two candidate pools; metadata enrichment is bounded to their retained union. Opening a saved-book detail reuses the existing overview endpoint and can incur its normal cache-miss generation cost. This is not a claim of unchanged overall spend.

## Verification completed

- Python unittest suite: duplicate votes, identity normalization, contribution opt-outs, non-book domains, changed opinions and time ties, shared ranks, recent ordering, missing timestamps, pass semantics, taste influence removal, bounded prompt signals, global ranks retaining read books, old/empty snapshot behavior and authenticated-user scoping in undo.
- Route tests execute actual handler bodies with fake storage; they do not exercise FastAPI dependency injection or live Firestore.
- Swift model/DTO executable: legacy response compatibility, new counts/ranks, fractional and null timestamps, default Up next state and persistence.
- Real old-schema SwiftData store opened by the new schema to verify additive migration and preservation of saved context (macOS SwiftData).
- iOS Simulator Debug compilation using an ignored, empty-key local Secrets.swift placeholder. Google Books search is not validated by that build. Existing concurrency warnings remain in unrelated legacy/feed code.

Commands:

```sh
PYTHONPATH=backend python3 -m unittest discover -s backend/tests -v
swiftc -parse-as-library ShelfV2/Shelf/Config/DomainConfig.swift ShelfV2/Shelf/Models/APIModels.swift ShelfV2/Shelf/Models/SwiftDataModels.swift tests/BookDataChecks.swift -o /tmp/shelf-book-data-checks
/tmp/shelf-book-data-checks
bash tests/check-model-migration.sh
xcodebuild -project ShelfV2/Shelf.xcodeproj -scheme Shelf -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## On-device gates still required

Interactive Simulator access was unavailable in the connected UI tool. Compilation and data tests do not verify touch targets, layout, voiceover or installed phone behavior.

- New and existing install: open Discover, both leaderboard segments, a book detail, back and retry. Check empty, old aggregate, error, long titles, equal votes and read/saved state. Reader counts must remain hidden in rows and book details; ranks must match the snapshot, and recent must never imply a weekly window.
- From search, Similar Books, a curated list, the leaderboard and For You: save and mark loved/disliked. Check Shelf, Taste, server context and the next aggregate. Repeated loves must not inflate counts. New user contribution false must remain excluded.
- Open an existing saved item; verify original context and explicit Amazon search. Pin/unpin, relaunch, pin a different book, remove and Undo. Existing coverless owned books must remain accessible.
- Pass and Undo with the API delayed; verify the card returns and that reaction is deleted only after the write finishes. Simulate a write failure and verify the restored card is visible and usable.
- Remove a legacy local seed and verify the server seed is removed, existing reactions no longer affect taste, and the community love remains. A network failure must keep the local seed.
- Check narrow phone, large Dynamic Type, dark mode, VoiceOver and safe-area behavior. No new fold or navigation header was added.

## Rollback and limits

Revert this branch's commits to remove the new behavior. Deploying the old backend ignores the extra snapshot fields and `taste_excluded`; note that ignored influence can return under the old prompt logic. The new Up next field is additive; don't discard a user's local store as a rollback mechanism. The existing app can continue consuming the old list endpoints.

Reader counts represent anonymous device identities, not verified unique people. Book identity remains the existing normalized title/author hash; fuzzy edition merging is outside this change. Historical blank-title reactions cannot be reliably repaired without additional evidence. Partial read/seed network failures can still require a retry; a durable offline event queue is not added.

The broader review's mood modes, surprise picks, compare-two flow, neutral finished state and feed hierarchy experiment are subsequent work. This is the first implementation of the feedback/Shelf/community priorities, not a claim that every proposed experiment has shipped.
