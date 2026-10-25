# RevenueCat billing

How the simulator is gated on a RevenueCat subscription (#339). Research: `docs/research/production-infrastructure.md` §3 (A6–A9).

## What the learner sees

| Page | What it does |
| --- | --- |
| `/planos` | Lists the plans. **Assinar** opens the plan's RevenueCat Web Purchase Link: `<link>/<app_user_id>?email=<email>`. |
| `/conta` | Shows the subscription: plan, payment method, and the card renewal date or the Pix due date. A Pix plan due within 3 days shows a renewal reminder with a **Renovar com Pix** link. Cancelled and expired subscriptions are shown as such. |
| `POST /sessions` | Without an active entitlement it answers `402` with `{"error": "subscription_required", "message": "Assine um plano para usar o simulador."}`. |

Payments run through the RevenueCat **Stripe Billing** integration, so learners can pay by card or Pix:

- **Card** plans renew automatically.
- **Pix** plans renew manually. Pix Automático is not available to Brazil-domiciled businesses, so each period is a separate Pix payment. Access ends cleanly at the due date when the next period is unpaid: no `EXPIRATION` event is needed.

## Identity

Each learner gets a random UUIDv4 `app_user_id` the first time it is needed (table `billing_subscriptions`). It is never the email or the database id. Every purchase link carries it.

## Configuration

| Variable | Meaning |
| --- | --- |
| `REVENUECAT_CARD_PURCHASE_LINK` | Web Purchase Link of the card plan, `https://pay.rev.cat/<token>`, without the app_user_id. |
| `REVENUECAT_PIX_PURCHASE_LINK` | Web Purchase Link of the Pix plan. |
| `REVENUECAT_WEBHOOK_AUTHORIZATION` | The `Authorization` header value set on the webhook in the RevenueCat dashboard. |
| `REVENUECAT_WEBHOOK_SECRET` | The webhook HMAC signing secret. RevenueCat shows it only once. |
| `REVENUECAT_ACCEPT_SANDBOX` | `true` lets production accept `SANDBOX` events. Development always accepts them. |

- Without a purchase link, its plan shows "Compra indisponível no momento."
- Without both webhook secrets, the webhook rejects every request (fail closed).
- Plans live in `config/config.exs` under `Backend.Billing`, keyed by RevenueCat `product_id`: `revalida_mensal_cartao` (card) and `revalida_mensal_pix` (Pix). The webhook carries no plan metadata or payment method, so the plan table decides both. The entitlement identifier is `simulador`.
- Set the custom success page of each Web Purchase Link to `<host>/conta`.

## Webhook processing

`Backend.Billing.verify_webhook/3` and `Backend.Billing.process_webhook_event/1`:

1. **Authentication.** The `Authorization` header must match. `X-RevenueCat-Webhook-Signature: t=<unix>,v1=<hex>` must be the HMAC-SHA256 of `"<t>.<raw body>"`, with `t` within 5 minutes. Both comparisons are constant time.
2. **Idempotency.** The event `id` is inserted under a unique index in the same transaction as its effect. A redelivery is a no-op. A failed effect leaves no id, so RevenueCat's retry still applies.
3. **User lookup.** By `app_user_id`, then `original_app_user_id`, then `aliases`. If no learner resolves, the transaction rolls back and the endpoint must answer non-200 so RevenueCat retries.
4. **Ordering.** An event whose `event_timestamp_ms` is older than the last applied one is ignored. An expiration never moves backwards.
5. **Effects.**

   | Event | Effect |
   | --- | --- |
   | `INITIAL_PURCHASE`, `RENEWAL`, `UNCANCELLATION`, `PRODUCT_CHANGE`, `SUBSCRIPTION_EXTENDED`, `NON_RENEWING_PURCHASE` | Grant the entitlement. |
   | `CANCELLATION` | Keep access until the expiration. |
   | `EXPIRATION` | End access. |
   | `TEST`, events for another entitlement, and other types (`BILLING_ISSUE`, `TRANSFER`, …) | Recorded, no effect. |

## Webhook endpoint

Set the webhook URL in the RevenueCat dashboard to `https://<host>/webhooks/revenuecat`, with the `Authorization` header value of `REVENUECAT_WEBHOOK_AUTHORIZATION` and the signing secret of `REVENUECAT_WEBHOOK_SECRET`.

`BackendWeb.RevenueCatWebhookController` answers:

| Status | `error` | When |
| --- | --- | --- |
| `200` | | The event was committed: `status` is `applied`, `ignored` or `duplicate`. |
| `400` | `invalid_event` | The body has no event `id` and `type`. |
| `401` | `unauthorized` | The `Authorization` header does not match. |
| `401` | `invalid_signature` | The signature is missing, malformed, stale (more than 5 minutes) or does not match the raw body. |
| `404` | `unknown_subscriber` | No learner resolves; nothing is recorded, so RevenueCat's retry still applies. |
| `413` | | The body is over 1 MB. |
| `503` | `webhook_not_configured` | `REVENUECAT_WEBHOOK_AUTHORIZATION` or `REVENUECAT_WEBHOOK_SECRET` is unset. |

The HMAC needs the exact bytes RevenueCat signed. `BackendWeb.RevenueCatBodyReader`, the `body_reader` of `Plug.Parsers` in `BackendWeb.Endpoint`, keeps the raw body for `POST /webhooks/revenuecat` only, capped at 1 MB; every other request keeps no raw copy. The route sets `log: false`, so neither the payload nor the headers reach the logs.

## Open

- Reconciling against `GET /subscribers` for events lost after RevenueCat stops retrying (about 80 minutes).
- Email reminder before a Pix due date. Today the reminder is shown only on `/conta`.
- `TRANSFER` handling.
- Daily quotas per plan (#340).
