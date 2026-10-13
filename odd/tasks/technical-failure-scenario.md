# Technical Failure Scenario

- **Feature:** `technical-failure-scenario`
- **Issue:** #57
- **Parent issue:** #31
- **Branch:** `feat/57-technical-failure`
- **Base:** `origin/feat/31-e2e-integration` at `5f6fd51`
- **Pull request target:** `feat/31-e2e-integration`
- **Status:** Complete; pull request opened
- **Engram mirror:** Pending — local Engram server is incompatible with the installed client.

## Objective

Add an end-to-end scenario proving that a Station AI provider failure is surfaced through the documented recoverable technical-failure contract without exposing partial feedback or weakening safety boundaries.

## Problem and rationale

The existing integration harness proves the happy path but its OpenAI mock only returns successful responses. Issue #57 requires deterministic provider-failure coverage across the real Phoenix boundary. The smallest cohesive change is to make the mock response configurable and assert the existing `502 station_ai_unavailable` contract, unavailable feedback, and a fresh restart session.

## Scope

- Extend the in-process OpenAI mock with a deterministic HTTP failure response.
- Add an integration scenario against the real Phoenix server.
- Assert the documented structured error contract.
- Assert that feedback remains unavailable after failure.
- Assert recovery starts a fresh session.
- Open a pull request from `feat/57-technical-failure` to `feat/31-e2e-integration`.

## Constraints

- Keep the change within the existing integration harness; do not refactor backend architecture.
- Preserve the feature-first dependency direction under `web/src`.
- Keep technical artifacts in English and existing learner-facing contract text in pt-BR.
- `strict_tdd: false` from `SPEC_MVP.md`; tests run after implementation.
- `scripts/test.sh` remains the repository-level verification command.
- Delivery strategy: `ask-on-risk`; forecast is below 400 authored changed lines, so one PR is expected.

## Tasks

- [x] **ODD-57-1 — Prove the recoverable provider-failure contract end to end**
  - State: Done.
  - Route: delegated writer.
  - Trigger: two non-trivial files (`web/src/integration/harness.ts`, `web/src/integration/stationFlow.test.ts`).
  - Acceptance:
    - The mock can deterministically return an upstream failure for the Station AI request.
    - The API client receives HTTP 502 with code `station_ai_unavailable` and the documented pt-BR message.
    - The failed session exposes no criterion-level result.
    - Recovery starts a fresh session with a different session ID.
    - Existing happy-path coverage continues to pass.
  - Checks:
    - `npm --prefix web test -- src/integration/stationFlow.test.ts`
    - `bash scripts/test.sh`
  - Runtime harness: `npm --prefix web test -- src/integration/stationFlow.test.ts` (starts Phoenix plus the in-process provider mock).
  - Rollback boundary: remove only the provider-failure mock option and its integration scenario from the two integration files.
  - Evidence:
    - Writer: focused integration passed (1 file, 3 tests); full suite passed (64 Vitest, 157 ExUnit).
    - Independent verifier: focused integration and full suite passed with the same counts.
    - Parent spot check: focused integration passed (1 file, 3 tests).
    - LSP: reported pre-existing Node type-resolution diagnostics in the integration harness; Vitest and the full repository suite compile and pass the file.
  - Commit: `3044f94` (`test(e2e): cover technical failure recovery`).
  - Native review assessment: unavailable because the untracked ODD task artifact prevented native assessment; RDD is off, so the candidate was treated as high risk and independently verified.

## Progress

- Created the feature branch from the requested parent integration branch.
- Confirmed blocker #56 is closed and merged into the parent branch.
- Mapped the existing harness and documented failure policy.

## Verification evidence

- `npm --prefix web test -- src/integration/stationFlow.test.ts`: passed three times (writer, independent verifier, parent spot check); 1 file and 3 tests.
- `bash scripts/test.sh`: passed twice (writer and independent verifier); 64 Vitest tests and 157 ExUnit tests.
- `git diff --check -- web/src/integration/harness.ts web/src/integration/stationFlow.test.ts`: passed in the writer run.
- LSP diagnostics could not resolve Node built-ins for the pre-existing integration harness configuration; this did not reproduce in either executable verification path.

## Delivery

- Pull request: #138 — https://github.com/ChordanDev/proyectoMed/pull/138
- Required target: `feat/31-e2e-integration`.
- Required issue reference: `Refs #57` because this child PR does not target the repository default branch.
- Required PR label: exactly one `type:*` label, expected `type:feature`.

## Next step

Monitor PR #138 checks and review feedback before merging into `feat/31-e2e-integration`.
