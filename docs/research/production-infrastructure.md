# Production infrastructure and billing research

Issue #328, parent spec #326. All sources accessed on **2026-10-21**, unless noted otherwise.

This report checks the assumptions that spec #326 marks as unverified. Each one gets a verdict:

- **Confirmed**: primary documentation supports the assumption as written.
- **Changed**: the documentation contradicts the assumption or adds a constraint that changes the plan. A recommended alternative follows.
- **Unverified**: no primary source settles it. It needs a live measurement, a support ticket or a sales answer.

Method: read-only reading of official documentation and pricing pages. No accounts were created, nobody signed in and no paid API was called. Community forum answers are labelled as such and never count as confirmation.

## Summary of verdicts

| # | Spec assumption | Verdict |
|---|---|---|
| A1 | Phoenix on Fly.io in São Paulo | Confirmed (`gru`) |
| A2 | One Phoenix node is enough at launch | Confirmed, with sizing below |
| A3 | Deploy drain: the old node finishes running sessions, with Fly request replay | **Changed**: Fly stops a Machine at most 300 s after the stop signal, and a station lasts 10 min |
| A4 | Postgres on Neon in a region near São Paulo | Confirmed (`aws-sa-east-1`, São Paulo) |
| A5 | Phoenix connects to Neon from Fly without special setup | Confirmed, with pooling and TLS notes |
| A6 | RevenueCat Web Billing for web subscriptions | Confirmed, but Pix is not available through RevenueCat Billing |
| A7 | Web Purchase Link or purchases-js, to verify | Confirmed: both work with our own user id. Recommend the Web Purchase Link |
| A8 | Webhook is signature-verified and idempotent | Confirmed (optional HMAC-SHA256 signature plus event `id`) |
| A9 | Daily quota per plan comes from RevenueCat plan metadata | **Changed**: webhooks carry no plan metadata |
| A10 | LiveKit Cloud has a region near Brazil | Confirmed for media. **Changed** for hosted agents: no South American agent region |
| A11 | LiveKit Cloud plan for ~200 concurrent sessions | Depends on where the voice workers run (see the LiveKit section) |
| A12 | Anthropic limits allow ~200 simultaneous sessions | **Changed**: the binding limit is the monthly spend cap, not RPM |
| A13 | Deepgram limits allow ~200 simultaneous sessions | **Changed**: Pay As You Go allows 150 concurrent streams. Growth or Enterprise is needed |
| A14 | ElevenLabs limits allow ~200 simultaneous sessions | Confirmed with conditions: WebSocket streaming and a Scale or higher plan |

## 1. Fly.io (Phoenix)

### Findings

- **The São Paulo region exists.** Its code is `gru`. It is one of 17 regions and can host Fly Managed Postgres. Unlike most regions, it has **no WireGuard gateway**. That affects `fly ssh`/`fly proxy` latency from Brazil, not production traffic. Source: <https://docs.fly.io/reference/regions>.
- **Region pricing.** The price of a region is the Ashburn price times a multiplier. For `gru` the multiplier is 1.615: shared-cpu-1x costs $3.54/month and performance-1x (1 vCPU, 2 GB) costs $53.31/month. Ashburn reference prices are $33.00 for performance-1x (2 GB) and $66.00 for performance-2x (4 GB). Source: <https://fly.io/pricing>.
- **Shared CPUs throttle under sustained load.** A shared vCPU has a baseline of 5 ms per 80 ms period (6.25%). It can burst to 100% from a balance that starts at 5 s and grows to at most 500 s. When the balance runs out, the vCPU falls back to its baseline. A performance vCPU can use 100% all the time. Source: <https://docs.fly.io/machines/cpu-performance>.
- **Memory limits.** Shared CPUs take 256 MB to 2 GB per vCPU. Performance CPUs take 2 GB to 8 GB per vCPU. Resizing replaces the VM but keeps the Machine ID. Source: <https://docs.fly.io/machines/guides-examples/machine-sizing>.
- **Deploy strategies.** Fly offers `rolling` (the default), `immediate`, `canary` and `bluegreen`. Bluegreen boots a new Machine next to each old one and moves traffic once health checks pass. It needs at least one health check and does not work with volumes. Source: <https://docs.fly.io/reference/configuration>.
- **Stop timeout.** `kill_timeout` defaults to 5 s, can be set to at most 300 s, and is best-effort. The default stop signal is `SIGINT`. Source: <https://docs.fly.io/reference/configuration>.
- **Request replay.** A response with `fly-replay: instance=<machine-id>` makes the Fly proxy replay the request to that Machine. `prefer_instance` is the soft form. The limits are:
  - requests over 1 MB cannot be replayed;
  - an app that replays must not negotiate the WebSocket upgrade itself;
  - with `fallback=force_self`, a replay to a Machine that is gone returns a proxy error.
  The page says nothing about deploys. Source: <https://docs.fly.io/networking/dynamic-request-routing>.

