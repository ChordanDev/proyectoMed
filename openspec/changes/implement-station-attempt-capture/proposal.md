# Proposal: Implement Station-Attempt-Capture Against the Expo + Phoenix Runtime

## Intent

Originating issue [#19](https://github.com/ChordanDev/proyectoMed/issues/19), under parent [#10](https://github.com/ChordanDev/proyectoMed/issues/10), implements the frozen contract from [#12](https://github.com/ChordanDev/proyectoMed/issues/12) against the runnable runtime from [#16](https://github.com/ChordanDev/proyectoMed/issues/16). This delivers the **secondary external seam** that [#10](https://github.com/ChordanDev/proyectoMed/issues/10) defines: pseudonymous attempt capture with append-only event lineage, timing-integrity accounting, strict-interruption replacement, and version-bound, tier-restricted, raw-audio-free evidence. It does **not** introduce #13 gate logic, #14 frozen reporting, #15 pilot execution, persistence, or provider selection.

## Scope

### In Scope
- Implement `Backend.{Attempts, Events, Lineage, Timing, Replacements, AccessTiers}` plus four Phoenix controllers covering all 5 frozen requirements and 11 Given/When/Then scenarios.
- Implement `mobile/src/stationAttemptCapture/**` and replace the stub `mobile/App.tsx` with a minimal capture-pipeline demo screen that the smoke test still covers.
- Share the canonical JSON hash-link algorithm between mobile and backend with a golden-vector parity test.
- Extend `scripts/test.sh` (already wired in #16) so all 11 scenarios have at least one ExUnit/Jest case that runs under `bash scripts/test.sh`.
- Persist a `verify-report.md` that documents the 11-scenario coverage map.

### Out of Scope
- Gate evaluation, advancement decisions, or scoring ([#13](https://github.com/ChordanDev/proyectoMed/issues/13)).
- Frozen advancement reports ([#14](https://github.com/ChordanDev/proyectoMed/issues/14)).
- Pilot execution or clinical release ([#15](https://github.com/ChordanDev/proyectoMed/issues/15)).
- Modifying the archived #12 contract; that change archives on its own verify gate, independent of this change.
- Persistence beyond the attempt lineage, authentication, deployment, voice-pipeline tuning, and raw-audio retention.

## Capabilities

### New Capabilities
- `station-attempt-capture-implementation`: implements the frozen contract from #12 as a Phoenix JSON API and Expo TypeScript client, sharing a hash-link algorithm and exposing the access tiers, raw-audio gate, and `replacement_of` referential integrity that the contract mandates. Distinct from the frozen `station-attempt-capture` capability.

### Modified Capabilities
None. The frozen `station-attempt-capture` capability is byte-frozen and remains read-only for this change.

## Approach

1. Branch from `origin/main` (HEAD `3383950`), clean stale untracked state, and implement the Phoenix modules/controllers, the Expo capture client, and the updated `App.tsx`.
2. Author a delta spec under `openspec/changes/implement-station-attempt-capture/specs/station-attempt-capture-implementation/spec.md` with **only ADDED requirements**, no MODIFIED or REMOVED sections touching the frozen capability.
3. Stack the implementation as **six work units**: setup, Phoenix snapshot+chain, Phoenix timing+replacements, Phoenix access+raw-audio gate, mobile capture client, and integration smoke. Each unit ≤ 800 authored lines, verified by `bash scripts/test.sh`.
4. Author a `verify-report.md` with a scenario-to-test map covering all 11 frozen Given/When/Then scenarios; admission through `gentle-ai sdd-verify-validate`.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `backend/lib/backend/{attempts,events,lineage,timing,replacements,access_tiers}.ex` | New | Phoenix domain modules enforcing the frozen contract |
| `backend/lib/backend_web/controllers/{attempt,event,timing,transcript}_controller.ex` | New | JSON API surface |
| `backend/lib/backend_web/router.ex`, `backend/lib/backend_web/controllers/error_json.ex` | Modified | Routes and rejection error shapes |
| `backend/test/backend/**/*_test.exs`, `backend/test/backend_web/controllers/*_test.exs` | New | ExUnit scenario coverage |
| `mobile/src/stationAttemptCapture/**` | New | Types, canonicalizer, HTTP client |
| `mobile/__tests__/stationAttemptCapture/**` | New | Golden-vector parity and client tests |
| `mobile/App.tsx` | Modified | Replace stub with minimal capture demo (smoke test still passes) |
| `openspec/changes/implement-station-attempt-capture/**` | New | This change folder |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Frozen #12 contract drift | Medium | Separate identifier, ADDED-only delta, no MODIFIED/REMOVED on the frozen capability |
| Hash-link algorithm drift between mobile and backend | Medium | Single shared algorithm with golden-vector parity test in both Jest and ExUnit |
| Raw-audio rejection bypass | Medium | Reject any `audio`/`raw_audio`/`bytes`/`audio_b64` keys; write `integrity_loss` with sanitized metadata; cover in ExUnit + Jest |
| `replacement_of` referential integrity | Low | Validate target existence and `strict_interruption` state at write time, return 409 |
| Working-tree cleanup loses untracked WIP | Low | Working-tree `mobile/` lockfile matches committed toolchain; reproducible via `npm ci` |

## Rollback Plan

Revert the implementation branch; remove the `station-attempt-capture-implementation` capability from `openspec/specs/` if it had been archived (it will not be archived by this change). The frozen #12 contract and the #16 scaffold remain intact in `main`.

## Dependencies

- Merged scaffold from [#16](https://github.com/ChordanDev/proyectoMed/issues/16) (commit `50425ff`).
- Frozen contract from [#12](https://github.com/ChordanDev/proyectoMed/issues/12) (`openspec/changes/capture-pilot-attempt-evidence-lineage/specs/station-attempt-capture/spec.md`).
- Downstream issues #13–#15 remain blocked on their own tickets.

## Success Criteria

- [ ] All 11 frozen Given/When/Then scenarios from the #12 spec map to at least one passing ExUnit/Jest test under `bash scripts/test.sh`.
- [ ] `mobile/__tests__/App.smoke.test.tsx` continues to pass.
- [ ] No MODIFIED or REMOVED sections on the frozen `station-attempt-capture` capability; no byte drift in `openspec/changes/capture-pilot-attempt-evidence-lineage/specs/station-attempt-capture/spec.md`.
- [ ] `sdd-verify-validate` admits the `verify-report.md` with verdict PASS.