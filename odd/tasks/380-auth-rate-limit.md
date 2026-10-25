# 380 - Rate-limit the public authentication and device-login endpoints

Objective: throttle the public authentication and device-login endpoints per client IP (and per account or email where it applies). Branch `feat/380-auth-rate-limit` from `feat/326-production-launch`; one PR (Refs #380). Test runner: `mix test` in `backend/` (`MIX_TEST_PARTITION=_issue380`).

## Specs

- S1. "Add throttling per client IP (and per account or user code where it applies) on those endpoints": "unauthenticated `POST /device/start`, user-code lookups on the `/device` confirmation page, password login, sign-up, password-reset and magic-link email requests."
- S2. "with an explicit `429` JSON error (`rate_limited`) for API routes and a pt-BR flash for LiveView pages."
- S3. "Limits are configurable through runtime config; counters live in memory (one Phoenix node at launch, ADR-014) without a new dependency unless the research shows one is clearly better."
- S4. "Each endpoint above refuses requests beyond its configured limit with the documented error, and allows them again after the window (tested)."
- S5. "Limits are configurable and documented in the README."
- S6. "Throttled requests log no codes, tokens or emails."
- S7. "Normal use (one learner logging in, one Unreal client polling at the advertised interval) is never throttled (tested)."
- S8. (task constraint) Client IP is `conn.remote_ip`; behind Fly's proxy the real IP is the `Fly-Client-IP` header, read only by a small, explicitly configured trusted-proxy plug that is off by default (never `X-Forwarded-For` blindly).

Constraints: keep the router change minimal (sibling #339 edits it); no billing, stations or session code; `BackendWeb` stays thin and calls only public context modules.

Why: Jorge review of PR #379 (SP-1/SP-2) and #361 follow-ups: a single client can enumerate user codes, flood email sending or brute-force passwords.

## Tasks

| ID | Specs | Route | Status | Commit / evidence |
|---|---|---|---|---|
| T1 | S1 (device start), S2 (API), S3, S4, S6, S8 | inline | done | RED 0/12 (module missing), GREEN 12/12; full backend 2228 passed |
| T2 | S1 (login, sign-up, reset, magic link, `/device` lookup), S2 (flash), S4, S6, S7 | inline | pending | |
| T3 | S5, S7 (README docs, runtime env overrides) | inline | pending | |

Route evidence: one bounded unit per task, written by the parent writer inline; no Writer trigger (no parallel units, no context backstop).

Checks: focused `mix test` per task; final `local_ci.sh` (requires "LOCAL CI PASSED").

## Log

- L1 (2026-10-25, issue #380 body): "Add throttling per client IP (and per account or user code where it applies) on those endpoints, with an explicit `429` JSON error (`rate_limited`) for API routes and a pt-BR flash for LiveView pages. Limits are configurable through runtime config; counters live in memory (one Phoenix node at launch, ADR-014) without a new dependency unless the research shows one is clearly better."
- L2: Design. `BackendWeb.RateLimit` is a fixed-window counter in a public ETS table owned by a GenServer supervised in `Backend.Application`, with a periodic sweep of expired windows. No new dependency: Hammer would add a dependency for the same single-node ETS counter. Buckets are keyed by `{action, kind, key, window}`; emails are hashed (SHA-256) before they become keys, and the throttle log names only the action and the key kind. LiveViews get the client IP through a `live_session` `session` MFA (signed into the LiveView session, never into the cookie), because the endpoint socket has no `peer_data` connect info and `endpoint.ex` is outside this issue's edit surface.
- T1: `BackendWeb.RateLimit` (+ `Backend.Application` child), `BackendWeb.Plugs.RateLimit` on `DeviceController.start` (`429`, `retry-after`, `rate_limited`), `BackendWeb.Plugs.ClientIP` in the `:browser` and `:api` pipelines (off by default), `RATE_LIMIT_*` and `TRUSTED_CLIENT_IP_HEADER` in `config/runtime.exs` (checked with `mix run`: `RATE_LIMIT_LOGIN_IP=3/60` parses, `abc` refuses to boot). Action `login_email` renamed `magic_link_email` so env names stay unambiguous.
- Next step: T2.
