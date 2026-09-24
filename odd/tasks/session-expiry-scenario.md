# Session Expiry Scenario

- **Feature:** `session-expiry-scenario`
- **Issue:** #58
- **Parent issue:** #31
- **Branch:** `feat/58-session-expiry`
- **Base:** `origin/feat/31-e2e-integration` at `8f73ead`
- **Pull request target:** `feat/31-e2e-integration`
- **Status:** In progress
- **Engram mirror:** Pending — local Engram server is incompatible with the installed client.

## Objective

Add an end-to-end scenario proving that session expiry is handled predictably across the real Phoenix boundary, returning the documented 410 `session_expired` response, asserting no stale result is accessible or displayed, and verifying clean recovery with a fresh session.

## Problem and rationale

The existing integration suite covers the happy path (#56) and technical upstream failure (#57). Issue #58 requires an end-to-end integration scenario where a session expires or is missing. The backend already contains logic for expiring sessions via ETS lookup in `Backend.Conversation` and returning 410 with `session_expired` in `BackendWeb.StationController`. To test this predictably end to end without introducing arbitrary long sleeps in the test suite, the backend runtime should accept a configurable conversation timeout via environment variable (e.g. `CONVERSATION_TIMEOUT_MS`), and the E2E harness should expose this configuration.

## Scope

- Allow configuring `conversation_timeout_ms` via `CONVERSATION_TIMEOUT_MS` in `backend/config/runtime.exs`.
- Support `conversationTimeoutMs` option in `web/src/integration/harness.ts`.
- Add an E2E scenario in `web/src/integration/stationFlow.test.ts` asserting:
  - Expired session returns HTTP 410 with code `session_expired` and message `"A sessão expirou."`.
  - Finishing or sending a message on an expired session returns 410 `session_expired` or 404 `session_not_found`.
  - Missing/deleted session returns HTTP 404 with code `session_not_found`.
  - Results remain unavailable (`fetchResult` fails; no stale criterion results are returned).
  - Recovery starts a fresh, active session with a new session ID and successful interaction.
- Add unit test coverage in `web/src/features/station/hooks/useStation.test.ts` for session expiry handling and clean recovery via reset.
- Open a pull request from `feat/58-session-expiry` to `feat/31-e2e-integration`.

## Constraints

- Keep Phoenix context interface and modular monolith invariants under `backend/`.
- Preserve feature-first dependency direction under `web/src`.
- Keep technical artifacts in English and learner-facing contract strings in pt-BR.
- Single command `bash scripts/test.sh` must pass.
- Child PR targets parent issue branch `feat/31-e2e-integration` using `Refs #58`.

## Tasks

- [x] **ODD-58-1 — Support configurable conversation timeout in backend and E2E harness**
  - State: Done.
  - Route: inline direct.
  - Allowed edit surfaces: `backend/config/runtime.exs`, `web/src/integration/harness.ts`.
  - Acceptance:
    - `CONVERSATION_TIMEOUT_MS` env var is recognized in `backend/config/runtime.exs`.
    - `E2EHarnessOptions` accepts `conversationTimeoutMs` and forwards it to the spawned Phoenix process.

- [x] **ODD-58-2 — Implement Session Expiry end-to-end scenario**
  - State: Done.
  - Route: inline direct.
  - Allowed edit surfaces: `web/src/integration/stationFlow.test.ts`, `web/src/features/station/hooks/useStation.test.ts`.
  - Acceptance:
    - An expired session returns HTTP 410 with `session_expired` and `"A sessão expirou."`.
    - Result retrieval on an expired session fails (HTTP 410 or 404), ensuring no stale feedback is accessible.
    - Missing session returns HTTP 404 with `session_not_found`.
    - Recovery creates a new active session with a distinct session ID and successful message exchange.
    - Hook transitions cleanly to failed state and resets to idle.

- [x] **ODD-58-3 — Verify test suite and edge cases**
  - State: Done.
  - Checks:
    - `npm --prefix web test` (66 passed)
    - `bash scripts/test.sh` (66 vitest, 157 exunit passed)

- [ ] **ODD-58-4 — Deliver PR and record evidence**
  - State: In progress.
  - Acceptance:
    - PR opened to `feat/31-e2e-integration` with `Refs #58`.

## Verification evidence

- `npm --prefix web test`: passed (7 test files, 66 tests).
- `bash scripts/test.sh`: passed (66 Vitest tests and 157 ExUnit tests).
- `npm --prefix web run typecheck`: passed with zero type errors.
