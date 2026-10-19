# 241 — Recognize common clinical phrasings for impresso requests

Issue: #241 (parent #237). Branch: `feat/241-impresso-phrasings` from `feat/237-clinician-demo-readiness`.

## Objective

A candidate who asks for an impresso in common clinical wording ("exame do abdome", "USG de abdome", "TC de abdome", "EAS", "função renal", "proteína C reativa") gets the matching handout instead of "Exame não disponível nesta estação".

## Why

Each acute-appendicitis impresso has one keyword phrase. In the 2026-10-19 run a natural physical-exam request was answered as unavailable, which also limits rubric items 5, 7, 8, 9 and 10.

## Constraints

- Matching stays deterministic (no LLM): normalized keyword matching in `backend/lib/backend/stations/impressos.ex`.
- Prefer authored keyword variants. Change the matcher only when a variant cannot be expressed as a keyword.
- No over-release: "exame" alone and unrelated text release nothing.
- The qualification harness (`backend/priv/stations/qualification/**`) is not edited and keeps passing.

## Tasks

- [x] T1 — Matcher: a keyword matches only when it starts at a word boundary, so short abbreviations (`EAS`, `TC`, `USG`, `sódio`) can be authored without matching inside "áreas", "etc" or "episódio". Tests in `impressos_test.exs`; authoring guide updated.
- [x] T2 — Acute-appendicitis keyword variants for every result impresso. `impresso-4-receituario` holds the expected conduct (Items 9 and 10), so it keeps `keywords: []` and is intentionally never released; the candidate verbalizes the conduct instead. Reproduction test with the issue's phrasings plus over-release guards. Package mapping and clinical review checklist updated.
- [x] T3 — Chest-pain keyword variants (exam, labs, X-ray) with tests and guards.

## Routing

All tasks inline in this bounded writer: one module, two JSON packages, tests and docs; no further delegation.

## Checks

- Focused: `mix test test/backend/stations/impressos_test.exs test/backend/stations/impresso_phrasings_test.exs`.
- Full: local CI script (`local_ci.sh <worktree>`), must print `LOCAL CI PASSED`.

## Progress

- Worktree created from `origin/feat/237-clinician-demo-readiness` at `efc2f30`.
- T1: RED 1 failing test (`dor em outras áreas` matched `EAS`), 9/10 passing. GREEN 10/10 in `impressos_test.exs`; full backend `mix test` 1124 passed. Matcher change justified: `EAS`, `TC`, `sódio` cannot be authored as substring keywords without matching inside "áreas", "etc", "episódio" (the reason they were left out before). Commit: see `git log` (T1 commit `fix(stations): match impresso keywords from a word start`).

- T1 commit: `c4045c1`.
- T2: RED 22 of 33 failing in the new `impresso_phrasings_test.exs` (the over-release guards already passed). GREEN 33/33 after authoring keyword variants; `mix test test/backend/stations` 776 passed. Docs: keyword table and gaps G5–G8 in `package-mapping.md`, checklist keyword and gap rows regenerated from the package (`content_review_records_test.exs` keeps them in step). Qualification cases `modality-gap-02`, `-05`, `-06` now release their impresso; their pending `proposed_expected` notes describe the old gaps and are left for the adjudicator (the harness is not edited). Commit: T2 commit `feat(stations): recognize common phrasings for appendicitis impressos`.

- T2 commit: `659967b`.
- T3: RED 15 of 52 failing (chest-pain phrasings). GREEN 52/52; full backend `mix test` 1176 passed. The chest-pain lab handout carries sodium and potassium, so "eletrólitos", "sódio" and "potássio" release it there; "eletro" is deliberately not authored so it cannot release the ECG on "eletrólitos". No chest-pain keyword docs exist to update. Commit: T3 commit `feat(stations): recognize common phrasings for chest-pain impressos`.

- T4 (review fix, Jorge C1): T2 had made `impresso-4-receituario` releasable on prescription-style requests, handing over the answer key for Items 9 and 10 (maintainer decision 2026-10-19). Keywords restored to `[]`. Tests now assert prescription-style requests release nothing and the receituário is never released by any listed phrasing: RED 2 failing, GREEN `mix test test/backend/stations` 793 passed. Docs (authoring guide, package mapping G7, checklist keyword and G7 rows) state the receituário is intentionally not releasable. Commit: `fix(stations): keep the receituário impresso unreleasable`.

## Next step

PR #249 review, merge into `feat/237-clinician-demo-readiness`.
