# Book detail ratings

Approved presentation: **★ 4.1 ⓘ**. The whole 44-point-high control opens a native
popover saying **Ratings from Hardcover**. No visible label, count or outbound
link. VoiceOver names the score out of five and explains the source action.

The same component appears below title/author metadata in both detail layouts:
For You / Similar Books and Discover / search / saved books / community rankings.
Feed cards do not request or display ratings. Rating loading is independent of
overview generation; unavailable data renders no placeholder or error message.

## Source and identity

`backend/hardcover.py` fetches aggregate scores only. The 100-book October 12 audit
contributes 88 explicit work mappings and 12 unresolved identities in
`backend/data/hardcover_matches.json`. These are identity mappings, never embedded
rating snapshots. A mapped ID is revalidated against its audited title and author
on refresh; one canonical redirect is supported. The 12 duplicate cases stay
hidden until explicitly resolved.

Other titles use a bounded title-plus-author search and require a unique exact
normalized title and full-author match. No fuzzy author overlap, subtitle stripping,
rating-volume tie-break, or ISBN-only join is used. This deliberately favors
omission over wrong-book scores and can miss books with variant titles. The audit's
ISBN conflicts do not participate in this feature and are not repaired here.

Only finite scores greater than zero and at most five, supported by at least 100
ratings, are returned. Rating count and provider identity remain backend-only.
Hardcover's [API guidance](https://github.com/hardcoverapp/hardcover-docs/blob/main/src/content/docs/api/Getting-Started.mdx#commercial-api-use)
allows attributed aggregates; the info popover supplies that attribution. Individual
reviews, user libraries and user profiles are not requested.

## Availability and secrets

The separate authenticated `POST /v1/book-rating` endpoint is optional. Existing
clients and existing response schemas remain compatible. Firestore's shared
`book_rating_cache` serves cached scores for at most seven days; absent, ambiguous and
below-threshold results retry after a day. Provider errors retry after five minutes.
An expired positive cache is never served after a refresh failure. The app also
rejects invalid, unknown-source or stale responses.

Each provider request has a three-second network timeout and no automatic retry;
lookups make at most three calls including a canonical redirect. Cache operations
use two-second timeouts without automatic retry. Bounded in-process locks coalesce
same-book requests; key/quota errors pause provider requests in that instance for
five minutes. Provider limits still apply across instances; this is not a distributed
rate limiter. The app's request timeout is 12 seconds, separate from overview work.

The production key named **Shelf book ratings backend** has `read:catalog` scope
only and expires **October 16, 2027**. Store it in the existing server environment,
never the app or repository. Replace `HARDCOVER_API_KEY` before expiry; removing it
disables ratings. Deployments preserve optional existing variables. If a key is
reset early by the provider, errors omit the control until the key is replaced.

## Verification

- 27 Python tests, including real FastAPI auth/validation/response handling with
  fake storage and network; matching, excerpts/adaptations, duplicates, redirects,
  thresholds, stale data, quota errors, missing key and cache failure.
- Swift executable checks optional/null/malformed/stale rating responses and
  existing model compatibility.
- iOS Simulator Debug build and signed Release archive, version **2.4 (132)**.
- Live catalogue probes: Project Hail Mary and Babel qualify; Staying On and the
  unresolved Big Little Lies mapping return no rating. A conservative unmapped
  Dune lookup is omitted because no unique exact work match was accepted.
- Interactive Simulator access is unavailable in the connected UI tool. Popover
  placement/dismissal, Dynamic Type, VoiceOver and touch behavior still need an
  on-device check. Compilation is not visual verification.

## Release evidence — October 16, 2026

- Production: `shelf-api-00057-vob`, verified at 100% traffic after testing its
  candidate URL. Image digest: `sha256:9945abb8fff77d046558fe7f1337a5d3c0e3a8f4a2baa1667164e228162a26c5`.
- Previous serving revision: `shelf-api-00055-xiz` (retained for rollback).
- Candidate and production checks confirmed qualifying and omitted ratings,
  authentication, no returned counts, and the existing list catalogue. Cached
  candidate repeat lookup took 0.11 seconds in this single smoke check, not a
  latency benchmark. `/healthz` returned Google's 404 on both the old production
  and candidate URLs; checks used the actual API routes and catalogue instead.
- Xcode confirmed **Shelf 2.4 (132) uploaded** to App Store Connect. Upload success
  does not establish TestFlight processing completion or public App Store release.
- Existing Cloud Run settings were preserved. The key is server-only; no personal
  libraries, reviews or profile permissions were granted.
- [Implementation PR](https://github.com/yaronsole/shelf/pull/4).

## Rollback

Route traffic back to the prior Cloud Run revision to restore the old backend.
The new app treats a missing rating endpoint as absence. Alternatively remove
`HARDCOVER_API_KEY` to disable this feature without affecting other endpoints.
The cache is additive; no user data or SwiftData schema is migrated.
