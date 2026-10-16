# Shelf's first explanation eval

This is a small learning experiment: **which short explanation makes a fixed book
recommendation more accurate, specific and useful to a reader?** It does not judge
the whole recommendation system or choose books for production.

## Start the review

From the repository root:

```sh
python3 evals/explanations/serve.py
```

Open [the local review](http://127.0.0.1:8765). No package installation or API key is
needed to review the included first run. The server must remain running; restart
with the same command if the page becomes unavailable. It listens on this Mac only.

For each of ten comparisons, read the fictional reader profile and brief book
notes, then choose A, B, equally good, neither, or need more context. Add a short
reason when you can. **Save & next** writes the judgment to disk. Unsaved drafts
are kept in browser storage. You can pause and resume, or revise saved choices
before revealing the versions. Reveal is available only after all cases have a
choice; it locks the round to preserve the original blind judgments.

The results table and JSON/CSV downloads separate ties, rejection and uncertainty.
Judgments are in `runs/round-01/judgments.json`, ignored by Git. They remain local
unless the reviewer explicitly shares them. Test-only judgments are isolated in
the ignored `qa-runs` directory and must never be treated as human feedback.

## What is held constant

- Fifteen fixed cases: ten development cases and five reserved final-check cases.
  The two splits use different books. Held-out cases are not generated or sent to
  the review browser in this round.
- Each comparison has the same seed book, recommended book, source notes,
  fictional reader and model settings. Reader preferences are invented test
  scenarios, not records of real users or claims about Yaron's taste.
- Baseline: the current `RecommendedBookOut.because_of_reason` field instruction,
  copied verbatim from `backend/models.py` at `212b9cd`.
- Candidate: that same instruction plus one paragraph directing the writer to
  select an evidence-supported overlap relevant to the reader, or abstain.
- Both prompts share a grounding wrapper and the same 12-word / 120-character
  limits. This is an **adaptation of the current instruction in an isolated
  writing task**, not a production replay: real Shelf selects books and other
  fields together, and does not receive these exact fictional taste statements.
- Source notes are short assistant-written paraphrases of linked publisher or
  author material, checked October 16, 2026. They are limited evidence and may
  omit relevant aspects. The uncertainty option records insufficient context.

A/B assignments are fixed for the run and counterbalanced: each instruction
appears on the left five times. The generator shuffles call order independently.
Prompt identities, scores and design tags are not sent to the page before reveal.
The raw manifest in Git contains the mapping for reproducibility: **review before
reading `baseline.txt`, `candidate.txt`, or the run manifest** if you want to stay
blind. This is concealment during review, not cryptographic secrecy.

## Generation evidence

`runs/round-01/manifest.json` retains the dataset hash, exact prompts, code base,
random seed, model requested/returned, first outputs, usage, timing
and deterministic checks. The initial run made 20 calls, all returning
`claude-opus-5-5`; usage was 17,666 input and 698 output tokens. All outputs fit
the shared display limits. **No human quality scores exist until the review is
completed.** Mechanical validity is not evidence of recommendation quality.

The generator makes no Shelf API calls and never imports `backend/main.py`, so
it cannot write to reader histories or recommendation collections. It uses the
Anthropic Messages API with a JSON schema, documented in the
[official structured-output guide](https://platform.claude.com/docs/en/build-with-claude/structured-outputs).
Credentials are read only from the process environment and never written to
artifacts. The initial run used Shelf's already-configured provider credential
in memory. The live app and its prompts were not changed or deployed.

To make a fresh run after setting `ANTHROPIC_API_KEY` securely in your environment:

```sh
python3 evals/explanations/generate.py --run round-02
python3 evals/explanations/serve.py --run evals/explanations/runs/round-02
```

Use a new run name; existing runs cannot be overwritten. Generation is bounded
to two calls per selected case, two workers by default, and 2,048 output tokens
per call. There are no quality-based retries or discarded alternatives. API or
incomplete-response failures mark the run failed, retain completed evidence, and
prevent review. These bounds limit calls/tokens, not a guaranteed dollar cost.

The reserved split requires both `--split holdout` and `--release-holdout`. Do not
use it while changing prompts. Once inspected to guide changes, those cases are
development material and a new untouched check set is needed.

## How this grows into loops

1. **Human evaluation now:** inspect which explanations fail and why. Revise the
   rubric or one prompt decision; rerun on development cases. Keep versions and
   original labels. One draw per condition is exploratory, not a stability study.
2. **Automated judging next:** give an AI judge the book notes, outputs and human
   rubric; hide variant identities. Compare its judgments with yours. Report
   disagreements and uncertainty separately, and check sensitivity to A/B order.
   Keep some human-labeled development cases out of judge tuning as a check of
   judge agreement. Five recommendation holdouts alone do not validate a judge.
3. **Bounded autonomous improvement later:** freeze the judging rubric and
   check set; let a separate improvement process propose prompt edits and score
   them. Set an iteration limit, cost ceiling and no-improvement stop condition.
   It may change the candidate prompt, not the judge, dataset, human labels or
   evaluation rules. Retain every attempt, including regressions. Check final
   candidates on held-out cases and review examples before any product rollout.

This round is deliberately small and chosen by us. It is not a representative
sample of Shelf traffic or a statistically powered experiment. Better explanations
can still rationalize weak book choices. Actual reading satisfaction, fuller
recommendation quality, latency and cost need separate evaluation.

## Checks

```sh
python3 -m unittest discover -s evals/explanations/tests -v
node --check evals/explanations/web/app.js
```

Tests cover hidden mappings, protected holdouts, persisted and corrected labels,
version assignment, distinct outcomes, reveal locking, export fidelity, local
request protections, dataset separation and shared prompt context. Browser QA
uses a separate run; see `QA.md` for the verified interactions and limitations.
