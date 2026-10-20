# 281 — Render sentence-streamed voice replies in the station transcript

Issue: #281 (parent tracker #237). Branch: `fix/281-voice-segment-rendering`, PR to
`feat/237-clinician-demo-readiness`.

## Objective

Show a sentence-streamed voice reply (#271) as one patient bubble that grows sentence by
sentence, and reconcile it with the stored reply only once the turn has ended.

## Problem and why

#271 publishes one `role: "patient"` event per verified sentence, each with a `segment`
index. #270's web transcript resolves a voice turn on the first patient event, locks it
in `voiceResolvedRef` and reads `GET /sessions/:id` right away. With both merged the
transcript shows only the first sentence, or a stored reply read before the whole reply
was stored. The worker publishes no end-of-turn signal for a streamed reply.

## Scope

- Worker: publish a content-free end-of-turn event once Phoenix settles a streamed reply.
- Web: parse `segment` and the end event; render segments of one turn as one growing
  bubble (in `segment` order, duplicates and out-of-order tolerated); reconcile with the
  stored reply only on the end event.
- Keep #270 behavior: kept turns ("Anotado."), failures, interim captions, barge-in.
- PR #280 follow-up (C2): a turn whose reply could not be delivered keeps its learner line.

## Constraints

- Feature-first: changes stay in `web/src/features/station/`.
- Never log transcripts or patient text; the end event carries no text.
- Learner-facing copy in pt-BR; artifacts in English.
- Stay focused on voice segment handling (#274 edits StationScreen in parallel).

## Checklist

- [x] T1 — Worker: end-of-turn event `{"session_id", "turn_id", "generation_id", "role": "patient", "status": "complete"}` after a streamed reply settles; README event table. Route: inline (worker files already mapped). Checks: `uv run python -m unittest`.
- [ ] T2 — Web: parse `segment` and the end event; one growing bubble per turn; reconcile on the end event; delivery failure keeps the learner line. Route: inline (station feature files already mapped). Checks: `npm --prefix web test`, typecheck.
- [ ] T3 — Local CI (`local_ci.sh`) and PR.

## Acceptance criteria

- Three sentence events for one turn render one patient bubble with the three sentences in
  order, followed by reconciliation with the stored text (tested).
- Duplicate and out-of-order segments are handled (tested).
- A kept turn still shows "Anotado.", and a delivery failure keeps the learner line (tested).
- Live check (pending, needs LiveKit/Deepgram/ElevenLabs/Jev): multi-sentence replies
  appear complete during the spoken rehearsal.

## Progress

- T1: `PatientVoice.on_turn_end` publishes the end event; `TurnManager`/`process_speech_stream`
  take `on_turn_end`, called only when a streamed reply is accepted. A rejected end event is
  logged content-free (no failure event: the sentences were delivered). RED: 3 of the 5 new
  tests failed (149 run). GREEN: 149/149 `uv run python -m unittest`. Commit: see git log
  (`feat(voice-worker): announce the end of a streamed reply`).

## Next step

T2.
