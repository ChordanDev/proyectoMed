# 337 — Log the Unreal client in through the browser

Issue: #337 (parent spec #326). Branch: `feat/337-unreal-device-login` → PR base `feat/326-production-launch`. Delivery strategy: `single-pr`. Test runner: `(cd backend && MIX_TEST_PARTITION=_issue337 mix test)`; full gate: `local_ci.sh <worktree>`.

Why: the Unreal client must act for a learner account (#336) so sessions, results and billing belong to someone. A browser device login (RFC 8628 shape) avoids typing passwords into the game.

## Specs

- **S1** (Issue #337 verbatim): "A device-login flow: Unreal starts a login, the learner completes it in the browser, and Unreal receives a short-lived access token plus a refresh token. Tokens are revocable (password change, logout, account deletion) and never logged. Session API endpoints require a valid token and tie sessions to the learner."
- **S2** (AC verbatim): "Start/poll/refresh/logout endpoints are documented for the Unreal owner"
- **S3** (AC verbatim): "Session endpoints reject missing, expired and revoked tokens"
- **S4** (AC verbatim): "Changing the password or deleting the account revokes all tokens"
- **S5** (AC verbatim): "No token appears in logs"
- **S6** (parent orchestrator constraints, verbatim excerpt): "POST /device/start returns device_code + short user_code + verification_uri + interval + expires_in; the learner opens the LiveView page, logs in and confirms the user_code; POST /device/token (poll) returns authorization_pending / slow_down / expired_token / access_denied or the tokens. Short-lived access token (e.g. 15 min) + rotating refresh token; store only hashes; revoke all on password change, logout-everywhere and account deletion"
- **S7** (parent orchestrator constraints, verbatim excerpt): "POST /sessions and every /sessions/:id/... route require a valid bearer token and tie the session to the learner (sessions of another learner are 404); GET /stations and GET /pre-station-notice also require the token. Keep the deprecated /api/stations/active/... routes unauthenticated only in dev/test for the frozen web harness and E2E (they already 404 in prod). Admin accounts may not use the device flow."
- **S8** (invariants, AGENTS.md): `Accounts` calls no other context; `Stations` may call `Accounts`; `BackendWeb` stays thin and calls only public context modules. Voice worker and patient generation are out of scope (sibling #341).

## Tasks

| ID | Specs | Route | Status | Evidence |
| --- | --- | --- | --- | --- |
| T1 | S1, S4, S6 | inline | done | `fa99e07` — `Backend.Accounts.DeviceLogin`: `device_authorizations` + `device_tokens` (SHA-256 hashes only), start/approve/deny/poll with RFC 8628 errors, 15-min access + rotating 30-day refresh with reuse detection, revoke one/all; password change/reset revoke all; deletion cascades. RED 0/21 (undefined functions) → GREEN 21/21 `device_login_test.exs`; accounts suites 100/100 |
| T2 | S1, S5, S6, S7 | inline | done | `214b995` — `POST /device/start|token|refresh|logout` (`DeviceController`), `BackendWeb.Plugs.DeviceAuth`, `/device` LiveView (admins refused), `"code"` added to `filter_parameters`. RED 0/17 (no routes) → GREEN 17/17; the logging test fails 0/1 with `"code"` removed from the filter (checked) |
| T3 | S3, S7 | inline | done | `ff36526` — `:learner_api` pipeline (DeviceAuth + `SessionOwner`) on `/stations`, `/pre-station-notice`, `/sessions*`; sessions carry `user_id`; `LegacyStationAuth` keeps `/api/stations` and `/api/v2/stations` open only where `:legacy_station_api_unauthenticated` (dev/test). RED 7/9 (`session_auth_test.exs`; the two passing tests pin catalog/legacy behavior) → GREEN 9/9; existing session/station controller tests updated with `register_and_log_in_device` (18 failed before) |
| T4 | S2 | inline | done | `57e3e6e` — `docs/unreal-station-client.md`: device login section with curl for start/poll/refresh/logout, 401 codes, deprecated routes in production |

Routing: inline for all tasks (no Writer trigger reason: one sequential feature, each unit depends on T1).

## Log

- **L1** (2026-10-25, parent orchestrator task for issue #337, verbatim excerpt): "Build an OAuth-2.0-device-authorization-style flow (RFC 8628 shape): POST /device/start returns device_code + short user_code + verification_uri + interval + expires_in; the learner opens the LiveView page, logs in and confirms the user_code; POST /device/token (poll) returns authorization_pending / slow_down / expired_token / access_denied or the tokens. Short-lived access token (e.g. 15 min) + rotating refresh token; store only hashes; revoke all on password change, logout-everywhere and account deletion (hook into #336's deletion). Tokens and codes must never be logged (scrub params in the endpoint/Logger filter). POST /sessions and every /sessions/:id/... route require a valid bearer token and tie the session to the learner (sessions of another learner are 404); GET /stations and GET /pre-station-notice also require the token. Keep the deprecated /api/stations/active/... routes unauthenticated only in dev/test for the frozen web harness and E2E (they already 404 in prod). Admin accounts may not use the device flow. Document start/poll/refresh/logout in docs/unreal-station-client.md with curl examples. Do not touch the voice worker or patient generation (sibling #341 owns them)."
- **L2** Baseline: `mix test` 2091 passed at `f8bce87`.
- **L3** Outside the declared edit surface: `backend/lib/backend/stations/conversation.ex` gained `:user_id` in `@pinned_station_keys` (one line plus the type) — the session store only keeps listed keys, so tying a session to its learner needs it. No other Conversation behavior changed.
- **L4** Verification: full `mix test` 2138 passed (baseline 2091 + 47 new). Local CI run 3: LOCAL CI PASSED (web 337, ExUnit 2138, E2E 4, credo, dialyzer 0 errors). Runs 1 and 2 hit timing/sequence flakes: run 1, 4 Conversation grace-timing tests while the machine was busy (102/102 three times in isolation); run 2, `content_test` / `admin_case_live_test` sequential-number assertions racing as async tests on the shared `cases` sequence (an existing issue: none of the new async tests insert cases). Screenshot on PORT=4141 pending: the headless Chromium download never wrote its executable on this machine (the existing Playwright cache has the same truncated install). The server, the isolated `backend_dev_issue337` database and the seeded learner did work.
- **Next:** `UStationClient` methods for the device login and the bearer header (Unreal track); a "log out everywhere" button on the web settings page if wanted.