### Verdicts

- **A1 Confirmed.** Use `primary_region = "gru"`.
- **A2 Confirmed, with sizing.** A single Phoenix node holds about 200 conversation processes. It spends most of its time waiting on LLM HTTP calls, but TLS, JSON and LiveView sockets keep it busy more steadily than the bursty profile shared CPUs are built for. Start with **performance-1x (2 GB)** in `gru`, about $53/month. Watch `fly_instance_cpu_throttle` and move to performance-2x if needed. The size is a recommendation: the 200-session load has not been measured.
- **A3 Changed.** The spec wants the old node to "finish running sessions". A station lasts 10 minutes, plus grading. Fly stops a Machine at most 300 s after the signal, so a normal `fly deploy` (rolling or bluegreen) can cut a live station. Alternatives:
  1. **Recommended: a drain gate before deploying.** An admin action or release task tells Phoenix to stop accepting new sessions, which reuses the concurrent-session cap from user story 56. The deploy runs once the active-session count reaches 0, at most about 12 min later. It is simple, needs no Fly-specific machinery and fits a single node. The cost is a short window with no new sessions at each deploy.
  2. **App-level blue/green.** Start the new release on new Machines (for example with `fly machine clone`/`run` instead of `fly deploy`). Point new sessions to them, and keep replaying requests for old sessions to the old Machine with `fly-replay: instance=<old id>`. The old Machine exits by itself when it is empty. This matches the spec's intent but needs custom deploy scripting and a spike. Unverified end to end.
  3. **Persist conversation state** so that any node can resume a session. This is the most robust option and the biggest change. It is out of scope for launch, because the spec rules out multi-node clustering.

## 2. Neon (Postgres)

### Findings

- **There is a São Paulo region.** It is `aws-sa-east-1`, AWS South America (São Paulo), and Postgres is available there. The Azure regions are deprecated for new projects. Source: <https://neon.com/docs/introduction/regions>.
- **Pooling.** The pooled endpoint runs PgBouncer in transaction mode and accepts up to 10,000 client connections. Each pool takes 90% of `max_connections`; for example, 1 CU has 419 connections, so its pool allows 377. A query waits at most 120 s for a pooled connection. In transaction mode, `SET`, `LISTEN`/`NOTIFY`, session advisory locks and SQL-level `PREPARE` do not work. Protocol-level prepared statements work. Neon recommends direct connections for migrations and `pg_dump`. Source: <https://neon.com/docs/connect/connection-pooling>.
- **Scale to zero.** Compute suspends after 5 minutes idle and resumes "within a few hundred milliseconds". It cannot be turned off on the Free plan; paid plans can turn it off. Source: <https://neon.com/docs/introduction/scale-to-zero>.
- **Ecto guide.** An official Ecto guide exists: <https://neon.com/docs/guides/elixir-ecto>. A community forum post reports two things: Neon needs TLS (`ssl: true` with peer verification), and `ECTO_IPV6=true`, which the Fly-generated Dockerfile sets, broke the connection. That post is not official guidance. Source: <https://community.neon.tech/t/guide-on-connecting-via-ecto/75>.

### Verdicts

- **A4 Confirmed.** Create the project in `aws-sa-east-1`, in the same metro as Fly `gru`. The round-trip latency between Fly `gru` and AWS `sa-east-1` has not been measured. Measure it with `SELECT 1` from a Fly Machine before launch.
- **A5 Confirmed, with notes.**
  - The Ecto Repo should use the **direct** endpoint and a small `pool_size`. Phoenix is a long-lived, pooled client. It does not open a connection per request, so PgBouncer adds nothing at our scale, and the direct endpoint keeps advisory locks and `LISTEN`/`NOTIFY` (Oban, PubSub adapters) working. Use the pooled endpoint only if connection counts grow.
  - Run migrations on the direct endpoint.
  - Use a paid plan and **turn off scale to zero** in production, so that the first query after an idle period does not pay a cold start. Usage-based price details were not checked.
  - Check `ECTO_IPV6` and the TLS settings during the first deploy.

