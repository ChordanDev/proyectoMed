# Design: Capture Pilot Attempt Evidence Lineage

## Technical Approach

Define `station-attempt-capture` as an implementation-neutral artifact contract. An immutable attempt snapshot anchors one append-only event chain; lifecycle state is projected from validated transition events. The contract records explicit outcomes for every expected timing slot, preserves strict-interruption replacement lineage, binds creation-time versions and context, and exposes access-tiered transcript evidence without retaining raw audio. It supplies evidence to later work but defines no #13 gate, #14 report, #15 pilot execution, GitHub mutation, or application code.

## Architecture Decisions

| Option | Tradeoff | Decision |
|---|---|---|
| Capability contract vs. application architecture | A contract cannot select storage or framework details, but matches this planning-only repository. | Keep the design technology-neutral and capability-aligned; defer Expo/Phoenix implementation choices until code exists. |
| Mutable attempt row vs. immutable snapshot plus event chain | Projection adds read-time interpretation; mutation would weaken auditability. | Anchor the chain in the creation snapshot and derive current lifecycle from append-only transition events. |
| Optional timing rows vs. one explicit outcome per expected slot | Explicit outcomes add records but prevent missing data from disappearing silently. | Resolve every slot with exactly one `timing_recorded` or `integrity_loss` event. |
| Combined evidence access vs. tiered transcript views | Tiering requires authorization-aware consumers but supports minimization. | Store no raw audio; separate participant-visible canonical transcript access from elevated full-disfluency access. |

The exactly-one timing outcome and creation-snapshot hash link are design decisions that operationalize the spec's timing-completeness and prior-hash requirements; they are not additional spec-mandated requirements.

## Data Flow

```text
creation request
  -> validate one modality + complete bindings
  -> immutable attempt snapshot / chain anchor
  -> sanitized capture signals
  -> ordered, hash-linked events
  -> lifecycle and timing projections
  -> access-tiered evidence reads for later consumers

raw audio -> MUST reject bytes -> MUST append metadata-only integrity_loss
strict interruption -> terminal event -> replacement snapshot(replacement_of)
```

By design, the first event references the creation snapshot hash; each later event references its predecessor. A replacement starts a new chain and points to the interrupted `attempt_id`; the original remains read-only and non-consuming.

## File Changes

| Artifact | Action | Description |
|---|---|---|
| `openspec/changes/capture-pilot-attempt-evidence-lineage/design.md` | Create | Record this technical design. |
| `openspec/changes/capture-pilot-attempt-evidence-lineage/specs/station-attempt-capture/spec.md` | No change | Governing delta contract. |
| `openspec/specs/station-attempt-capture/spec.md` | Deferred | Created by archive after verification, not by this change phase. |
| `docs/PRD.md` | No change | Governing product principles only. |

No source, test-runner, GitHub issue, gate, report, or pilot-execution artifact changes are included.

## Interfaces / Contracts

| Record | Required contract |
|---|---|
| Attempt snapshot | Pseudonymous `attempt_id`, `pilot_id`; immutable `modality`; UTC `created_at`; optional `replacement_of`; bindings for station, rubric, policy, provider route, application build, telemetry schema, accessibility context, and material-unlock state. |
| Event | `attempt_id`, pseudonymous `pilot_id`, discriminator, UTC `occurred_at`, increasing `seq`, `prior_hash`, and sanitized payload/reference. Committed events cannot be updated, deleted, or reordered. |
| Lifecycle | Only `created -> in_progress -> submitted -> evaluated -> closed`, or `in_progress -> strict_interruption`. The latter is terminal and does not consume the attempt budget. |
| Timing slot | Each expected phase slot resolves once to `{slot_id, started_at, ended_at}` or `integrity_loss {slot_id, reason, recovery_action}`. |
| Transcript access | Canonical participant-visible transcript is the default projection; full-disfluency transcript requires elevated policy authorization. Raw-audio payloads are rejected and never enter lineage. |

Creation is atomic: mixed modalities or incomplete bindings produce no attempt. A raw-audio persistence attempt MUST reject the payload bytes and append a sanitized metadata-only `integrity_loss` event to the attempt chain. Standard `occurred_at`, `seq`, and `prior_hash` fields make the rejection auditable; raw bytes never enter lineage.

## Testing Strategy

| Layer | What to Test | Approach |
|---|---|---|
| Spec review | Five requirements and eleven scenarios | Trace each scenario to the contracts and data flow; verify RFC 2119 outcomes remain representable. |
| Invariant review | State ordering, hash/sequence continuity, timing completeness, replacement linkage, immutable bindings | Review valid and prohibited examples, including mixed modality, mutation, silent slot omission, invalid replacement, unauthorized transcript access, and raw-audio persistence. |
| Scope review | Boundary with #13–#15 and repository capabilities | Confirm no gate logic, frozen-report schema, pilot execution, GitHub mutation, source path, or executable test is introduced. Unit, integration, and E2E execution remain unavailable per `openspec/config.yaml`. |

## Threat Matrix

N/A — no routing, shell, subprocess, VCS/PR automation, executable-file classification, or process-integration boundary.

## Migration / Rollout

No data or application migration required. After artifact review, archive may promote the delta to the canonical capability spec; implementation rollout is deferred until a runnable stack exists.

## Open Questions

None.
