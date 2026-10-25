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
| T1 | S1, S4, S6 | inline | pending | Accounts: `device_authorizations` + `device_tokens` tables (hashes only), start/approve/deny/poll, access + rotating refresh, revoke on password change/reset, logout, logout-everywhere; deletion cascades |
| T2 | S1, S5, S6, S7 | inline | pending | Web: `POST /device/start`, `/device/token`, `/device/refresh`, `/device/logout`, LiveView `/device` confirmation page, admins refused, code params filtered from logs |
| T3 | S3, S7 | inline | pending | Bearer plug on `/stations`, `/pre-station-notice`, `/sessions*`; sessions carry `user_id`, another learner's session is 404; deprecated routes unauthenticated only in dev/test |
| T4 | S2 | inline | pending | `docs/unreal-station-client.md`: start/poll/refresh/logout with curl |

Routing: inline for all tasks (no Writer trigger reason: one sequential feature, each unit depends on T1).

## Log

- **L1** (2026-10-25, parent orchestrator task for issue #337, verbatim excerpt): "Build an OAuth-2.0-device-authorization-style flow (RFC 8628 shape): POST /device/start returns device_code + short user_code + verification_uri + interval + expires_in; the learner opens the LiveView page, logs in and confirms the user_code; POST /device/token (poll) returns authorization_pending / slow_down / expired_token / access_denied or the tokens. Short-lived access token (e.g. 15 min) + rotating refresh token; store only hashes; revoke all on password change, logout-everywhere and account deletion (hook into #336's deletion). Tokens and codes must never be logged (scrub params in the endpoint/Logger filter). POST /sessions and every /sessions/:id/... route require a valid bearer token and tie the session to the learner (sessions of another learner are 404); GET /stations and GET /pre-station-notice also require the token. Keep the deprecated /api/stations/active/... routes unauthenticated only in dev/test for the frozen web harness and E2E (they already 404 in prod). Admin accounts may not use the device flow. Document start/poll/refresh/logout in docs/unreal-station-client.md with curl examples. Do not touch the voice worker or patient generation (sibling #341 owns them)."
- **L2** Baseline: `mix test` 2091 passed at `f8bce87`.
