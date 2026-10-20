# 294 - Classify the addressee in parallel with the patient generation

Issue: #294 (parent #237). Branch: `perf/294-parallel-addressee` from `feat/237-clinician-demo-readiness`.

## Objective

Start the patient generation concurrently with the Jev turn-addressee check
(`turn_addressee`, #274) instead of after it. An examiner decision cancels the
generation and acknowledges the turn as today; a patient or undecided decision
(or a failed check) keeps the generation that is already running.

## Why

In the 2026-10-20 rehearsal the addressee check took 0.2-0.7 s and ran before a
1.0-2.6 s patient generation, so every patient-addressed voice turn paid the
check on top of the generation.

## Constraints

- Nothing from a cancelled generation is verified, handed over, spoken,
  committed or logged as a reply; no `verified_fact_ids` are recorded for it
  (#274, #286 kept-learner-turn rules).
- Conversation turn ownership is unchanged: only the matching generation/token
  resolves the turn.
- The addressee check keeps its own deadline and fail-open rule (failure or
  undecided is patient-addressed).
- `Backend.Stations` stays the only public interface; `BackendWeb` unchanged.

## Tasks

- [x] T1 Streamed voice turn (`stream_voice_turn/5`): run the check in a task
  while `SentenceStream` generates; gate the first sentence verification (or
  the end of a stream without sentences) on the decision; examiner cancels the
  generation and keeps the learner turn. Update `docs/design/turn-addressee.md`.
- [ ] T2 Non-streamed voice (`process_voice_turn/3`) and text
  (`create_message/2`) turns: run the generation in a task concurrently with the
  check; examiner shuts the generation down and acknowledges.

## Routing

- T1: delegated direct (this writer), 2+ non-trivial files.
- T2: delegated direct (this writer).

## Checks

- Focused: `mix test test/backend/stations/turn_addressee_test.exs test/backend/stations/voice_sentence_stream_test.exs`.
- Full: local CI script (`LOCAL CI PASSED`).
- Live check of the overlap in `voice_sentence` / `turn_addressee` logs: optional, pending a human run.

## Progress

- Created feature document.
- T1 done. RED: `turn_addressee_test.exs` 10/12 (examiner streamed turn never
  started a generation; first sentence after 803 ms with 400 ms check + 400 ms
  generation stubs). GREEN: 12/12; focused addressee + stream + multiturn files
  33/33; full `mix test` 1573/1573. Commit: see T2 entry (recorded after commit).

## Next step

T2 RED test.
