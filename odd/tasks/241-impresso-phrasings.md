# 241 — Recognize common clinical phrasings for impresso requests

Issue: #241 (parent #237). Branch: `feat/241-impresso-phrasings` from `feat/237-clinician-demo-readiness`.

## Objective

A candidate who asks for an impresso in common clinical wording ("exame do abdome", "USG de abdome", "TC de abdome", "EAS", "função renal", "proteína C reativa", a prescription) gets the matching handout instead of "Exame não disponível nesta estação".

## Why

Each acute-appendicitis impresso has one keyword phrase, and `impresso-4-receituario` has none, so it can never be released. In the 2026-10-19 run a natural physical-exam request was answered as unavailable, which also limits rubric items 5, 7, 8, 9 and 10.

## Constraints

- Matching stays deterministic (no LLM): normalized keyword matching in `backend/lib/backend/stations/impressos.ex`.
- Prefer authored keyword variants. Change the matcher only when a variant cannot be expressed as a keyword.
- No over-release: "exame" alone and unrelated text release nothing.
- The qualification harness (`backend/priv/stations/qualification/**`) is not edited and keeps passing.

## Tasks

- [x] T1 — Matcher: a keyword matches only when it starts at a word boundary, so short abbreviations (`EAS`, `TC`, `USG`, `sódio`) can be authored without matching inside "áreas", "etc" or "episódio". Tests in `impressos_test.exs`; authoring guide updated.
- [ ] T2 — Acute-appendicitis keyword variants for every impresso, including `impresso-4-receituario` (prescription-style request). Reproduction test with the issue's phrasings plus over-release guards. Package mapping and clinical review checklist updated.
- [ ] T3 — Chest-pain keyword variants (exam, labs, X-ray) with tests and guards.

## Routing

All tasks inline in this bounded writer: one module, two JSON packages, tests and docs; no further delegation.

## Checks

- Focused: `mix test test/backend/stations/impressos_test.exs test/backend/stations/impresso_phrasings_test.exs`.
- Full: local CI script (`local_ci.sh <worktree>`), must print `LOCAL CI PASSED`.

## Progress

- Worktree created from `origin/feat/237-clinician-demo-readiness` at `efc2f30`.
- T1: RED 1 failing test (`dor em outras áreas` matched `EAS`), 9/10 passing. GREEN 10/10 in `impressos_test.exs`; full backend `mix test` 1124 passed. Matcher change justified: `EAS`, `TC`, `sódio` cannot be authored as substring keywords without matching inside "áreas", "etc", "episódio" (the reason they were left out before). Commit: see `git log` (T1 commit `fix(stations): match impresso keywords from a word start`).

## Next step

T2.
