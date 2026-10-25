# #339 Gate the simulator on an active RevenueCat subscription

Parent: #326. Branch `feat/339-revenuecat-entitlement` from `origin/feat/326-production-launch`. Delivery: one child PR to `feat/326-production-launch` (`Refs #339`). Runner: `cd backend && MIX_TEST_PARTITION=_issue339 mix test`; closure: local CI script.

## Specs

- S1 (issue) "Webhook events activate, renew, expire and cancel entitlements; replays are ignored; bad signatures are rejected".
- S2 (issue) "Session creation returns an explicit error without an active subscription": `POST /sessions` answers `402` with `error: "subscription_required"`.
- S3 (issue) "The web shows plan and renewal date".
- S4 (#339 decision comment) "Pix subscriptions renew as a manual payment each period: the web must show the renewal due date, send a reminder before it, and the entitlement must expire cleanly when an unpaid period lapses. Cards renew automatically."
- S5 (research A7) app_user_id is a random UUIDv4 stored per user, never the email; the Web Purchase Link `https://pay.rev.cat/<token>/<app_user_id>?email=...`; the webhook resolves a user by `app_user_id`, then `original_app_user_id`, then `aliases`.
- S6 (research A8) HMAC `X-RevenueCat-Webhook-Signature: t=<unix>,v1=<hex>` over `"<t>.<raw body>"`, constant-time, 5 min tolerance, plus the `Authorization` header; idempotency on event `id` under a unique index, recorded in the same transaction as the effect; ignore an event older (`event_timestamp_ms`) than the last applied; never move an expiration backwards; unresolved user or failure answers non-200; ignore `SANDBOX` in production.
- S7 (task) Webhook secret, authorization value and purchase-link base URL from env, documented; no real RevenueCat/Stripe calls; fixtures only. Daily quotas are #340 (out of scope).
- Assumption A1: Pix vs card is known from the product (Phoenix-side plan table keyed by `product_id`, research A9 option 1), because the webhook carries no payment method.
- Assumption A2: the account page with the subscription status is a new `/conta` LiveView (the research's success page), because `UserLive.Settings` is outside this issue's edit surface.

## Tasks

| ID | Specs | Route | Status | Commit | RED/GREEN |
| --- | --- | --- | --- | --- | --- |
| T1 | S1 S4 S5 S6 S7 | inline | done | df7a500 | RED 0/24 (module undefined) → GREEN 24/24 |
| T2 | S2 | inline | done | a5397a4 | RED 2 failures (201 instead of 402) → GREEN 36/36 (session, auth, published-session tests) |
| T3 | S3 S4 S5 | inline | done | 2265819 | RED 0/6 (no routes) → GREEN 6/6 |
| T4 | S1 S6 S7 | inline | done | (T4 commit) | RED 0/16 (no route) → GREEN 16/16; log test RED without `log: false` |

- T1 Billing context: migration (`billing_subscriptions`, `billing_webhook_events`), signature verification, idempotent ordered atomic event processing, entitlement query, plan table.
- T2 Session gate: `Stations.start_station_session/2` refuses `:subscription_required` for a learner without an active entitlement; `POST /sessions` answers 402.
- T3 Plan page `/planos` (Web Purchase Links carrying the app_user_id) and account page `/conta` (plan, renewal/due date, Pix vs card, Pix reminder banner, expired state).
- T4 Webhook endpoint `POST /webhooks/revenuecat` (raw body kept for the HMAC), env docs.

## Log

- L1 (2026-10-25, workflow task) Implement #339: Billing context with a signature-verified, idempotent, ordered, atomic RevenueCat webhook storing entitlement + product_id + expiration per user (app_user_id a random UUIDv4); LiveView plan page with the Web Purchase Link; subscription status on the account page; `POST /sessions` refuses with explicit 402 `subscription_required`; env-configured secrets; fixtures only; quotas are #340.
- L2 (2026-10-25) T1–T3 done. Full backend suite: 2210 passed (baseline 2177). Credo strict clean. Docs: `docs/operations/revenuecat.md`.
- L3 (2026-10-25) T4 blocked. The HMAC is computed over the raw request body, but `Plug.Parsers` in `backend/lib/backend_web/endpoint.ex` consumes the body before the router runs. Keeping the raw body needs a `body_reader` option there, and `endpoint.ex` is outside this issue's allowed edit surfaces. Needed decision: approve editing `backend/lib/backend_web/endpoint.ex` (one option on `Plug.Parsers`: `body_reader: {BackendWeb.RevenueCatBodyReader, :read_body, []}`, caching the raw body only for `/webhooks/revenuecat`). The rest of T4 is inside the surfaces: `backend/lib/backend_web/controllers/revenuecat_body_reader.ex`, `revenuecat_webhook_controller.ex`, the route, and `backend/test/backend_web/controllers/revenuecat_webhook_controller_test.exs`.
- L4 (2026-10-25) Parent approved editing `backend/lib/backend_web/endpoint.ex` only to add `body_reader: {BackendWeb.RevenueCatBodyReader, :read_body, []}`, caching the raw body only for the webhook path, capped. Merged `origin/feat/326-production-launch` (#382 usage, #384) cleanly.
- L5 (2026-10-25) T4 done: `POST /webhooks/revenuecat` (`log: false`) verifies via `Billing.verify_webhook/3` over the raw body kept by `RevenueCatBodyReader` (POST on the exact path only, 1 MB cap → 413), then `Billing.process_webhook_event/1`. 200 applied/ignored/duplicate; 401 unauthorized/invalid_signature; 400 invalid_event; 404 unknown_subscriber; 503 webhook_not_configured. Docs: README "Subscription (RevenueCat)", `docs/operations/revenuecat.md` "Webhook endpoint".
