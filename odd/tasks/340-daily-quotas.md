# #340 Enforce daily simulation quotas per plan

Parent: #326. Branch `feat/340-daily-quotas` from `origin/feat/326-production-launch`. Delivery: one child PR to `feat/326-production-launch` (`Refs #340`). Runner: `cd backend && MIX_TEST_PARTITION=_issue340 mix test`; closure: local CI script.

## Specs

- S1 (issue) "Quota comes from plan metadata without a deploy". Research #328 A9: RevenueCat webhooks carry no plan metadata, so the daily quota lives in a Phoenix table keyed by RevenueCat `product_id` (seeded by the migration, admin-editable later); an unknown product gets a safe default from config, documented.
- S2 (issue) "The N+1th session in a day is refused with an explicit error": `POST /sessions` past the quota returns `429` `daily_quota_exhausted` with the reset time.
- S3 (issue) "Failed sessions do not consume quota": only sessions that reached a graded result count (the learner's `educational_results` since local midnight in `America/Sao_Paulo`, day boundary documented); a technical failure never consumes quota.
- S4 (issue) "Remaining count is shown on the web": `/conta` shows today's remaining simulations.
- S5 (task) Race: two sessions started at the same moment at quota-1. Define and test the behaviour (count started-and-not-failed sessions or reserve on start) and justify the choice in docs.
- S6 (task) Document the error in `docs/unreal-station-client.md`. Screenshot on PORT=4149 of `/conta` showing remaining simulations.
- Assumption A1: `America/Sao_Paulo` has had no daylight saving time since 2019, so the day boundary is a fixed UTC−03:00 offset (midnight local = 03:00 UTC) and no time zone database dependency is added.
- Assumption A2 (S5 choice): reserve on start. A start takes a per-learner Postgres advisory lock and counts graded results today plus in-flight reservations; a reservation holds a slot until the session is graded (then the result counts) or until the session's expiry (abandoned or technically failed sessions release it). The second concurrent start at quota-1 is refused.

## Tasks

| ID | Specs | Route | Status | Commit | RED/GREEN |
| --- | --- | --- | --- | --- | --- |
| T1 | S1 S3 | inline | done | f060f89 | RED 24/31 (7 failures, functions undefined) → GREEN 31/31 |
| T2 | S2 S3 S5 S6 | inline | done | 1ca4e21 | RED 1/10 quota tests (module undefined) and 19/20 controller (WithClauseError) → GREEN 10/10 and 20/20; race test fails 0/1 with the advisory lock removed |
| T3 | S4 S6 | inline | done | 4fae63a | RED 7/9 (2 failures, no `#daily-quota`) → GREEN 9/9 |

- T1 Billing: `billing_plan_quotas` table (seeded per product), `Billing.daily_quota/1` with the configured default for an unknown product, `Billing.quota_day/1` (the America/Sao_Paulo day window and reset time); docs in `docs/operations/revenuecat.md`.
- T2 Stations: quota reservations, the gate in `start_station_session/2` (`{:error, {:daily_quota_exhausted, resets_at}}`), `daily_quota_status/1`; `POST /sessions` answers 429 with `resets_at` and `Retry-After`; race test; docs in `docs/unreal-station-client.md`.
- T3 `/conta` shows today's remaining simulations and the reset time.

Route evidence: no writer trigger (one behaviour chain, each task under ~400 lines), so every task runs inline.

## Log

- L1 (2026-10-25, workflow task) Implement #340: daily quota per product_id (unknown product → a safe default from config, documented); count only sessions that reached a graded result (use educational_results for the learner since local midnight in America/Sao_Paulo — document the day boundary); a technical failure never consumes quota; POST /sessions past the quota returns 429 `daily_quota_exhausted` with the reset time; /conta shows today's remaining simulations. Race: two sessions started at the same moment at quota-1 — define and test the behaviour (count started-and-not-failed sessions or reserve on start; justify the choice in docs). Document the error in docs/unreal-station-client.md. Local Postgres; MIX_TEST_PARTITION=_issue340. Screenshot on PORT=4149: /conta showing remaining simulations.
- L2 (2026-10-25) T1–T3 done. Quota table `billing_plan_quotas` (seeded 10 per plan, default 3); reservations in `session_quota_reservations` under a per-learner advisory lock; `POST /sessions` 429 with `resets_at` and `Retry-After`; `/conta` "N de M simulações restantes hoje". Full backend suite 2284 passed; Credo strict clean. Docs: `docs/operations/revenuecat.md` (Daily quotas), `docs/unreal-station-client.md` (Daily quota), README.
- L3 (2026-10-25) Screenshot of `/conta` ("7 de 10 simulações restantes hoje") on an isolated dev DB (`backend_dev_issue340`) on PORT=4149, seeded with one card learner and three in-flight reservations; Playwright's Chromium was unavailable, so a WKWebView snapshot was used; server stopped and DB dropped.
- L4 (2026-10-25) Local CI (`MIX_TEST_PARTITION=_issue340`): LOCAL CI PASSED — web unit 337 passed, ExUnit 2287 passed, E2E 4 passed, Credo strict clean. GitHub Actions is blocked by billing.