## 3. RevenueCat (web billing)

### Findings

- **RevenueCat Billing (Web Billing) uses Stripe as its payment gateway.** You connect an existing Stripe account or start from a claimable sandbox that cannot take real payments until it is claimed. Products, prices, trials and transactional emails are configured in RevenueCat. It includes a customer portal for managing subscriptions. Customers based in India are not supported. Source: <https://www.revenuecat.com/docs/web/web-billing/configuring-overview.md>.
- **Payment methods are cards, Apple Pay and Google Pay only.** Pix and boleto are not listed. Source: <https://www.revenuecat.com/docs/web/web-billing/payment-methods>.
- **BRL is supported**, with a minimum price of R$4.99 and one price per currency per product. Source: <https://www.revenuecat.com/docs/web/web-billing/multi-currency-support>.
- **The Stripe Billing integration is the alternative.** Since 2026-04-17, RevenueCat web flows (Web SDK, Web Purchase Links, Web Paywalls, Funnels) can sell Stripe Billing products, including Stripe Managed Payments. Managed Payments is Stripe's merchant-of-record product and is **not** available through RevenueCat Billing. With Stripe Billing, Stripe runs checkout, the customer portal and the emails. Sources: <https://www.revenuecat.com/release/sell-stripe-billing-products-in-web-purchase-flows-2026-04-17>, <https://www.revenuecat.com/docs/web/integrations/stripe.md>, <https://www.revenuecat.com/docs/web/integrations/stripe/stripe-managed-payments.md>.
- **Pix on Stripe** (relevant only on the Stripe Billing path):
  - Pix supports recurring payments through Pix Automático, but **Pix Automático is not available to businesses domiciled in Brazil**. Brazilian accounts can only take one-time Pix payments.
  - MCC 8099 (Medical Services) is prohibited for Pix, and "telehealth or medicine vendors" are not allowed. An exam-preparation product would normally fall under an education MCC, but this has not been confirmed with Stripe.
  - Source: <https://docs.stripe.com/payments/pix>.
- **Web Purchase Links.** The URL takes the form `https://pay.rev.cat/<token>/<appUserId>`. For identified users the App User ID must be appended, or the page returns 404. A custom success page receives `app_user_id` as a URL parameter, and the `email` parameter pre-fills the email. Anonymous links rely on Redemption Links. Source: <https://www.revenuecat.com/docs/web/web-billing/web-purchase-links>.
- **purchases-js** (`@revenuecat/purchases-js`). Configure it once with the public Web Billing key and an `appUserId`. `purchase({rcPackage, htmlTarget, customerEmail})` renders checkout into an element, and `getCustomerInfo()` exposes `entitlements.active`. Source: <https://www.revenuecat.com/docs/web/web-billing/web-sdk>.
- **App User ID rules.** Unique per user, case-sensitive, at most 100 characters, no `/`, and not guessable. RevenueCat recommends a random UUIDv4 and advises against email addresses. Values such as `anonymous`, `null` and `0` are blocked. Source: <https://www.revenuecat.com/docs/customers/identifying-customers>.
- **Webhook authentication.**
  - An optional `Authorization` header value is set in the dashboard.
  - Optional HMAC signing adds `X-RevenueCat-Webhook-Signature: t=<unix>,v1=<hex>`, an HMAC-SHA256 over the timestamp and the raw body. It should be compared in constant time against a tolerance window, for example 5 min.
  - A non-200 response, or no response within 60 s, counts as a failure. RevenueCat retries up to 5 times with backoff over about 80 min, then stops.
  - Delivery is at least once. A retry reuses the event `id`, so idempotency is keyed on `id`.
  - Source: <https://www.revenuecat.com/docs/integrations/webhooks>.
- **Webhook events and fields.** Relevant events: `INITIAL_PURCHASE`, `RENEWAL`, `CANCELLATION`, `UNCANCELLATION`, `EXPIRATION`, `BILLING_ISSUE`, `PRODUCT_CHANGE`, `SUBSCRIPTION_EXTENDED`, `TRANSFER`, `TEST`. Every event carries `app_user_id`, `original_app_user_id`, `aliases`, `entitlement_ids`, `product_id`, `expiration_at_ms` and `environment` (`SANDBOX`/`PRODUCTION`). `store` is `RC_BILLING` for RevenueCat Billing and `STRIPE` for Stripe Billing. Source: <https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields>.
- **Offering metadata.** It is a JSON object of up to 4000 characters attached to an **Offering**, the paywall entity. The documentation only describes reading it through the SDKs. It says nothing about webhooks or the REST API. Source: <https://www.revenuecat.com/docs/tools/offering-metadata>.
- **Pricing.** RevenueCat is free up to $2,500 monthly tracked revenue and 1% of tracked revenue after that. The pricing page lists "Integrated RevenueCat Billing" with no separate fee. Stripe processing fees come on top. Whether RevenueCat Billing has its own fee is **unverified**: it is not stated on the page. Source: <https://www.revenuecat.com/pricing>.

