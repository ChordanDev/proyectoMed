# 271 — Speak the patient reply sentence by sentence

Issue: #271 (parent #237). Branch: `feat/271-sentence-streaming` from `feat/237-clinician-demo-readiness`.

## Objective

In real-time voice, start speaking the patient reply as soon as its first
sentence is generated and verified, instead of after the whole reply is
generated and verified.

## Why

The 2026-10-20 rehearsal measured 1.3–2.1 s of server time per normal turn,
75–80% of it generation. Nothing is spoken until the whole reply is generated
and verified, so the learner waits for all of it.

## Scope

- Real-time voice path only: `Stations.stream_voice_turn/5` → `VoiceWorkerController`
  → Python worker. The text path and `process_voice_turn/3` keep whole-reply verification.
- Anthropic Messages API streaming (SSE) through raw Req (`into:`), keeping the
  #272 cached system block and the patient's `between_tools` thinking / `low` effort.
- Per-sentence Jev verification with the full conversation plus the already
  verified sentences of the same reply (the cumulative reply is verified).
- Sentence channel Phoenix → worker: the transcript POST answers with a chunked
  NDJSON body when the worker sends `Accept: application/x-ndjson`
  (one `sentence` line per verified sentence, then one `result` or `error` line).
  Same route, same bearer auth (`VOICE_WORKER_SECRET`); an older worker that
  does not ask for NDJSON keeps the single JSON reply.

## Constraints

- ADR-011: nothing unverified is spoken, stored, published or logged.
- First refused sentence stops the reply; the spoken verified sentences are the
  stored patient turn. Nothing spoken → #256/#269 kept-turn rules; the single
  regeneration happens only when the first sentence is refused (nothing spoken).
- Stage directions stripped per sentence for speech, kept in the stored text.
- Latency logs without content: end of learner speech → first audio (worker),
  per-sentence generation and verification ms (server).
- No live calls in tests.

## Tasks

| ID | Task | Route | Status |
|----|------|-------|--------|
| T1 | Sentence splitter + Anthropic SSE streaming client + `stream_reply` adapter callback | delegated direct (this writer) | [x] |
| T2 | `SentenceStream` orchestrator + `Stations.stream_voice_turn/5` (verify per sentence, stop on refusal, store spoken, kept rules, latency logs) | delegated direct (this writer) | [x] |
| T3 | `VoiceWorkerController` NDJSON sentence channel | delegated direct (this writer) | [x] |
| T4 | Worker: stream sentences from Phoenix, speak them in order, first-audio latency log, docs | delegated direct (this writer) | [ ] |

Route evidence: the parent delegated all four tasks to one bounded writer (2+ non-trivial files).

## Acceptance criteria

- With a stubbed streaming client and verifier, the first sentence is handed to TTS before generation ends (tested).
- A refused second sentence: the first is spoken and stored, nothing after it is (tested).
- No unverified text reaches the worker, the transcript or the logs (tested).
- Live check: time to first audio reported, target under 1.5 s after end of speech (pending, needs a live run).

## Checks

- `cd backend && mix test` (focused per task), `mix format --check-formatted`, `mix compile --warnings-as-errors`.
- `cd voice-worker && uv sync && uv run python -m unittest`.
- Local CI script (mirrors `.github/workflows/pr-validation.yml`; GitHub Actions is blocked by billing).

## Progress

- T1: RED 16 new tests failing (splitter undefined, `stream_message/3`, `stream_reply/4` undefined); one splitter expectation corrected (an ellipsis run ends a sentence by design). GREEN `mix test test/backend/station_ai` 77/77; `mix compile --warnings-as-errors` clean. Commit: see git log (`feat(stations): stream patient replies from the Messages API`).

- T2: RED 14/14 new tests failing (`stream_voice_turn/5` undefined); one GREEN-phase bug found by the tests (a duplicate turn matched the generation-id clause) and fixed. GREEN `mix test` 1508/1508 (14 new); `mix compile --warnings-as-errors` clean. Design notes: the candidate verified for sentence N is the reply so far (sentences 0..N), with the full conversation; the gate's regeneration runs only for sentence 0 (`can_retry?: false` afterwards); a turn cancelled mid-reply stores nothing (Conversation's generation fence) — see follow-ups.

- T3: RED 5/5 new controller tests failing (no NDJSON channel). Found during GREEN: the `:api` pipeline only accepts JSON, so the worker sends `Accept: application/x-ndjson, application/json`. GREEN controller suite 31/31, full `mix test` green, format and warnings clean.

## Next step

T4.
