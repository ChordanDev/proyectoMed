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

- [x] T1 `StationAI.Addressee`: marker parser (whole text and streamed prefix) + unit tests.
- [x] T2 Prompt asks for the marker; `StationAI.next_reply/2` strips it before BoundedReply.
- [x] T3 Text and non-streamed voice paths decide from the marker / impresso match; no Jev addressee call.
- [ ] T4 Streamed voice path decides from the streamed marker / impresso match; no Jev addressee call.
- [ ] T5 Delete `JevDecision.decide_addressee` (adapters, config, tests); update `docs/design/turn-addressee.md`.

## Routing

All tasks: delegated direct (this worker is the bounded writer); inline within the worker.

## Checks

- Focused: `mix test` on the touched test files per task (RED then GREEN).
- Closure: local CI script (`LOCAL CI PASSED`).
- Live: Haiku run of the 10-turn script plus examiner turns; addressee and latency per turn.

## Progress

- T1 `40d2a2d`: RED 16/16 failing (module missing) -> GREEN 16 passed (`station_ai_addressee_test.exs`).
- T2 (this commit): RED 5 failing (prompt + `next_reply` strip) and 3/3 failing in `addressee_marker_turn_test.exs`
  -> GREEN 26 + 3 passed; full backend suite 1745 passed. The `next_reply/2` boundary keeps `%{text, used_facts}`.

- T2 `af921a0`.
- T3 (this commit): RED 9/12 failing in `addressee_marker_turn_test.exs` (examiner marker, impresso shortcut,
  missing-marker log, no Jev addressee request, text and non-streamed voice) -> GREEN 12 passed; then migrated
  the Jev-addressee text/voice tests (controller, evidence, gate-contract texts that now name an impresso)
  and moved the #302/#305 impresso tests into the new file; full backend suite 1740 passed.

## Next step

T4.