### Verdicts

- **A6 Confirmed, with one decision.** RevenueCat Billing works with BRL prices, but **only cards and wallets**. If Pix matters for Brazilian conversion, use the **Stripe Billing integration** through the same RevenueCat flows. Pix Automático is unavailable to a Brazilian entity, though, so Brazil-domiciled recurring Pix still does not work. This is open question Q1.
- **A7 Confirmed. Recommend the Web Purchase Link.** Phoenix LiveView renders a link to `https://pay.rev.cat/<token>/<user.revenuecat_id>?email=...` and sets the custom success page back to `/conta`. No JavaScript SDK or LiveView hook is needed. Use purchases-js only if the checkout must be embedded in our own page.
  - App User ID mapping: store a random UUIDv4 `revenuecat_id` per user, never the email or the sequential primary key, and use it in every link.
  - The webhook handler resolves a user by `app_user_id`, then `original_app_user_id`, then `aliases`.
- **A8 Confirmed.**
  - Turn on HMAC signing and also set the `Authorization` header.
  - Verify the signature over the raw body. Phoenix must keep the raw body for this route, for example with a custom `body_reader`.
  - Reject timestamps older than 5 minutes.
  - Insert the event `id` under a unique index for idempotency.
  - Return 200 quickly, well under 60 s.
  - Ignore `environment = SANDBOX` in production.
- **A9 Changed.** Webhooks carry `product_id` and `entitlement_ids`, not plan metadata. Offering metadata belongs to the paywall and is documented only for the SDKs. Alternatives:
  1. **Recommended:** a Phoenix-side plan table keyed by RevenueCat `product_id`, for example `{"revalida_basic_monthly": 3, "revalida_pro_monthly": 10}`, held in runtime config or a database table that admins can edit. Changing a quota then needs no deploy if it lives in the database. This keeps quotas out of RevenueCat, which is a change to user story 55.
  2. One entitlement per tier, with the quota keyed by entitlement id. This is coarser and has the same need for a Phoenix-side mapping.
  3. Fetch offering metadata through the RevenueCat REST API on a schedule. This is **unverified**: the metadata page does not say the REST API exposes it.

## 4. LiveKit Cloud (media and voice workers)

The current voice worker (`voice-worker/worker.py`) is a LiveKit Agents process. It uses the Deepgram (`nova-3`) and ElevenLabs (`eleven_flash_v2_5`) plugins with our own provider keys, not LiveKit Inference.

### Findings

