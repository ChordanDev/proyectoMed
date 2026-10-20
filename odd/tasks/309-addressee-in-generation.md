# 309 - Addressee decided in the patient generation

Issue: #309 (parent #237). Branch: `feat/309-addressee-in-generation` (base `feat/237-clinician-demo-readiness`).

## Objective

The patient generator decides who a learner turn is addressed to in the same call:
every reply starts with `[PACIENTE]` or `[EXAMINADOR]`. The separate Jev
`turn_addressee` call leaves every path (text, voice, streamed voice).

## Why

The Jev addressee call costs 0.2-0.5 s per turn (one 1 s error in the last
rehearsal) and runs beside a generation that is thrown away on examiner turns
(#294). One call doing both removes that cost and failure mode.

## Constraints

- The marker is parsed in code from the first tokens, before any sentence reaches
  TTS or the client; it is never spoken, shown or stored.
- Missing/invalid marker: patient path, logged (no content in logs).
- `Impressos.match` on the learner text short-circuits to examiner, without the model.
- Examiner path unchanged: kept learner turn, "Anotado.", impresso release (#302/#305).
- Architecture: internal modules under `backend/lib/backend/stations/`; `BackendWeb` thin.

## Tasks

- [ ] T1 `StationAI.Addressee`: marker parser (whole text and streamed prefix) + unit tests.
- [ ] T2 Prompt asks for the marker; `StationAI.next_reply/2` strips it before BoundedReply.
- [ ] T3 Text and non-streamed voice paths decide from the marker / impresso match; no Jev addressee call.
- [ ] T4 Streamed voice path decides from the streamed marker / impresso match; no Jev addressee call.
- [ ] T5 Delete `JevDecision.decide_addressee` (adapters, config, tests); update `docs/design/turn-addressee.md`.

## Routing

All tasks: delegated direct (this worker is the bounded writer); inline within the worker.

## Checks

- Focused: `mix test` on the touched test files per task (RED then GREEN).
- Closure: local CI script (`LOCAL CI PASSED`).
- Live: Haiku run of the 10-turn script plus examiner turns; addressee and latency per turn.

## Progress

(updated per task)

## Next step

T1.
