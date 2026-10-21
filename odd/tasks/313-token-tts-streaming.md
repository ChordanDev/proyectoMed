# #313 Stream patient text to ElevenLabs as it is generated, and measure the gain

Parent: #237. Branch `feat/313-token-tts-streaming` (from `origin/feat/237-clinician-demo-readiness`, 1aebedf).

## Objective

Lower the time from the end of learner speech to the first patient audio by
feeding the patient reply to ElevenLabs word by word as Claude generates it
(`VOICE_TTS_STREAMING=token`), instead of one verified sentence at a time
(`sentence`, the #271 behaviour and the default), and measure both modes with
the same per-stage marks.

## Why

Patient replies are one or two short sentences, so in sentence mode the learner
waits for (almost) the whole reply before any audio. The user prefers fluency
and asked to try word-level streaming and measure the gain.

## Scope

- Per-stage timing marks, content-free, emitted the same way in both modes:
  Phoenix (turn start, first model token, addressee marker parsed, first text
  handed to the worker) and worker (end of learner speech, first text received,
  first text pushed to TTS, first audio frame).
- `VOICE_TTS_STREAMING=token|sentence` (Phoenix, validated in `runtime.exs`,
  default `sentence`). The worker opts in per request (`deltas: true`); Phoenix
  sends deltas only when both agree.
- Token mode: after the `[PACIENTE]` marker, Phoenix pushes word-aligned,
  stage-direction-free text deltas (`delta` NDJSON lines), each checked first by
  `BoundedReply` on the accumulated text. A violation sends `abort`, and the
  existing regenerate-once/refusal path runs. Sentence lines are still sent for
  the transcript.
- Worker token mode: an ElevenLabs streaming-input TTS stream per generation
  (`elevenlabs.TTS.stream()`, `auto_mode=False`, word tokenizer, short chunk
  schedule), fed by deltas; `abort` stops playback at once; barge-in as today.
- A scripted comparison (real Claude + real ElevenLabs, own Phoenix on a free
  port) with per-stage medians, recorded in `docs/design/token-tts-streaming.md`.

## Constraints

- Never log transcript or reply text; marks are identifiers and milliseconds.
- Never synthesize the marker or anything of an examiner turn.
- `blocking` verification keeps sentence mode (deltas would be spoken before Jev).
- Sentence mode unchanged; existing tests green.
- Never touch ports 4000/4001/5173/7880 or the main checkout.

## Checklist

- [ ] T1 Phoenix per-turn timing line (turn start, first token, marker, first text) — route: inline (2 files, understood)
- [ ] T2 Worker per-turn timing line (speech end, first text, first TTS push, first audio) — route: inline
- [ ] T3 Phoenix token mode: config, `SpeechDeltas`, `SentenceStream` delta hook with BoundedReply abort, controller `delta`/`abort` lines — route: inline
- [ ] T4 Worker token mode: client `delta`/`abort` parsing, streamed TTS per generation, abort and barge-in — route: inline
- [ ] T5 Scripted live comparison and design note — route: inline

Route note: this worker is itself the delegated writer for #313; tasks run inline here.

## Acceptance criteria

- Timing marks logged for both modes (tested where deterministic).
- Token mode: deltas reach the TTS stream before the first sentence completes;
  the marker is never synthesized; examiner turns synthesize nothing (stubs on
  both sides).
- Token mode: a BoundedReply violation mid-stream stops audio and follows the
  refusal path (tested).
- Sentence mode unchanged.
- Comparison table (sentence vs token) with per-stage medians in the PR.

## Checks

- `cd backend && mix test` (focused files per task, full at close)
- `cd voice-worker && uv run python -m unittest`
- Local CI script (`LOCAL CI PASSED`)

## Progress

(updated per task)

## Next step

T1.
