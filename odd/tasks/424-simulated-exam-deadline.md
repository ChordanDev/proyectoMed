# 424 Simulated exam deadline

Objective: end a Prova simulada exactly at its deadline (#424, parent #318 business rule 4 and T3).
Branch: `feat/424-simulated-exam-deadline` from `origin/develop`, PR to `develop`. Delivery: single PR.
Test runners: `cd backend && mix test`, `cd voice-worker && uv run pytest`, `scripts/run-unreal-tests.sh ProyectoMed.StationVoice` and `ProyectoMed.StationClient.FakePhoenix`.

## Specs

- S1. "A learner utterance that started before the deadline is kept as evidence even if its transcript arrives after the deadline, and gets no patient reply."
- S2. "An utterance that starts after the deadline is discarded."
- S3. "The patient never speaks after the deadline in a real test."
- S4. "The learner can still finish a real test early."
- S5. "Trainings keep the current grace window (#256)."
- S6. "The voice worker sends the speech-start timestamp of each final utterance; Phoenix checks it against its own clock with a tolerance defined and documented in the implementation."
- S7. "The real-test branch lives in `Backend.Stations`, never in the client; Phoenix generates and releases no reply for a post-deadline turn, and the worker speaks nothing after the deadline."
- S8. "Each case (started before, started after, at the tolerance boundary) is tested at the Phoenix HTTP API and at the station client module."

Assumptions (marked, not requested):
- A1. After the deadline Phoenix waits a bounded evidence window (5 s by default) for the final transcript of an utterance that started before it; the first transcript after the deadline closes the window early. The client's `FinishSession(Timer)` waits on it (its request timeout is 15 s).
- A2. Tolerance: an utterance counts as started before the deadline when `speech_started_at < deadline_at + 500 ms`. A transcript after the deadline without `speech_started_at` is discarded.
- A3. The generation in flight at the deadline is cut: its learner turn stays and Phoenix answers `201 kept`, so the worker does not stop with a fatal error before the client's own clock reaches zero.

## Tasks

| ID | Specs | Route | Status | Evidence |
| --- | --- | --- | --- | --- |
| T1 | S1, S2, S3, S5, S6, S7 | inline | done | RED then GREEN in `voice_worker_controller_test.exs`; #201 grace tests moved to trainings; `e985c2a` |
| T2 | S3, S6, S7 | inline | done | RED then GREEN in `test_transcripts.py` and `test_worker.py`; `469c4e1`, `5fc4d4e` |
| T3 | S8 | inline | done | characterization specs (no client change needed); `26136c4` |
| T4 | all | inline | done | docs/unreal-station-client.md, CONTEXT.md, README.md |

## Log

- L1 (2026-10-29, user request verbatim): "Implement GitHub issue #424 in ChordanDev/proyectoMed: \"End a Prova simulada exactly at the deadline\". It is a child of #318, assigned to ChordanDev, labelled ready-for-agent, jorge:required and wave:3, and has no open blocker (#421, #422 and #364 are closed)." The full prompt adds: branch from `origin/develop`, PR to `develop` with `Refs #318` and `Closes #424`; reuse the #422 `Backend.Stations` guard instead of a parallel one; stay out of level/content assets and `StationRunFlow.cpp` unless required; observe RED before each rule; add one test proving a training's timer behaviour is unchanged; do not run a Jorge review.
- L2: Exploration. Today a simulated exam ends at `deadline_at` but keeps the #256 voice grace (30 s): a reply in flight is still released and stored. The client calls `FinishSession(Timer)` at zero and leaves the room when it returns; a worker `error` event while the run is `Running` invalidates a simulated exam (`LoseVoice`), so a deadline outcome must not reach the worker as `409` before the client's clock ends the run.
- L3: Reuse decision. The #422 guard `ensure_typed_input_allowed/1` is about typed input; the deadline branch reads the session's `mode` inside `Backend.Stations.Conversation` (internal to the context) and adds no new public guard.
- L4: The voice worker suite runs with `unittest` (README), not pytest: there is no pytest dependency.
- L5: Found while testing: a streamed reply the deadline halted could end after the evidence window closed and answer `422 session_completed`. Fix: `Backend.Stations` maps any outcome of a deadline-cut generation to the `kept` receipt.
- L6: Found while reading the client: the worker's fatal `station_time_elapsed` event invalidates a simulated exam whose client clock has not reached zero (`LoseVoice`). Fix kept out of `StationRunFlow.cpp`: past its deadline a silent worker ends its job without the `error` event.
- L7: Unreal specs are characterization tests: the client module needs no change, so no RED was possible there. Ran `ProyectoMed.StationVoice.Unit` (25/25) and `ProyectoMed.StationClient.FakePhoenix` (6/6).
