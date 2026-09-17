# Shelf — Recommendation Quality: Relevance & Diversity
## Implementation Plan & Claude Code Prompt (backend-only, no UX changes)

---

## PROJECT CONTEXT (read first — a fresh session has no prior history)

**What Shelf is.** A personal iOS book-recommendation app (SwiftUI + SwiftData) for friends and
family. Recommendations are generated server-side by the Claude API from a user's taste profile
(seed books they love) plus reaction history. Owner (Yaron) is non-technical and drives changes
through Claude Code; favor complete, correct edits and explain non-obvious choices in commits.

**Backend:** `/Users/ysole/Desktop/ShelfApp/backend/` — Python FastAPI, Firestore per-user
storage keyed by anonymous token, Claude API. THIS WORK IS BACKEND-ONLY. Do not change any iOS
code, any endpoint shape, any response model, or anything the app renders. The goal is to improve
the RELEVANCE and DIVERSITY of recommendations purely by changing how they are generated.

**Two generation paths (both currently `claude-opus-4-5`, both default sampling — no temperature/
top_p/top_k set anywhere):**
1. **For You feed** — `_generate_recommendations` (main.py ~258) → `build_recommendations_prompt`
   (prompts.py:9). Inputs: seeds, liked, disliked, exclusion list. Asks for 10 books, ~80% match
   / 20% stretch (`is_comfort_zone_push`). Validates `because_of` against real seed titles.
2. **Similar books** — the per-seed "readers also enjoyed" cache, served by
   `/v1/onboarding/suggestions` (get_suggestions, main.py ~376) → `build_suggestions_prompt`
   (prompts.py:74). Inputs: ONE seed title/author + an exclude list. NO taste profile, NO
   like/dislike signal — it is taste-blind today.

**Diagnosed weaknesses (the basis for the phases):**
- No sampling params → conservative, "obvious" picks. Biggest untapped lever.
- Each For You batch is single-shot and independent; it only knows prior *titles* (exclusion
  list), not prior *genres/eras*. Result: title-level novelty but theme/genre/era clustering
  across sessions (e.g. every batch is contemporary literary fiction).
- Within-batch: the comfortable 80% has no axis to spread along, so it can look uniform.
- Disliked signal is bare titles, capped at 50, with no inferred pattern to generalize from.
- Similar-books path ignores the user's broader taste and dislikes entirely.
- `because_of` is post-hoc (pick first, attach a seed after) rather than seed-anchored selection.

**Constraints / conventions.**
- Backend-only. No endpoint or response-model shape changes EXCEPT the debug endpoint in Phase 0
  (additive fields only).
- Keep structured-JSON output reliable: any sampling change must keep the "ONLY a JSON array"
  contract firm and the parser working.
- Owner absorbs API cost (~$10/mo target). A slightly larger response (Phase B/D) is fine;
  avoid extra LLM round-trips.
- Phased, one commit per phase, STOP at each ship gate. Each phase independently revertable.
- Regression guard at bottom — these are previously-fixed bugs; do not reintroduce.

---

## EVALUATION
After each phase, generate a fresh batch for a test user (force=true) and compare against the
enriched debug endpoint (Phase 0). Track: genre spread, era spread, and % comfort-zone-push per
batch, plus a subjective relevance read on the blurbs. There is no automated eval; the debug
fields make diversity measurable instead of eyeball-only.

---

## PHASES

### PHASE 0 — Make diversity measurable  [commit: "feat(recs-p0): debug genre/era spread"]
Additive only; no behavior change to generation.
- Extend `DebugInfoResponse` and `debug_info` (main.py ~409) with, for the most recent batch:
  `genre_distribution` (dict genre→count), `era_distribution` (dict era→count),
  `comfort_push_count` (int), `batch_id` (str). Compute from the latest batch in
  `recommendation_col` (group by stored `batch_id`, newest by `created_at`).