- **Media.** Clients connect to the nearest edge. Region pinning lists an `sa` group, "South America (Brazil)", with a single location and no in-region redundancy. Regional realtime addresses and static IPs exist only for Canada, the EU, India, Japan and the US. Source: <https://docs.livekit.io/deploy/admin/regions/endpoints/>.
- **Hosted agents (LiveKit Cloud Agents)** deploy only to `us-east`, `eu-central` and `ap-south`. There is no South American region. Source: <https://docs.livekit.io/deploy/admin/regions/endpoints/>.
- **Plans** (source: <https://livekit.com/pricing>):

  | Plan | Price | Concurrent connections | Concurrent agent sessions | Included agent minutes | Included WebRTC minutes |
  |---|---|---|---|---|---|
  | Build | $0 | 100 | 5 | 1,000 | 5,000 |
  | Ship | from $50/mo | 1,000 | 20 | 5,000 | 150,000 |
  | Scale | from $500/mo | 5,000 | up to 600 | 50,000 | 1.5M |
  | Enterprise | custom | custom | custom | custom | custom |

  Agent overage is $0.01/min. WebRTC overage is $0.0005/min on Ship and $0.0004/min on Scale. The Server API is limited to 1,000 requests/min on every plan. Source: <https://docs.livekit.io/home/cloud/quotas-and-limits/>.
- **Agent session limits and self-hosted workers.** The quotas page defines an agent session as an agent "running on LiveKit Cloud". Community staff answers say self-hosted agents do not count toward the concurrent agent session limit, but they do count toward connections and WebRTC minutes. That is **unverified in official docs**. Source: <https://community.livekit.io/t/does-the-5-concurrency-limit-apply-to-self-hosted-agents/135>.
- **Self-hosted worker sizing.** LiveKit recommends "4 cores and 8GB per agent server" for "10-25 concurrent jobs". Workers stop taking jobs above `load_threshold` 0.7 (CPU), stop accepting jobs on SIGINT/SIGTERM and finish the running ones. Voice apps may need "a 10+ minute grace period". Source: <https://docs.livekit.io/deploy/custom/deployments.md>.

### Verdicts

- **A10 Confirmed for media, Changed for hosted agents.** Learner media can stay in Brazil (the `sa` edge). Hosted agents would run in `us-east`, adding a Brazil-to-US hop between the room and the agent. The agent already calls US-hosted STT, TTS and LLM providers, so whether that hop matters is **unverified**: measure the end-to-end turn latency before deciding.
- **A11 depends on where the workers run.** About 200 sessions means about 400 connections (learner plus agent), which fits within Ship's 1,000.
  - **Option A: self-host the workers** (for example, a Fly process group in `gru`). Ship ($50/month) is enough if the self-hosted exemption holds. It needs about 8 to 20 worker machines of 4 vCPU and 8 GB for 200 jobs.
  - Fly's 300 s `kill_timeout` is shorter than the 10-minute grace LiveKit recommends. The workers would need the same drain gate or app-level blue/green as Phoenix (A3).
  - **Option B: LiveKit Cloud Agents.** Ship allows only 20 concurrent agent sessions. About 200 sessions needs **Scale (from $500/month, up to 600 sessions)**. Agents run in `us-east`, and LiveKit handles drain and scaling.
  - The spec says "on LiveKit Cloud", which reads like Option B. Option B is the one with no deploy-drain problem and the least operations work for a one-month launch, at a higher fixed price. This is open question Q2.

## 5. AI provider limits for ~200 simultaneous sessions

Load model (an assumption to replace with the usage metering from user story 53): 200 live stations. Each one makes a patient turn about every 15 s, which gives about 800 patient LLM requests/min at peak. Each turn has one Jev audit, which does not go through Anthropic, and one TTS reply of about 100 to 300 characters. Each session holds one STT stream for 10 minutes.

### Anthropic

- **Tiers.** The tiers are now Start, Build, Scale and Custom. New organizations may begin in a lower **Evaluation** tier until they have usage history. Source: <https://platform.claude.com/docs/en/api/rate-limits>.
- **Rate limits** for Claude Haiku 5.5, Sonnet 5.5 and Opus 5.5 (each model has its own bucket):

  | Tier | RPM | ITPM | OTPM |
  |---|---|---|---|
  | Start | 1,000 | 2,000,000 | 400,000 |
  | Build | 5,000 | 5,000,000 | 1,000,000 |
  | Scale | 10,000 | 10,000,000 | 2,000,000 |

  Source: same page.
- **Cached reads do not count.** Cached input reads do not count toward ITPM for these models, so caching the station prompt raises effective throughput. Limits use a token bucket, short bursts can return 429, and 429 responses carry `retry-after`. Sudden traffic increases can hit "acceleration limits". Source: same page.
- **Monthly spend caps:** Start $500, Build $1,000, Scale $200,000. At the cap, the API returns 429 with `error_code: enforced_spend_limit_reached` and **no `retry-after`** until the first day of next month. Source: same page.

**A12 Changed.** About 800 RPM on Haiku fits the Start tier's 1,000 RPM with little headroom, and Build gives five times that. The real risk is the **spend cap**: up to 1,000 learners doing several stations a day, plus resolver calls, can pass $500 or $1,000 in a month and stop every session until the 1st. Before launch:

1. Request the Scale tier through "Request tier increase" in the Console.
2. Ramp traffic gradually to avoid acceleration limits.
3. Treat `enforced_spend_limit_reached` as an operator alert and an explicit learner error, never a retry.

### Deepgram

- **Concurrency limits** (per project):

  | Plan | Nova-3 streaming | Nova-3 pre-recorded |
  |---|---|---|
  | Pay As You Go | up to 150 | up to 50 |
  | Growth | up to 225 (North America); 150 (Europe, Australia, India) | up to 50 |
  | Enterprise | from 300 | from 200 |

  Source: <https://developers.deepgram.com/reference/api-rate-limits>.
- **Price.** Nova-3 monolingual streaming is $0.0048/min on Pay As You Go and $0.0042/min on Growth. Growth starts at $4k/year in prepaid credits. Source: <https://deepgram.com/pricing>.
- The error returned when the limit is exceeded is not documented on the limits page (**unverified**).

**A13 Changed.** 200 sessions that each hold one stream exceed Pay As You Go's 150. **Growth** (225, North America only) gives about 12% headroom. **Enterprise** (300 or more) gives safe headroom. Alternatives:

1. Buy Growth before launch and set the Phoenix concurrent-session cap (user story 56) to 200 or less, below Deepgram's limit.
2. Close the STT stream while the learner is not speaking. This is **unverified**: it depends on LiveKit's STT plugin behavior and adds reconnect latency.
3. Negotiate Enterprise if the target goes above about 200.

Whether our traffic counts as "North America" depends on the endpoint region, which is **unverified**.

### ElevenLabs

- **TTS concurrency by plan:**

  | Plan | Flash | Multilingual v2 |
  |---|---|---|
  | Free | 4 | 2 |
  | Starter | 6 | 3 |
  | Creator | 10 | 5 |
  | Pro | 20 | 10 |
  | Scale | 30 | 15 |
  | Business | 30 | 15 |
  | Enterprise | elevated | elevated |

  Over HTTP, every in-flight request counts. **Over the WebSocket, only the time spent generating audio counts.** The `current-concurrent-requests` and `maximum-concurrent-requests` headers report usage. Flash v2.5 lists about 75 ms model latency. Source: <https://elevenlabs.io/docs/overview/models>.
- **Plan prices:** Creator $22, Pro $99, Scale $299, Business $990 per month. Included Flash characters: 550k for Creator, 2.475M for Pro, 7.475M for Scale and 24.75M for Business. The page lists $0.04 per 1k Flash characters. Whether that is the overage rate is **unverified**, because the page does not label it. Source: <https://elevenlabs.io/pricing/api>.

**A14 Confirmed with conditions.** With WebSocket streaming, a concurrency slot is held only while audio is generated. That is a fraction of a second per reply. 200 sessions × 1 reply per 15 s gives about 13 replies starting per second. If each generation takes about 0.5 to 1 s, about 7 to 13 slots are busy on average (Little's law), so **Scale (30)** fits with burst headroom. These generation times are unmeasured: read the concurrency headers during a load test. Characters, not concurrency, will drive cost. Size the plan from measured characters per session.

## Open questions for the user

- **Q1 Pix.** Is Pix needed at launch?
  - If not, keep RevenueCat Billing (cards, Apple Pay and Google Pay in BRL).
  - If yes, switch to the Stripe Billing integration. A Brazil-domiciled business still only gets one-time Pix, not Pix Automático subscriptions.
  - Which country is the company domiciled in?
- **Q2 Voice worker hosting.** Self-host the workers on Fly `gru` (LiveKit Ship at about $50/month plus about 8 to 20 four-vCPU machines, and our own drain), or use LiveKit Cloud Agents on Scale (from $500/month, `us-east`, managed drain)?
- **Q3 Deploy drain.** Accept the recommended drain gate (no new sessions for up to about 12 minutes per deploy), or invest in app-level blue/green with `fly-replay`?
- **Q4 Quota source.** Accept that daily quotas live in Phoenix, keyed by RevenueCat `product_id`, instead of in RevenueCat?
- **Q5 Provider plans before launch.** Approve:
  - an Anthropic Scale tier request;
  - Deepgram Growth ($4k/year prepaid) or an Enterprise conversation;
  - an ElevenLabs Scale plan or higher;
  - a paid Neon plan with scale to zero turned off.
- **Q6 Stripe merchant category.** Confirm with Stripe that an exam-preparation product is classified under education, not a medical MCC. This matters for Pix eligibility if Q1 is yes.

## Live checks still pending

These need accounts or measurements, so this research did not do them:

- Round-trip latency from Fly `gru` to Neon `aws-sa-east-1`.
- End-to-end voice turn latency with the agent in `gru` versus LiveKit `us-east`.
- A 200-session load test that reads ElevenLabs concurrency headers, Deepgram stream counts and Anthropic rate-limit headers.
- The Anthropic organization's current tier on the Console Rate limits page.
- Whether self-hosted agents are exempt from the LiveKit agent session limit, confirmed with LiveKit support.
