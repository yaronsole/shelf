# Explanation review QA — October 16, 2026

Reader: Yaron, learning evaluation by judging ten blind comparisons on a desktop
browser. Secondary check: a 390 × 844 viewport. This is a local learning tool,
with no changes to the live Shelf product. Build base: `212b9cd`; task branch:
`codex/explanation-eval`. Existing untracked `review/` artifacts were preserved.

Self-reviewed implementation and interaction testing; no independent design judge.
No scores in the QA fixtures are human judgments.

| Source / principle | Contract or action | Evidence / status |
| --- | --- | --- |
| User / YD-01, 03 | One small blind review, meaningful reading context | Ten visible cases; fixed pairs and source notes; five cases withheld. Pass. |
| User / YD-09 | A/B comparisons and honest counts | Counterbalanced mapping; identity and totals hidden until reveal; 17 Python contract tests pass. |
| User / YD-04 | Save choices and notes for later judging | Saved a test choice, note and accuracy flag; reloaded and returned to the case; all restored. Pass. |
| YD-08 | Whole options are clickable, keyboard-labelled controls | Clicked full A/B options; notes and radio/checkbox controls expose labels. Case navigation and Previous exercised. Pass. |
| YD-13 | Completion and reveal work | Finished ten cases in a separate QA run; results table showed ten; reveal mapped the choice correctly and locked edits. Pass. |
| YD-13 | Save failure preserves draft | Stopped QA server, attempted save; choice/note retained and retry shown. Friendly error text added; recovery checked after restart. |
| YD-07, 13 | Responsive comparison layout | Desktop peer columns and 390px stacked options visually inspected, including lower controls; no horizontal clipping observed. |
| YD-09 | Keep uncertainty distinct | Neither, tie and need-more-context remain distinct in storage, summary and export. Pass. |
| YD-11 | Keep user feedback separate from test fixtures | UI test labels use QA-only runs. The real run was left without seeded judgments. Pass. |

Likely friction considered: a reviewer may not know both books, so concise sourced
notes stay visible and an uncertainty choice is available. A reviewer may need
more facts than these notes supply; this is recorded rather than forcing a winner.
Prompt explanations live after reveal so they do not bias choices. No cover image
is needed to judge a short explanation; typographic book identities keep attention
on the text. No new durable design preference was inferred from this self-review.

Limits: viewport simulation is not installed-iPhone verification. No actual human
judgments, AI-judge calibration, automatic prompt-search loop, recommendation lift
or production deployment is claimed. Server restart is required if the local
process exits. Saved judgments persist on disk, with drafts in browser storage.