- This is the yardstick for Phases A–D. No prompt or sampling change here.
STOP. Ship gate: /v1/debug/generation-info returns genre/era distributions for the last batch.

### PHASE A — Sampling + within-batch diversity  [commit: "feat(recs-pA): sampling + spread"]
Lowest risk, fastest signal. DIVERSITY HERE IS A GENTLE NUDGE, NOT AN ENFORCED FLOOR — the
reader's actual taste wins; we only prevent a monotonous feed, never force breadth the profile
doesn't support.
- In `_generate_recommendations`, set `temperature` on the For You `claude.messages.create` call
  to a tunable module constant `REC_TEMPERATURE` (start 0.7 — deliberately moderate, not
  adventurous). Keep the suggestions/similar call at a LOWER temperature (`SIMILAR_TEMPERATURE`,
  start 0.4) — "closely related" wants less spread. Define both as named constants at the top of
  main.py so they're trivially tunable.
- In `build_recommendations_prompt`, add a SOFT instruction: avoid clustering the whole batch on a
  single genre/era, but do NOT force genre breadth that isn't reflected in the taste profile — if
  the reader's taste is genuinely narrow, honor that. Do NOT impose a fixed genre count.
  Keep the JSON contract instruction firm and last.
STOP. Ship gate: a fresh batch still parses to valid JSON of {count} items; the batch isn't
single-genre-monotonous, but also hasn't drifted off-taste into forced variety.

### PHASE B — Cross-session counterbalancing  [commit: "feat(recs-pB): genre histogram"]
Attacks RUNAWAY across-session clustering only — not normal taste concentration.
- In `_generate_recommendations`, compute a compact histogram of `genre` (and `era`) over the
  last ~3 delivered batches (cap the lookback so token cost stays bounded). Pass it into
  `build_recommendations_prompt` as a new optional arg `recent_mix: dict | None`.
- In the prompt, if `recent_mix` is present, state what the reader has recently been shown and
  instruct a LIGHT bias against a single genre/era dominating MANY consecutive batches. Do NOT
  push toward genres the reader never signaled, and do NOT override clear taste — this is an
  anti-monotony nudge, not a diversification mandate. Relevance to the taste profile always wins.
- IMPORTANT: same-author / adjacent-author picks (see Phase E) are EXEMPT from this counterbalance.
  Author affinity naturally clusters by genre/era and must not be thinned out by it.
- Default arg so the signature stays back-compatible.
STOP. Ship gate: a genre that dominated several recent batches gets a lighter touch in the next
one, but the feed stays clearly on-taste and author picks (Phase E) are untouched.

### PHASE C — Personalize the similar-books path  [commit: "feat(recs-pC): taste-aware similars"]
Closes the biggest relevance gap in the similar path.
- Pass the user's `liked`/`disliked` summaries (reuse the same gathering logic as For You; cap
  liked/disliked to keep tokens bounded) AND the existing exclusion list into
  `build_suggestions_prompt` via new optional args (default None → current behavior preserved).
- In the prompt, when taste context is present, instruct: stay closely related to the seed book,
  but bias toward this reader's positive signals and steer clear of the patterns in their
  dislikes; never suggest excluded titles.
- get_suggestions must gather and pass this context. Keep the response shape identical.
STOP. Ship gate: similar-books output for a seed avoids the user's disliked patterns and excluded
titles; response JSON shape unchanged so iOS still decodes it.

### PHASE D — Seed-anchored selection + dislike-pattern inference  [commit: "feat(recs-pD): anchored reasoning"]
Tightens relevance; highest prompt-surgery risk, so it ships last.
- In `build_recommendations_prompt`, restructure so the model reasons in two internal steps
  BEFORE emitting JSON: (1) infer what the disliked books have in common and what to avoid;
  (2) for each pick, anchor it to a specific seed (driving selection), rather than choosing freely
  and labeling `because_of` afterward. The reasoning is internal — the FINAL output must remain
  ONLY the JSON array (no preamble), so the parser is unaffected. Optionally request a slightly
  larger pool (e.g. {count}+5) and down-select in Python for max genre/era spread before
  persisting exactly {count}.
