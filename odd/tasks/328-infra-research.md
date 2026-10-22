# #328 Research the production infrastructure and billing integration

Locator: `odd/tasks/328-infra-research.md` · branch `docs/328-infra-research` (from `origin/feat/326-production-launch`) · parent spec #326 · Engram `odd/328-infra-research/tasks`.

## Objective
Verify, with primary sources, the infrastructure and billing assumptions spec #326 marks as unverified, and record each finding with its source URL and access date in `docs/research/production-infrastructure.md`.

## Why
The launch (target 2026-11-21) depends on Fly.io, Neon, RevenueCat Web Billing, LiveKit Cloud and three AI providers. Building against wrong region, billing or rate-limit assumptions would cost rework during the critical month.

## Scope
- Fly.io São Paulo region and machine sizing.
- Neon region closest to São Paulo; connection from Fly.
- RevenueCat Web Billing: Stripe vs RevenueCat billing engine, Web Purchase Links vs purchases-js, app_user_id mapping, webhook events and authentication, plan metadata for daily quotas.
- LiveKit Cloud regions near Brazil; plan for ~200 concurrent sessions.
- ElevenLabs, Deepgram and Anthropic concurrency/rate limits for ~200 simultaneous sessions.

## Constraints
- Research only, read-only toward external services: official docs via WebSearch/WebFetch. No accounts, no sign-in, no paid API calls.
- Every claim carries a source URL and access date; unverified items are marked as such.
- No code. Allowed edit surfaces: `docs/research/**`, this file.

## Tasks
- [x] T1 (route: inline; no delegation trigger — single passive doc, research via web tools) Write `docs/research/production-infrastructure.md` covering every scope item, with a confirmed/changed verdict per spec assumption and an open-questions list.

## Test-first policy
Exception: passive documentation-only change; there is no meaningful runnable RED. Checks are structural (every section has a verdict and sources) plus the local CI gate to prove nothing else regressed.

## Acceptance criteria
Per issue #328: report in `docs/` with each finding, source URL and date; each spec assumption marked confirmed or changed with an alternative; open questions listed.

## Checks
- Structural readback of the report.
- `bash <scratchpad>/local_ci.sh <worktree>` prints `LOCAL CI PASSED`.

## Delivery
Forecast ~300–450 authored lines (one doc). Strategy `single-pr` to `feat/326-production-launch`.

## Progress
- T1: done in commit `613dd62` (`docs(research): verify production infrastructure and billing assumptions`).
  - RED/GREEN: not applicable (passive documentation, no runnable RED).
  - Structural check: all 14 assumptions (A1–A14) have one verdict each, every finding carries a source URL, the access date is 2026-10-21, and open questions Q1–Q6 are listed.
  - Local CI: `LOCAL CI PASSED`. Web: 337 tests in 16 files. Backend: 1743 passed. A second web suite: 4 passed.
  - Key changed assumptions:
    - A3: the deploy drain conflicts with Fly's `kill_timeout` maximum of 300 s.
    - A9: quotas cannot come from RevenueCat plan metadata.
    - A12: Anthropic's monthly spend cap is the real limit.
    - A13: Deepgram Pay As You Go allows 150 streams, fewer than 200.
    - A10: LiveKit has no South American region for hosted agents.
- Review round 1 (Jorge C2): A11 had a free-form verdict outside the legend. Relabelled it `Unverified` in the summary table and the verdict heading in commit `e931d87`.
  - RED: `rg '^\| A[0-9]+ '` filtered against `Confirmed|Changed|Unverified` returned the A11 row.
  - GREEN: the same check returns no rows (14 table rows, all legend verdicts).
- Review round 2 (Jorge C1, TR-1): commit `87f6603`.
  - C1: A11 and Q2 now give a total for both options. Option A: performance-4x · 8 GB at $132.01 (Ashburn) × 1.615 ≈ $213/month in `gru`; 8 to 20 machines plus Ship ≈ $1,756 to $4,314/month. Option B: from $500/month plus $0.01 per agent minute above 50,000, with the break-even volume against Option A stated. The "higher fixed price" wording is gone.
  - TR-1: A8 now states the rules for atomicity (dedup insert and entitlement in one transaction), unresolved users (non-200), ordering (`event_timestamp_ms`, no backward expiration) and reconcile (`GET /subscribers`, as RevenueCat recommends; our own job stays open). `TRANSFER`/`PRODUCT_CHANGE` are marked open for #339/#344.
  - RED: `rg 'Option A total|Option B total'` returned 0, Q2 had no total, and A8 matched none of the five rule keywords.
  - GREEN: 2 option totals, 1 Q2 total, and all five A8 keywords match once each.

## Next step
The user answers Q1–Q6 in the report. The live checks it lists stay pending until accounts exist.
