# 388 Refund access cut

Objective: a refund or chargeback ends simulator access at the event time (#388, parent #326). Branch `feat/388-refund-access-cut` from `feat/326-production-launch`; one child PR (`Refs #388`). Test runner: `mix test` in `backend/` (`MIX_TEST_PARTITION=_issue388`), local CI script.

## Specs

- **S1** "A refund or chargeback event ends access at the event time, even when it carries an earlier expiration than the stored one (tested with fixture payloads)." New sessions are refused with 402 `subscription_required`; "A session already in progress may finish."
- **S2** "A plain cancellation (no refund) keeps access until the stored expiration (tested)."
- **S3** "Out-of-order and duplicate events keep today's protections for non-refund events (existing tests stay green)." Refund/chargeback is the only exception to the never-move-expiration-backwards rule.
- **S4** "`/conta` shows that access ended because of a refund (pt-BR copy)."
- **S5** "docs/operations/revenuecat.md documents the rule and the RevenueCat fields it reads, with source links." Include the Brazil context: Consumer Defense Code art. 49 (7-day withdrawal), card chargebacks and Pix MED reversals.
- **S6** Out of scope (decision comment 2026-10-25): "no in-app refund request button".

Refund signal (verified against RevenueCat docs, 2026-10-25): `CANCELLATION` (or `EXPIRATION`) whose `cancel_reason` (or `expiration_reason`) is `CUSTOMER_SUPPORT`, or whose `price` is negative. RevenueCat documents no separate dispute/chargeback event; `REFUND_REVERSED` is App Store only and is not handled.

## Tasks

| ID | Specs | Route | Status | Commit / evidence |
| --- | --- | --- | --- | --- |
| T1 | S1, S2, S3, S5 | inline (no writer reason: one behavior) | done | see Log L3 |
| T2 | S4 | inline | done | see Log L4 |

## Log

- **L1** (2026-10-25, issue #388) "Make refunds and chargebacks the only exception to that rule: when the webhook event signals a refund or a chargeback / reversal (RevenueCat `CANCELLATION` with a refund cancel reason, or the refund/reversal event types RevenueCat documents — verify the exact field values in the RevenueCat webhook docs and cite them), the entitlement ends at the event time and new sessions are refused with 402 `subscription_required`. The ordering, idempotency and never-move-backwards protections stay for every other event. A session already in progress may finish."
- **L2** Design: a new nullable `billing_subscriptions.refunded_at` records the refund event time. A refund sets `status: :expired`, `expires_at` and `refunded_at` to the event time. Event-time ordering (`event_timestamp_ms`) and event-id idempotency still apply to refunds; only the expiration may move backwards. A later non-refund `CANCELLATION` does not reopen a refunded subscription; a later granting event (a new purchase) clears `refunded_at`.
- **L3** T1 RED: `billing_test.exs` 31/37 (6 new refund tests failing); controller refund test against base code 16/17. GREEN: billing + controller tests 54/54. Refund rule in `Backend.Billing.WebhookEvents`, migration `20261025180000` adds `refunded_at`, `subscription_status/1` adds `refunded?`, docs section "Refunds and chargebacks". Sources: RevenueCat event types and fields, RevenueCat refunds (accessed 2026-10-25).
- **L4** T2 RED: `billing_live_test.exs` 9/10 (refund copy missing). GREEN: 10/10. `/conta` shows "Acesso encerrado em <data> por reembolso ou estorno do pagamento." with **Assinar novamente**; no daily quota card.
- **L5** Verification: local CI (`local_ci.sh`) LOCAL CI PASSED: web unit 337, ExUnit 2338 passed, E2E 4, Dialyzer 0 errors, format, warnings-as-errors, Credo. Live check on PORT=4151 against a scratch database: a signed fixture `INITIAL_PURCHASE` then a signed `CANCELLATION` (`cancel_reason` `CUSTOMER_SUPPORT`, `price` -99.9) both answered 200 `applied`; `/conta` showed "Acesso encerrado em 25/10/2026 por reembolso ou estorno do pagamento." with **Assinar novamente** (screenshot attached to the PR notes). GitHub Actions is blocked by billing. Next step: review of the child PR into `feat/326-production-launch`.