- If the larger-pool + down-select is added, do it in `_generate_recommendations` after parse,
  before enrichment/persist; keep stored batch at exactly {count}.
STOP. Final ship gate: output still parses to exactly {count} valid items; `because_of` values
still validate against real seed titles; debug spread holds or improves; blurbs read on-taste.

### PHASE E — Author as a strong, priority-weighted signal  [commit: "feat(recs-pE): author affinity"]
Make "more by an author you love" a strong driver in BOTH paths. PRIORITY-WEIGHTED, NOT A QUOTA:
when a loved author has more eligible work, those picks rank at the top; when they don't, the slot
falls through to adjacent authors / taste matches with no forcing. Never invent a backlist a
real author doesn't have, and never recommend already-excluded titles.

For You (`build_recommendations_prompt`):
- Instruct the model to first identify authors the reader clearly loves (recurring across seeds +
  liked). Treat (a) OTHER works by those authors and (b) authors very close in voice/style as
  TOP-PRIORITY candidates — among the strongest signals, ahead of generic genre matching.
- These author-driven picks are EXEMPT from the Phase A spread nudge and the Phase B counterbalance
  (their genre/era similarity is the point). The diversity nudges apply only to the remaining,
  non-author-driven slots.
- No fixed count: a reader who loves several prolific authors will see more author-driven picks; a
  reader whose loved authors have thin backlists will see fewer, naturally. Don't pad to hit a
  number.

Similar books (`build_suggestions_prompt`):
- Lead with 1–2 OTHER works by the SEED book's author when they have a notable backlist and the
  titles aren't excluded, THEN branch to closely related authors/books. If the author has no
  suitable other work, skip straight to adjacent authors — no filler.

STOP. Ship gate: a profile with a clearly-loved, prolific author surfaces that author's other
work near the top of For You and at the head of that author's similar-books list; a profile whose
loved authors have thin backlists shows no forced/filler author picks; JSON shapes unchanged.

---

## ROLLBACK MECHANICS
- One commit per phase; any phase reverts cleanly because each adds optional args / named
  constants rather than rewriting call sites. Sampling constants can also be tuned toward
  defaults (temperature back toward conservative) without a code revert if a batch regresses.

## REGRESSION GUARD — NEVER reintroduce
1. Same-recs-back-to-back bug: cached recs are marked `delivered=True` on serve; don't break that.
2. Exclusion list MUST keep including every prior rec + seeds + titled reactions, capped at
   `MAX_EXCLUSION_LIST` (currently 150 slice) — don't uncap (token cost) and don't drop members.
3. `because_of` must stay validated against real seed titles; never show "because you loved
   <book the user doesn't own>". Drop the field rather than show a bogus link.
4. Final model output must remain ONLY a JSON array, parseable by the existing `json.loads(raw)` —
   no markdown, no preamble, even with the Phase D reasoning steps.
5. No iOS changes; no endpoint/response-model shape changes except additive debug fields (Phase 0).
6. Keep cover/NYT/reading-time enrichment (`_enrich_book`) and the no-cover handling intact.
7. Don't add extra LLM round-trips; reasoning stays inside the single existing call per path.

═══════════════════════════════════════════════════════════════════════════
## CLAUDE CODE PROMPT (paste below this line)
═══════════════════════════════════════════════════════════════════════════

FIRST: read the "PROJECT CONTEXT" and the phase definitions at the top of this same file
(SHELF_RECS_QUALITY_PLAN.md). This is a BACKEND-ONLY task in
/Users/ysole/Desktop/ShelfApp/backend/. Do not modify any iOS code, any endpoint shape, or any
response model except the additive debug fields in Phase 0. The facts here were verified before
this prompt was written; confirm against the actual files (main.py, prompts.py, models.py) as you
go, since code may have changed.

