# Tasks: Capture Pilot Attempt Evidence Lineage

## Review Workload Forecast

| Field | Value |
|---|---|
| Estimated changed lines | 130–180 artifact lines |
| Review budget | 800 lines |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single artifact-only review change |
| Delivery strategy | auto-chain |
| Chain strategy | pending |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Low

Planning-only boundary: no source, package manifest, or test runner exists. These are artifact-review tasks only; do not create application code or executable tests.

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|---|---|---|---|---|---|
| 1 | Complete contract trace review | Artifact-only PR | N/A — runner unavailable | N/A — no runnable stack | `openspec/changes/capture-pilot-attempt-evidence-lineage/tasks.md` |

## Phase 1: Lifecycle and Lineage Trace

- [x] 1.1 Review `proposal.md`, `design.md`, and `specs/station-attempt-capture/spec.md`; confirm the contract stays technology-neutral and excludes #13–#15 decisions, reports, execution, GitHub, and code.
- [x] 1.2 Trace Attempt Creation: `created` has pseudonymous IDs, one immutable oral/written modality, UTC time, and valid forward transitions; verify fresh creation and mixed-modality rejection leaves no attempt.
- [x] 1.3 Trace Append-Only Lineage: verify event identity, UTC time, discriminators, increasing `seq`, snapshot-hash first link, predecessor hashes thereafter; verify ordered appends and rejected mutation/deletion/reordering.

## Phase 2: Integrity and Access Trace

- [x] 2.1 Trace Timing Slots: verify each expected slot resolves exactly once to `timing_recorded` or `integrity_loss {slot_id, reason, recovery_action}`; verify complete-slot and lost-slot/queryable scenarios.
- [x] 2.2 Trace Strict Interruption: verify only `in_progress -> strict_interruption` is terminal and non-consuming; verify a new read-only replacement chain uses `replacement_of`.
- [x] 2.3 Trace Creation Bindings and Access: verify atomic rejection of incomplete bindings; capture all eight version/context fields at creation and prohibit rewrites.
- [x] 2.4 Trace evidence minimization: verify canonical transcript default, elevated full-disfluency access, and raw-audio byte rejection followed by sanitized metadata-only `integrity_loss` with event-chain fields.

## Phase 3: Verification and Readiness Gate

- [x] 3.1 Perform a manual RFC-2119 trace of all five requirements and eleven scenarios against the snapshot, event, lifecycle, timing, replacement, and access contracts; record results in this task checklist.
- [x] 3.2 Confirm no applicable threat-matrix RED test exists and no executable test is scheduled: the design marks all listed threat boundaries N/A and `openspec/config.yaml` reports every test layer unavailable.
- [x] 3.3 Block `sdd-apply` for this capability until a separate SDD proposal establishes a runnable Expo/Phoenix stack, source paths, and test command; retain this change as planning evidence.
