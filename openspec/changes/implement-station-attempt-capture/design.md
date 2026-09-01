# Design: Implement Station-Attempt-Capture Against the Expo + Phoenix Runtime

## Technical Approach

Implement the frozen contract from #12 as a Phoenix 1.8 JSON API and Expo 54 TypeScript client, sharing a canonical-JSON SHA-256 hash-link algorithm. A pseudonymous attempt snapshot anchors one append-only event chain; lifecycle state is projected from validated transition events. The contract records explicit outcomes for every expected timing slot, preserves strict-interruption replacement lineage, binds creation-time versions, and exposes tier-restricted transcripts without retaining raw audio. It supplies evidence to later work but defines no #13 gate, #14 report, #15 pilot execution, GitHub mutation, or persistence layer.

## Architecture Decisions

| Option | Tradeoff | Decision |
|---|---|---|
| Shared canonical-JSON SHA-256 hash-link algorithm | Symmetric cost in mobile + backend; algorithm drift risk | Implement once each in mobile TS and Elixir with golden-vector parity tests in both runtimes |
| Append-only event chain in `:ets` set | Memory-only; loses across restart but matches prototype scope | Use `:ets` set keyed by `{attempt_id, seq}`; document as prototype-only |
| Server-side access-tier trust signal | Mobile cannot bypass | `transcript_controller` reads tier from a plug-injected request context, never from client payload |
| Raw-audio rejection at controller boundary + mobile client | Defense-in-depth | Mobile refuses to send audio bytes; backend rejects any payload containing audio-shaped keys with `integrity_loss` appended |
| `replacement_of` referential integrity at write time | Stops bad writes before they reach the chain | Validate target existence and `strict_interruption` state in `Backend.Replacements`; return `409 Conflict` otherwise |

## Data Flow

```text
mobile capture UI
  -> POST /api/attempts {modality, bindings}
  -> Backend.Attempts.create (atomic, single modality, complete bindings, pseudonymous pilot_id)
  -> snapshot hash + first event
  -> ordered, hash-linked events (append-only)
  -> POST /api/attempts/:id/timing {slot} -> Backend.Timing.resolve -> timing_recorded | integrity_loss
  -> strict interruption -> terminal event -> replacement snapshot(replacement_of)
  -> access-tiered evidence reads for later consumers
```

The first event references the creation snapshot hash; each later event references its predecessor. A replacement starts a new chain and points to the interrupted `attempt_id`; the original remains read-only and non-consuming.

## File Changes

| Artifact | Action | Description |
|---|---|---|
| `backend/lib/backend/attempts.ex` | Create | Pseudonymous attempts with modality immutability and atomic creation |
| `backend/lib/backend/events.ex` | Create | Append-only event chain with `seq` + `prior_hash` linker |
| `backend/lib/backend/lineage.ex` | Create | Canonical-JSON SHA-256 algorithm |
| `backend/lib/backend/timing.ex` | Create | Slot registry and `timing_recorded`/`integrity_loss` resolver |
| `backend/lib/backend/replacements.ex` | Create | Strict-interruption transition and `replacement_of` validation |
| `backend/lib/backend/access_tiers.ex` | Create | Server-side tier trust signal and transcript projection |
| `backend/lib/backend_web/controllers/{attempt,event,timing,transcript}_controller.ex` | Create | JSON API surface |
| `backend/lib/backend_web/router.ex` | Modify | Add `/api/attempts*` routes |
| `backend/lib/backend_web/controllers/error_json.ex` | Modify | 409 / 422 / 403 rejection shapes |
| `backend/test/backend/**/*_test.exs`, `backend/test/backend_web/controllers/*_test.exs` | Create | ExUnit coverage for all 11 frozen scenarios |
| `mobile/src/stationAttemptCapture/{types,canonicalize,client}.ts` | Create | Shared types, canonicalizer, HTTP client |
| `mobile/__tests__/stationAttemptCapture/**` | Create | Golden-vector parity and client tests |
| `mobile/App.tsx` | Modify | Minimal capture demo; smoke test still passes |
| `openspec/changes/implement-station-attempt-capture/verify-report.md` | Create | 11-scenario coverage map and PASS verdict |

## Interfaces / Contracts

| Component | Contract |
|---|---|
| `Backend.Lineage.canonicalize/1` | Returns canonical JSON bytes (sorted keys, NFC unicode, no whitespace, deterministic floats) |
| `Backend.Lineage.hash/1` | SHA-256 over canonical bytes, hex-encoded |
| `Backend.Attempts.create/2` | Returns `{attempt_id, snapshot_hash}` or `{:error, :modality_conflict | :incomplete_bindings | :replacement_not_strict}` |
| `Backend.Events.append/2` | Returns `{seq, hash}` or `{:error, :chain_broken}`; mutation/deletion/reordering rejected |
| `Backend.Timing.resolve/2` | Returns `:ok` exactly once per slot; subsequent calls return `{:error, :slot_resolved}` |
| `Backend.Replacements.create/2` | Returns `{replacement_id}` or `{:error, :replacement_target_invalid}` (409) |
| `Backend.AccessTiers.transcript_for/2` | Returns `{:canonical, transcript}` or `{:elevated, transcript}` per request context |
| Mobile `canonicalize.ts` | Same algorithm; parity test against `Backend.Lineage` golden vectors |
| Mobile `client.ts` | Wraps `fetch`; refuses to send audio-shaped keys |

## Testing Strategy

| Layer | What to Test | Approach |
|---|---|---|
| Phoenix unit | `Backend.{Lineage,Attempts,Events,Timing,Replacements,AccessTiers}` | ExUnit with shared fixtures, covering all 11 frozen Given/When/Then scenarios |
| Phoenix controller | Routes return correct status and shape | ExUnit via `ConnCase` |
| Mobile unit | Canonicalize parity, client error paths, raw-audio client-side refusal | Jest with golden vectors and mocked fetch |
| Integration | Mobile→backend end-to-end smoke | `bash scripts/test.sh` exit 0; both runtimes green |
| Coverage map | All 11 scenarios have at least one passing test | Listed in `verify-report.md` |

## Threat Matrix

N/A except for `scripts/test.sh` which already exists; no new shell boundary introduced. Row applicable only to the existing `test.sh` and `scaffold.sh` from #16.

## Migration / Rollout

None — no data or application migration required. After verification, archive the new `station-attempt-capture-implementation` capability. #12 archives on its own verify gate, independent of this change.

## Open Questions

None.