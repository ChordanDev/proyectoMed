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
- [x] T1 (inline; one mechanical file) Feature document. Commit `824324e`.
- [x] T2 (inline; GitHub writes only) Publish ADR-014 superseding ADR-001; mark #34 superseded (status line + comment).
- [x] T3 (inline; GitHub writes only) Amendment comments on ADR-013 #209, ADR-007 #92, ADR-002 #35, ADR-012 #124.
- [x] T4 (inline; GitHub write only) Publish ADR-015: Phoenix LiveView for account, billing and the admin case panel; the Vite/React SPA stays frozen.
- [x] T5 (inline; one file) Sync `CONTEXT.md`: Content Partner, MVP Data Retention, Session Data Lifecycle, Jev Gate and the other entries that contradict the new ADRs; add the new launch terms. Commit `646535e`.
- [x] T6 (inline) Comment on #326 listing links to every ADR change; local CI; PR.

## Acceptance
Per #327: each decision published with context, decision, alternatives and consequences; ADR-001 marked superseded with a link; #326 lists every ADR change; contradicting glossary entries updated; local CI passes.

## Progress / evidence
- ADR-014 #346 (supersedes ADR-001): https://github.com/ChordanDev/proyectoMed/issues/346
- ADR-001 #34: Status line edited to "Superseded by ADR-014 #346" and comment https://github.com/ChordanDev/proyectoMed/issues/34#issuecomment-6330999414 (issue kept open as history, like ADR-010 #115).
- ADR-013 #209 amendment: https://github.com/ChordanDev/proyectoMed/issues/209#issuecomment-6331023393
- ADR-007 #92 amendment: https://github.com/ChordanDev/proyectoMed/issues/92#issuecomment-6331035546
- ADR-002 #35 amendment: https://github.com/ChordanDev/proyectoMed/issues/35#issuecomment-6331035877
- ADR-012 #124 amendment: https://github.com/ChordanDev/proyectoMed/issues/124#issuecomment-6331036195
- ADR-015 #347: https://github.com/ChordanDev/proyectoMed/issues/347
- #326 link list: https://github.com/ChordanDev/proyectoMed/issues/326#issuecomment-6331057157
- Readback: every issue and comment above fetched with `gh issue view --json`; titles, `type:docs` labels and first lines match.
- Structural check on `CONTEXT.md` (not a test; no runnable RED applies): ripgrep for the contradicting statements ("no learner account", "no personal history", "no clinician workspace", the unconditional "must pass Jev before it is displayed", "supplies the one MVP station", "does not create personal history", "Content Partner's rubric") matched 8 lines before the edit and 0 after.
- Local CI: see the PR evidence.

## Follow-ups
- `AGENTS.md` and `.agents/skills/backend-phoenix-contexts/SKILL.md` still describe one domain context and a JSON-only `BackendWeb`; update them to the ADR-007 amendment and ADR-015 (outside this issue's edit surface).

## Next
PR review and merge into `feat/326-production-launch`.
