# Tasks: Implement Station-Attempt-Capture Against the Expo + Phoenix Runtime

## Review Workload Forecast

| Field | Value |
|---|---|
| Estimated changed lines | 1,200–1,800 (Phoenix + Expo + tests) |
| Review budget | 800 lines |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | Setup → Snapshot+chain → Timing+replacements → Access+raw-audio → Mobile capture client → Integration smoke |
| Delivery strategy | auto-chain |
| Chain strategy | stacked-to-main |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|---|---|---|---|---|---|
| 1 | Setup: branch, clean, initial SDD artifacts, baseline `bash scripts/test.sh` green | Setup PR | `bash scripts/test.sh` | `bash scripts/test.sh` | `openspec/changes/implement-station-attempt-capture/{proposal,design,specs,tasks}.md` |
| 2 | Phoenix `Backend.{Attempts,Events,Lineage}` + attempt/event controllers + ExUnit | Snapshot+chain | `mix --cd backend test` | `bash scripts/test.sh` | `backend/lib/backend/{attempts,events,lineage}.ex`, controllers |
| 3 | Phoenix `Backend.{Timing,Replacements}` + timing controller + replacement linkage | Timing+replacements | `mix --cd backend test` | `bash scripts/test.sh` | `backend/lib/backend/{timing,replacements}.ex`, timing controller |
| 4 | Phoenix `Backend.AccessTiers` + transcript controller + raw-audio gate | Access+raw-audio | `mix --cd backend test` | `bash scripts/test.sh` | `backend/lib/backend/access_tiers.ex`, transcript controller |
| 5 | Mobile `stationAttemptCapture/**` + canonicalize parity + client tests | Mobile capture client | `npm --prefix mobile test` | `bash scripts/test.sh` | `mobile/src/stationAttemptCapture/**`, `mobile/__tests__/stationAttemptCapture/**` |
| 6 | Mobile→backend integration smoke + `verify-report.md` 11-scenario coverage map | Integration smoke | `bash scripts/test.sh` | `bash scripts/test.sh` | `mobile/__tests__/stationAttemptCapture/integration.test.ts`, `verify-report.md` |

## Phase 1: Setup

- [ ] 1.1 Branch from `origin/main` HEAD `3383950`; clean untracked `mobile/`, `backend/`, `node_modules/`, `erl_crash.dump`, `PR_BODY*.md`.
- [ ] 1.2 Confirm `bash scripts/test.sh` is still green at the branch tip.
- [ ] 1.3 Author the initial SDD artifacts (`proposal.md`, `design.md`, `specs/.../spec.md`, this `tasks.md`).

## Phase 2: Phoenix Snapshot + Chain Core

- [ ] 2.1 Implement `Backend.Lineage.canonicalize/1` and `hash/1` with golden vectors and ExUnit parity.
- [ ] 2.2 Implement `Backend.Attempts.create/2` enforcing single modality, complete bindings, pseudonymous `pilot_id`, and atomic creation.
- [ ] 2.3 Implement `Backend.Events.append/2` with `seq` allocator, `prior_hash` linker, and mutation/deletion/reordering rejection.
- [ ] 2.4 Add `attempt_controller` and `event_controller` routes, with `409` / `422` error shapes.
- [ ] 2.5 ExUnit: scenarios for fresh-create, mixed-rejection, ordered-append, mutation-rejected, replacement-links, versions-captured.

## Phase 3: Phoenix Timing + Replacements

- [ ] 3.1 Implement `Backend.Timing.resolve/2` registry; one outcome per slot; `integrity_loss` shape fixed.
- [ ] 3.2 Implement `Backend.Replacements.create/2` validating `replacement_of` target existence and `strict_interruption` state.
- [ ] 3.3 Add `timing_controller`; add replacement route on `attempt_controller`.
- [ ] 3.4 ExUnit: scenarios for all-slots-recorded, lost-slot-recorded, non-consuming-terminal; replacement rejection paths.

## Phase 4: Phoenix Access + Raw-Audio Gate

- [ ] 4.1 Implement `Backend.AccessTiers.transcript_for/2` reading server-side tier from request context.
- [ ] 4.2 Implement `transcript_controller`; reject any payload containing audio-shaped keys; append sanitized `integrity_loss`.
- [ ] 4.3 ExUnit: scenarios for raw-audio-rejected, elevated-access; golden test for sanitized `integrity_loss` shape.

## Phase 5: Mobile Capture Client

- [ ] 5.1 Implement `mobile/src/stationAttemptCapture/{types,canonicalize,client}.ts` with the shared hash-link algorithm.
- [ ] 5.2 Add Jest golden-vector parity test against `Backend.Lineage`.
- [ ] 5.3 Add Jest client error-path tests; mobile refuses to send audio-shaped keys.
- [ ] 5.4 Update `mobile/App.tsx` to a minimal capture demo; smoke test `mobile/__tests__/App.smoke.test.tsx` still passes.

## Phase 6: Integration Smoke + Verify

- [ ] 6.1 Add `mobile/__tests__/stationAttemptCapture/integration.test.ts` (Jest + mocked fetch + Phoenix end-to-end through `bash scripts/test.sh`).
- [ ] 6.2 Author `verify-report.md` with the 11-scenario coverage map and byte-equality cross-check on the frozen #12 spec.
- [ ] 6.3 Confirm `bash scripts/test.sh` exit 0; submit for `sdd-verify` admission.