# Proposal: Capture Pilot Attempt Evidence Lineage

## Intent

Originating issue [#12](https://github.com/ChordanDev/proyectoMed/issues/12), under parent [#10](https://github.com/ChordanDev/proyectoMed/issues/10), needs an auditable record of each one-station pilot attempt. The record must preserve evidence, timing, modality, policy, and version context without retaining raw audio, so later work can evaluate the pilot fairly.

## Scope

### In Scope
- Define the attempt lifecycle, including terminal strict interruptions that do not consume an attempt and link to a replacement.
- Capture append-only, pseudonymous event evidence, expected timing slots and integrity-loss records.
- Bind every attempt to station, rubric, policy, provider-route, application-build, and telemetry-schema versions; preserve accessibility and material-unlock context.
- Keep oral and written modalities distinct at attempt creation.

### Out of Scope
- Gate evaluation and advancement decisions ([#13](https://github.com/ChordanDev/proyectoMed/issues/13)).
- Frozen reports, metrics, or reporting contracts ([#14](https://github.com/ChordanDev/proyectoMed/issues/14)).
- Pilot execution or verification ([#15](https://github.com/ChordanDev/proyectoMed/issues/15)).
- Application implementation, provider selection, and raw-audio retention.

## Capabilities

### New Capabilities
- `station-attempt-capture`: captures lifecycle state and immutable, version-bound evidence lineage for a pseudonymous pilot station attempt.

### Modified Capabilities
None. No existing OpenSpec capabilities exist.

## Approach

Create a capability-aligned delta spec for `station-attempt-capture`. It will formalize lifecycle, event discriminators, strict-interruption replacement links, timing-integrity failures, version binding, access tiers, and modality validation using the locked #2–#9 inputs. This is the secondary seam defined by #10 and unblocks #13 without defining its decisions.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `openspec/changes/capture-pilot-attempt-evidence-lineage/specs/station-attempt-capture/spec.md` | New | Delta contract for issue #12. |
| `openspec/specs/station-attempt-capture/spec.md` | New on archive | Canonical capability specification. |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Scope enters #13 or #14 | Medium | Exclude decision and report semantics from requirements. |
| Missing timestamps improve metrics silently | Medium | Persist integrity-loss records; never omit expected slots. |
| Evidence exposes participant data | Medium | Use pseudonymous IDs, restricted transcript access, and no raw audio. |

## Rollback Plan

Before implementation, revert this change's delta artifacts and do not archive them into the canonical spec. No application behavior or GitHub issue is changed by this proposal.

## Dependencies

- Parent contract #10 and locked inputs from issues #2–#9.
- Downstream issue #13 remains blocked until this capability contract is complete.
- Strict TDD remains disabled until a runnable stack exists.

## Success Criteria

- [ ] The delta spec defines valid, interrupted, and replacement attempt lineage without mutable corrections.
- [ ] Every expected timing slot and required version context is representable, including integrity loss.
- [ ] The contract prohibits raw-audio storage and rejects mixed oral/written attempt modalities.
- [ ] The completed capability is sufficient for #13, without specifying gate evaluation.
