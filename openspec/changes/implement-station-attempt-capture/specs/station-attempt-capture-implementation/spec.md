# station-attempt-capture-implementation Specification

## Purpose

Implements the frozen #12 contract against the Expo + Phoenix runtime. Distinct from the frozen `station-attempt-capture` capability (untouched). Adds the HTTP API, JSON schemas, hash-link algorithm, controller boundaries with raw-audio gate, replacement integrity, access-tier authorization, and 11-scenario coverage map. #12 is source of truth.

## ADDED Requirements

### Requirement: HTTP API Surface

The system MUST expose a JSON API under `/api`: `POST /api/attempts`, `GET /api/attempts/:id`, `POST /api/attempts/:id/replacement`, `POST /api/attempts/:id/events`, `GET /api/attempts/:id/events`, `POST /api/attempts/:id/timing`, `GET /api/attempts/:id/integrity-losses`, `GET /api/attempts/:id/transcript`. Responses MUST use `Content-Type: application/json`. Unknown paths return `404`.

#### Scenario: Endpoints return JSON

- GIVEN Phoenix is running
- WHEN any documented endpoint is called
- THEN Content-Type is `application/json`.

### Requirement: JSON Schemas

Payloads MUST validate against typed schemas: `AttemptCreation {pilot_id, modality, versions{8 fields per #12}}`, `EventAppend {discriminator, occurred_at, payload}`, `TimingResolution {slot_id, outcome, reason?, recovery_action?}`, `ReplacementLink {replacement_of}`. Mobile types MUST mirror backend; drift MUST fail Jest parity.

#### Scenario: Mixed-modality payload rejected

- GIVEN an `AttemptCreation` mixing oral and written modality signals
- WHEN the controller validates
- THEN the request MUST be rejected with `422`; the attempt MUST NOT persist.

### Requirement: Hash-Link Algorithm And Golden Parity

The system MUST compute `event_hash = SHA-256(canonical_json(event_body_without_hash || prior_hash))`. Canonicalization MUST use sorted keys, NFC Unicode, no whitespace, deterministic floats. The algorithm MUST be shared between `Backend.Lineage` and mobile. Golden vectors run in ExUnit and Jest.

#### Scenario: First event links to snapshot

- GIVEN a created attempt
- WHEN the first event is appended
- THEN `prior_hash` equals the creation snapshot hash.

### Requirement: Controller Boundaries And Raw-Audio Gate

`attempt_controller`/`event_controller`/`timing_controller`/`transcript_controller` own snapshot, append-only chain, slot resolution, and transcript projection. Controllers MUST delegate hashing to `Backend.Lineage` and reject payloads with `audio`, `raw_audio`, `bytes`, or `audio_b64` for any Content-Type. On rejection, return `422` with `{error: :raw_audio_rejected, audit_event: {...sanitized...}}` and append an `integrity_loss`. Mobile MUST refuse raw audio bytes.

#### Scenario: Controller delegates hashing and rejects raw audio

- GIVEN a payload mixing valid events with `audio_b64`
- WHEN `event_controller` processes it
- THEN valid events hash via `Backend.Lineage.hash_link/2` AND raw-audio payload returns `422` plus `integrity_loss`.

### Requirement: Replacement Referential Integrity

`Backend.Attempts.create_replacement/2` MUST validate `replacement_of` references an existing `strict_interruption` attempt. Missing target, non-terminal target, or self-reference MUST return `409` with `{error: :invalid_replacement_link}`. The interrupted chain MUST stay immutable.

#### Scenario: Replacement to non-terminal attempt rejected

- GIVEN an attempt in `in_progress`
- WHEN a replacement pointing to it is created
- THEN the request MUST fail with `409 Conflict`.

### Requirement: Access-Tier Authorization

The transcript tier MUST be resolved server-side from a plug-derived trust signal; client flags MUST be ignored. Non-elevated MUST receive the canonical transcript only; elevated MAY receive the full disfluency transcript under policy.

#### Scenario: Full transcript requires elevated tier

- GIVEN a non-elevated request to `GET /api/attempts/:id/transcript`
- WHEN the controller projects the response
- THEN only the canonical transcript is returned.

### Requirement: 11-Scenario Coverage Map

All 11 frozen Given/When/Then scenarios from #12 MUST map to at least one ExUnit or Jest case passing under `bash scripts/test.sh`. `verify-report.md` MUST enumerate the mapping and be admitted by `sdd-verify-validate`.

| # | Scenario | Test surface |
|---|---|---|
| 1 | fresh-create | ExUnit `attempts_test` |
| 2 | mixed-rejection | ExUnit `attempts_test`, Jest `client.test` |
| 3 | ordered-append | ExUnit `events_test` |
| 4 | mutation-rejected | ExUnit `events_test` |
| 5 | all-slots-recorded | ExUnit `timing_test` |
| 6 | lost-slot-recorded | ExUnit `timing_test` |
| 7 | non-consuming-terminal | ExUnit `replacements_test` |
| 8 | replacement-links | ExUnit `replacements_test`, Jest `client.test` |
| 9 | versions-captured | ExUnit `attempts_test` |
| 10 | raw-audio-rejected | ExUnit controllers, Jest `client.test` |
| 11 | elevated-access | ExUnit `access_tiers_test` |

#### Scenario: All 11 scenarios pass under bash scripts/test.sh

- GIVEN `verify-report.md` enumerates the mapping
- WHEN `bash scripts/test.sh` runs and `sdd-verify-validate` admits
- THEN each frozen scenario has at least one passing test.
