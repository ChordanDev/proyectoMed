# Issue 130: original clinical content and Jev educational qualification

- Issue: #130 (parent #125). Execution mode: HITL.
- Branch: `feat/130-clinical-content`, created from `origin/feat/125-jev-evaluation` at `c978d9a`.
- Worktree: `../proyectoMed-130`.
- Feature document: `odd/tasks/issue-130-clinical-content.md`. Engram mirror topic: `odd/issue-130-clinical-content/tasks`.

## Objective

Load the Content Partner's original station (acute appendicitis, general surgery) into the station package format, and give the humans who own clinical qualification the records and harness they need: provenance and rights, a field-by-field clinical review, acceptance thresholds, adjudicated fixtures, and observed results.

## Problem

- Every package on the parent branch is a fictional placeholder; no partner-authored station exists.
- The package contract only accepts points that are multiples of 0.125. The partner's rubric uses tenths (0.2, 0.4, 0.8, 1.2, 1.4), so it cannot load.
- There is no authoring guide, provenance record, clinical review checklist, qualification harness, adjudicated fixture set, or threshold definition.
- No live Jev adapter exists (`DisabledAdapter` is the only implementation), so observed results against a real model cannot be produced from this branch.

## Why

The official PEP 2025/2 scores items in tenths (for example `0,0 / 0,4 / 0,8`), so the partner's values follow the current official granularity. The 0.125 rule was derived from PEP 2023/1 and is now too coarse. The contract changes, not the authored content.

## Decisions

