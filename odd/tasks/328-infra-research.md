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
- [ ] T1 (route: inline; no delegation trigger — single passive doc, research via web tools) Write `docs/research/production-infrastructure.md` covering every scope item, with a confirmed/changed verdict per spec assumption and an open-questions list.

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
- T1: pending.

## Next step
Research and write T1.