Before editing, read: prompts.py (both build_* functions), main.py around
_generate_recommendations (~258), get_suggestions (~376), and debug_info (~409), and models.py
(DebugInfoResponse, RecommendationResponse). Match real signatures.

Implement SIX phases IN ORDER (0, A, B, C, D, E). One commit per phase with the prefix shown in
the plan. After each phase, STOP and print the ship-gate check for me to verify before continuing.
Do not collapse phases. Keep every change revertable: prefer new optional args (defaulting to
current behavior) and named module constants over rewriting call sites.

OVERALL TUNING INTENT (applies across phases): diversity is a GENTLE anti-monotony nudge, NOT an
enforced spread — never force variety the taste profile doesn't support. AUTHOR affinity is a
STRONG, priority-weighted signal that is EXEMPT from the diversity nudges.

Phase 0: extend DebugInfoResponse + debug_info with genre_distribution, era_distribution,
comfort_push_count, batch_id for the most recent batch (grouped by batch_id, newest by
created_at). No generation change. STOP at ship gate.

Phase A: add REC_TEMPERATURE (0.7) and SIMILAR_TEMPERATURE (0.4) constants at top of main.py;
apply to the For You and similar calls respectively. In build_recommendations_prompt, add a SOFT
instruction to avoid single-genre monotony WITHOUT forcing breadth the profile doesn't support and
WITHOUT a fixed genre count. Keep the "ONLY a JSON array" instruction firm and last. STOP at ship
gate.

Phase B: in _generate_recommendations compute a genre+era histogram over the last ~3 delivered
batches (bounded lookback) and pass as new optional arg recent_mix to build_recommendations_prompt;
prompt applies only a LIGHT bias against one genre/era dominating many consecutive batches — no
pushing toward unsignaled genres, no overriding clear taste. Author-driven picks (Phase E) are
exempt. Back-compatible default. STOP at ship gate.

Phase C: pass liked/disliked summaries (bounded) + exclusion list into build_suggestions_prompt via
new optional args (default None = current behavior); get_suggestions gathers and passes them;
prompt biases toward positives, avoids dislike patterns and excluded titles, stays close to the
seed. Response shape UNCHANGED. STOP at ship gate.

Phase D: restructure build_recommendations_prompt so the model (1) infers the disliked-books
pattern to avoid and (2) anchors each pick to a specific seed, as INTERNAL reasoning, with the
FINAL output remaining ONLY the JSON array. Optionally request {count}+5 and down-select in Python
for genre/era spread before persisting exactly {count}. because_of must still validate against
real seed titles. STOP at final ship gate.

Phase E: make author a STRONG, PRIORITY-WEIGHTED signal (not a quota) in both paths. In
build_recommendations_prompt, identify clearly-loved authors (recurring across seeds + liked) and
treat their other works + very-close-in-voice authors as top-priority candidates, ahead of generic
genre matching; these picks are EXEMPT from the Phase A/B diversity nudges. In
build_suggestions_prompt, lead with 1–2 other works by the seed's author (if notable backlist, not
excluded) then branch to adjacent authors. Never invent a backlist, never pad to a number, never
recommend excluded titles. JSON shapes unchanged. STOP at ship gate.

REGRESSION GUARD — do not reintroduce: serving same recs back-to-back (keep delivered=True on
serve); uncapping or dropping members of the exclusion list (keep MAX_EXCLUSION_LIST); unvalidated
because_of; non-JSON / preamble in final output (existing json.loads must work); any iOS or
endpoint-shape change beyond additive debug fields; breaking _enrich_book or no-cover handling;
extra LLM round-trips; forcing diversity that overrides clear taste; thinning out author-driven
picks via the diversity nudges; inventing an author backlist or padding author picks to hit a count.