- 2026-10-07, user: widen the points granularity from multiples of 0.125 to multiples of 0.025, kept as exact integers, with an amendment recorded on ADR-012 (#124). Rejected alternative: rescale the partner's eleven items to eighths.
- The official INEP files the user supplied are a structural reference only. They are not copied into the repository, and no official item or case text is reproduced.
- The partner's station loads with `placeholder: true` until the human review recorded below is complete. Promotion is a human action.

## Scope

In scope: points granularity, the partner-authored package, authoring and review documentation, the qualification harness with fictional qualification cases, and the human review record templates.

Out of scope: a live Jev adapter or provider selection, privacy/ZDR/legal acceptance, STT/TTS vendor comparison, #121 voice-realism work, clinical accuracy claims, and flipping `placeholder` to false.

## Constraints

- No real patient data and no retained learner transcripts or payload logs.
- No invented medical validation, thresholds, or adjudication. Anything a human must decide is left as an explicit pending gate.
- Backend changes stay behind `Backend.Stations`; frontend changes stay inside `web/src/features/station`.
- Artifacts are in English, except authored station content, which is pt-BR.

## Delivery

- Strategy: `feature-branch-chain`, taken from the repository git workflow in `AGENTS.md` (child PRs target the parent issue branch `feat/125-jev-evaluation`, `Refs #130`).
- Forecast: about 1,600 authored changed lines, above the 400-line budget, so the work is sliced by task. Slice boundaries are recorded per task below.
- Receipt-driven development is off for this clone (`clone_local`); ordinary checks apply.

## Tasks

- [x] **T1 — Widen points granularity to 0.025.** Route: delegated writer (schema, validator, points arithmetic, result decimals, web decoder, tests, docs: more than two non-trivial files). Checks: `mix test`, `npm --prefix web test`, `npm --prefix web run typecheck`, `mix format --check-formatted`, `mix compile --warnings-as-errors`. Evidence (2026-10-07): RED observed first (backend: 38 of 285 tests failing in the points, estimates, authored-rules, rubric-assessment, package, and assess-session files; web: 6 of 23 failing in `educational-result.test.ts` against the unmodified decoder). GREEN: `mix test` 774 passed; `mix format --check-formatted` clean; `mix compile --warnings-as-errors` clean; `mix credo --strict` no issues; `npm --prefix web test` 166 passed in 7 files; `npm --prefix web run typecheck` clean; `npm --prefix web run lint` clean. Points are integer fortieths; strings emitted for existing eighth values are unchanged. Slice: one work-unit commit, `aef1dfd`.
- [x] **T2 — Load the partner-authored appendicitis station.** Route: delegated writer. Authored text is transcribed, never rewritten; any rule the schema cannot express is returned as a gap for the partner, not approximated. Checks: package validates through `StationPackage.validate/1`; level points sum to 10.0; loader tests. Evidence (2026-10-07): RED observed first (`mix test test/backend/stations/acute_appendicitis_package_test.exs`: 0 of 8 passed, package file missing). GREEN: the same file 8 passed; `mix test` 782 passed; `mix format --check-formatted` clean; `mix compile --warnings-as-errors` clean; `mix credo --strict` no issues. The package is `backend/priv/stations/acute-appendicitis/package.json` (`placeholder: true`, not the active station); prose was copied from the source by line and every prose string checked as a substring of it. The eleven `adequado` values total exactly 10 in integer fortieths. Mapping, 20 derived fields and 17 gaps for the partner are in `docs/content/acute-appendicitis/package-mapping.md`; two items are not exact (Item 10 can score lower than the source, Item 8 can score higher when the hypothesis is not the main one). Schema, validator and active station id unchanged. Slice: one work-unit commit (this one).
- [x] **T3 — Authoring guide, provenance and rights record, clinical review checklist.** Route: delegated writer (documentation). Checks: structural readback. Evidence (2026-10-07): `docs/content/authoring-guide.md` (rules cited by `path:line` from the validator), `docs/content/acute-appendicitis/provenance-and-rights.md` (template; every human field reads PENDING, no attestation recorded) and `docs/content/acute-appendicitis/clinical-review-checklist.md` (generated from the package: 21 facts, 10 impressos, 11 criteria with every level, point, threshold, action and rule field, plus the 18 gap rows and 20 derived fields; every box unchecked). `backend/test/backend/stations/content_review_records_test.exs` keeps the checklist in step with the package and the mapping record and fails on a ticked box: 4 passed (written after the documents, so no RED was observed). `mix test` 786 passed; `mix format --check-formatted` clean; `mix compile --warnings-as-errors` clean; `mix credo --strict` no issues. The T2 work-unit commit is `e1e5d11`. Slice: one work-unit commit (this one).
- [x] **T4 — Qualification harness and qualification cases.** Fixture format for adjudicated cases, a runner, and fictional cases for ambiguity, unsupported or early disclosure, contradiction, injection, uncertainty, modality gaps, chronology, and technical failure. Thresholds and adjudication stay as human gates. Route: delegated writer. Checks: `mix test`, harness run against the scripted adapter. Evidence (2026-10-07): RED observed first (`mix test test/backend/stations/qualification_test.exs test/backend/stations/qualification test/mix`: 0 of 37 passed, `Backend.Stations.Qualification` not available). GREEN: the same files 37 passed; `mix test` 823 passed; `mix format --check-formatted` clean; `mix compile --warnings-as-errors` clean; `mix credo --strict` no issues; `mix dialyzer` 0 errors. The harness is `Backend.Stations.Qualification` (format in `Qualification.Cases`), reached through `Backend.Stations.run_qualification/2` and `mix stations.qualify <station_id> [--out <path>]`. It drives `CandidateGate.verify_and_deliver/4` and `RubricAssessment.assess/3` with the configured adapter. 33 fictional cases in eight category files and `thresholds.json` are under `backend/priv/stations/qualification/acute-appendicitis/`; every case is `pending` and every threshold is `null`. Observed run with `DisabledAdapter`: 30 cases `adapter_disabled`, 3 `not_adjudicated` (the technical-failure cases, decided in code before the adapter), 0 agreed, 0 disagreed. Agreement arithmetic is tested only with a scripted double and an in-test fixture. The harness never compares results with thresholds and never prints a verdict. Limits returned to the parent: no `first_n` or `order` rule is authored in this package, so the enumeration path is not exercised by any case; model-backed results do not exist. The T3 work-unit commit is `d56568e`. Slice: one work-unit commit, `4f2583d`.
- [ ] **T5 — Results and human review record.** Thresholds and observed-results document, disclaimer and coverage comprehension review record, ADR-012 amendment on #124, child PR. Route: inline plus GitHub. Evidence: pending.

## Human gates (not closable by an agent)

- [ ] Content Partner attests provenance and rights for the appendicitis station.
- [ ] Clinical review of every fact, disclosure condition, template, applicability predicate, level, point, and rule.
- [ ] Acceptance thresholds defined and qualification cases adjudicated.
- [ ] Provider, privacy, ZDR, and legal qualification accepted.
- [ ] Disclaimer and coverage comprehension review, including complete and no-eligible results.

## Acceptance criteria

Those of issue #130. An item is checked only when its outcome was observed; human gates are checked only by the named human.

## Progress

- 2026-10-07: explored the parent branch, confirmed the granularity mismatch against PEP 2025/2, created the branch and this document. Next step: T1.
- 2026-10-07: T1 done. The validator and the assessment share one exactness check (`RubricAssessment.Points.from_authored/1`). Next step: T2.
- 2026-10-07: T2 done. The package loads without a contract change; every rule the contract cannot express is listed as a gap, encoded so that it does not award more than the source, except the Item 8 wording difference recorded as G2b. Next step: T3.
- 2026-10-07: T3 done. The review records exist and are empty; the five human gates stay open. Next step: T4.
- 2026-10-07: T4 done. The harness runs and reports honestly with the disabled adapter; no case is adjudicated and no threshold is defined. Next step: T5.
- 2026-10-07: T5 documentation half done, T5 stays open. Written: `docs/content/acute-appendicitis/qualification-results.md` (what the harness measures, case inventory, undefined thresholds, the observed disabled-adapter run, run-log template, activation gates) and `docs/content/acute-appendicitis/result-comprehension-review.md` (review template, nothing recorded), with pointers from the authoring guide and the result API document. The T4 work-unit commit is `4f2583d`. T5 still needs: the ADR-012 amendment on #124 and the child PR (both the parent's). The five human gates stay open. Next step: the parent completes T5.
