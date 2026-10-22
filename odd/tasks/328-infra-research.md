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

## Next step
The user answers Q1–Q6 in the report. The live checks it lists stay pending until accounts exist.
