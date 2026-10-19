# 239 — Show the station brief (cenário de atuação and tarefas)

Issue: #239 (parent #237). Branch `feat/239-station-brief` from parent branch `feat/237-clinician-demo-readiness`. Worktree `../proyectoMed-worktrees/issue-239`. The child PR targets the parent branch with `Refs #239`.

## Objective

Show the learner the "cenário de atuação" and the numbered tasks before the timer starts, keep them reachable during the station without pausing the timer, and show the station title in the header.

## Why

In the Revalida practical exam the candidate reads the scenario and tasks before entering the room. Today the learner sees only the generic notice, and the header always reads "Estação" because `App.tsx` never passes `title`. The packages have no learner-facing brief: `patient_profile.presenting_context` is examiner-voiced patient-prompt input, and `expected_actions[]` mixes `tarefa-1`..`tarefa-5` with an examiner answer key.

## Constraints

- The brief never exposes rubric answers, examiner-only findings, `expected_actions` answer keys or impresso contents (for example the vital signs, which are Impresso 1 content).
- `presenting_context` is not rendered. A learner-facing brief is authored for both shipped packages (fictional case, pt-BR).
- Contract: required `candidate_brief` object with a non-empty `scenario` string and a non-empty ordered `tasks` list of non-empty strings; no other keys.
- `backend/priv/stations/qualification/` holds qualification thresholds and scenario fixtures, not Station Packages; they are never validated by `StationPackage.validate/1`, so the field does not apply there.
- `BackendWeb` stays thin; `Backend.Stations` stays the public interface. Web keeps `app -> features -> shared`.
- Learner-facing copy is pt-BR and states that the case is fictional.

## Tasks

- [x] T1 Package contract: `candidate_brief` validated by `station_package.ex` and documented in `package.schema.json`; authored for acute-appendicitis and chest-pain; added to valid fixtures; content guard test (no fact, impresso or answer-key text); authoring guide and mapping doc updated.
- [x] T2 API: `GET /api/stations/active` returns `candidate_brief` (projected to `scenario` and `tasks` only); context and controller tests assert nothing from rubric, answer keys or impressos.
- [x] T3 Web data: client decodes `candidate_brief`; `useActiveStation` hook loads the active station.
- [x] T4 Web UI: brief screen between notice and station start; brief dialog during the station (timer keeps running); header shows `display_title`; App wiring and tests.

## Routing

- All tasks: delegated direct (this bounded writer), as assigned by the parent orchestrator.

## Checks

- Backend: `cd backend && mix format --check-formatted && mix compile --warnings-as-errors && mix credo --strict && mix test`.
- Web: `npm --prefix web test`, typecheck, lint, build.
- Full local CI before the PR (mirrors `pr-validation.yml`; GitHub Actions is blocked by billing).

## Delivery

Forecast: about 600–800 authored changed lines across four work-unit commits. Strategy: `single-pr` (one child PR to the parent branch, requested by the parent orchestrator).

## Progress

- Created 2026-10-19.
- T1 done in `61db6c9`. RED: 6 new `station_package_test.exs` tests failed (55/61). GREEN: 61/61; full backend 1105 passed. `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict` clean.
  - Qualification decision: `priv/stations/qualification/` holds thresholds and scenario fixtures, not Station Packages, so the required field does not apply there; its tests keep passing.
  - The acute-appendicitis brief omits the vital signs (Impresso 1 content) and the 18-hour onset (fact `hda-01`); recorded in G12 of the mapping doc.
- T2 done in `e95eeba`. RED: 3 failed (118/121). GREEN: 134/134 across controller, context and active-station config tests. README response example updated.
- T3 done in `5ff9614`. RED: 6 failed and the hook test file failed to import (22/28). GREEN: 31/31. Typecheck and lint clean.
- T4 done in `9d112d7`. RED: BriefScreen test file failed to import, 5 tests failed (72/77). GREEN: 82/82; full web 213 passed; typecheck, lint, build clean.
- Local CI (`local_ci.sh`): LOCAL CI PASSED. Web unit 209 passed, backend 1107 passed, web e2e 4 passed, dialyzer 0 errors. GitHub Actions is blocked by billing.
- Pending: live check of the brief on acute-appendicitis with `ACTIVE_STATION_ID=acute-appendicitis` (parent rehearsal, #237).

## Next step

Open the child PR to `feat/237-clinician-demo-readiness`; clinician review of the authored brief wording.
