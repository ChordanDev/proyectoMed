# station-attempt-capture Specification

## Purpose

Captures lifecycle and version-bound evidence lineage for each pseudonymous pilot station attempt, without raw audio or gate decisions. Downstream evaluation (#13) and reporting (#14) consume it.

## Requirements

### Requirement: Attempt Creation And Lifecycle States

The system MUST record each attempt as one of `{created, in_progress, submitted, evaluated, closed, strict_interruption}`. `created` carries a pseudonymous `attempt_id`, `pilot_id`, a `modality` of `oral` or `written`, and UTC `created_at`. Bundling `oral` and `written` MUST be rejected; the chosen modality MUST persist, MUST NOT mutate. Forward transitions MUST follow `created → in_progress → submitted → evaluated → closed`; skip, reorder, rewind are prohibited. `in_progress → strict_interruption` is the sole lateral exit before submission.

#### Scenario: Fresh attempt enters created

- GIVEN no prior attempt
- WHEN the participant starts the station
- THEN a `created` attempt exists with pseudonymous `attempt_id` and `modality`

#### Scenario: Mixed modality is rejected

- GIVEN a creation payload mixes oral and written events
- WHEN the system validates the attempt
- THEN creation MUST be rejected; the attempt MUST NOT persist.

### Requirement: Append-Only Pseudonymous Event Lineage

The system MUST record every attempt event as append-only, tagged with `attempt_id`, pseudonymous `pilot_id`, an event discriminator, UTC `occurred_at`. Mutation, deletion, reordering of committed events are prohibited. Each event MUST carry a monotonically increasing `seq` and MUST reference the prior hash.

#### Scenario: Events append in order

- GIVEN an attempt in `in_progress`
- WHEN two events occur in sequence
- THEN both store with strictly increasing `seq` and the prior hash

#### Scenario: Mutation is rejected

- GIVEN a committed event
- WHEN any actor requests a mutation
- THEN the request MUST be rejected and the event stays unchanged

### Requirement: Expected Timing Slots And Integrity Loss

The system MUST define expected timing slots per phase, persist a record for every slot, and produce an `integrity_loss` for any lost slot naming slot, reason, and recovery action. Silent omission is prohibited.

#### Scenario: All expected slots recorded

- GIVEN an attempt in `in_progress`
- WHEN each phase boundary completes
- THEN a timing record is stored with `slot_id`, `started_at`, `ended_at`

#### Scenario: Lost slot recorded as integrity loss

- GIVEN the capture pipeline drops a slot
- WHEN the slot window closes
- THEN an `integrity_loss` event names the slot and reason, the attempt stays queryable

### Requirement: Strict-Interruption Replacement Integrity

`strict_interruption` (examiner halt, safety stop, or pre-submission policy violation) MUST be terminal, MUST NOT consume the attempt budget. The system MUST link the interrupted attempt to a replacement via `replacement_of` and preserve the interrupted attempt's lineage read-only.

#### Scenario: Strict interruption does not consume budget

- GIVEN an attempt in `in_progress`
- WHEN strict interruption occurs
- THEN the attempt transitions to `strict_interruption`; the budget is preserved

#### Scenario: Replacement links to interrupted attempt

- GIVEN an attempt in `strict_interruption`
- WHEN a replacement is created
- THEN it carries `replacement_of: <interrupted attempt_id>` and the interrupted events stay immutable

### Requirement: Version Binding, Access Tiers, And No Raw Audio

At `created`, the system MUST bind every attempt to active versions: `station`, `rubric`, `policy`, `provider_route`, `application_build`, `telemetry_schema`, `accessibility_context`, `material_unlock_state`. Retroactive version-binding rewrite is prohibited. Raw audio MUST NOT be stored or persisted; transcripts MUST be tier-restricted (participant-visible canonical; full transcript with disfluencies requires elevated access).

#### Scenario: Versions captured at creation

- GIVEN a station start
- WHEN the attempt is created
- THEN the record contains all bound fields plus `accessibility_context` and `material_unlock_state`

#### Scenario: Raw-audio write is rejected

- GIVEN a capture pipeline attempts audio persistence
- WHEN the persistence layer receives a raw-audio payload
- THEN the write MUST be rejected; an `integrity_loss` event is logged

#### Scenario: Full transcript requires elevated access

- GIVEN a full disfluencies transcript exists
- WHEN a non-elevated actor requests it
- THEN only the participant-visible transcript is returned; elevated actors MAY retrieve it under policy.