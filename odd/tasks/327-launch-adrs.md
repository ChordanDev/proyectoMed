# #327 Record the production-launch architecture decisions as ADRs

Locator: `odd/tasks/327-launch-adrs.md` · branch `docs/327-launch-adrs` (from `origin/feat/326-production-launch`) · Engram `odd/327-launch-adrs/tasks` · parent spec #326.

## Objective
Publish every ADR change that spec #326 depends on, as GitHub issues (new ADRs) or amendment comments (existing ADRs), and sync the `CONTEXT.md` glossary so it no longer contradicts them.

## Why
Spec #326 (production launch: database, accounts, subscriptions, results history, many reviewed cases, multi-actor stations) contradicts accepted ADR-001 #34 (no database, no accounts) and narrows or extends ADR-013 #209, ADR-007 #92, ADR-002 #35 and ADR-012 #124. The repository rule (`docs/agents/domain.md`) says a conflict with a recorded ADR must be surfaced explicitly, not silently overridden.

## Scope and constraints
- ADRs are GitHub issues labelled `type:docs` with `ADR-NNN:` titles (template `.github/ISSUE_TEMPLATE/architecture-decision.yml`); never markdown under `docs/adr/`.
- New ADRs: ADR-014 (supersedes ADR-001), ADR-015 (Phoenix LiveView for account, billing and admin). Amendments: comments on #209, #92, #35, #124. ADR-001 #34 marked superseded with a link.
- English, neutral register. The repository change is only `CONTEXT.md` plus this file; no code.
- Allowed edit surfaces: `CONTEXT.md`, `docs/**`, `odd/tasks/327-launch-adrs.md`.
- Test-first exception: passive documentation and GitHub issue text; there is no runnable deterministic test. Proportionate checks are structural: a ripgrep check over `CONTEXT.md` for the contradicting statements (must match before, must not match after), readback of every published issue/comment, and local CI.
- Delivery: forecast well under 400 authored lines; strategy `single-pr` into `feat/326-production-launch`.

## Tasks
- [ ] T1 (inline; one mechanical file) Feature document.
- [ ] T2 (inline; GitHub writes only) Publish ADR-014 superseding ADR-001; mark #34 superseded (status line + comment).
- [ ] T3 (inline; GitHub writes only) Amendment comments on ADR-013 #209, ADR-007 #92, ADR-002 #35, ADR-012 #124.
- [ ] T4 (inline; GitHub write only) Publish ADR-015: Phoenix LiveView for account, billing and the admin case panel; the Vite/React SPA stays frozen.
- [ ] T5 (inline; one file) Sync `CONTEXT.md`: Content Partner, MVP Data Retention, Session Data Lifecycle, Jev Gate and the other entries that contradict the new ADRs; add the new launch terms.
- [ ] T6 (inline) Comment on #326 listing links to every ADR change; local CI; PR.

## Acceptance
Per #327: each decision published with context, decision, alternatives and consequences; ADR-001 marked superseded with a link; #326 lists every ADR change; contradicting glossary entries updated; local CI passes.

## Progress / evidence
(filled per task)

## Next
T2.
