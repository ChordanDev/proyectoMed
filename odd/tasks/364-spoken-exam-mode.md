# #364 Request exams and impressos aloud: exam mode for the next utterance (server side)

Parent: #326 (tracker), product parent #318. Branch `feat/364-spoken-exam-mode` from `origin/feat/326-production-launch` (1490fdf). Delivery: one PR to `feat/326-production-launch`. Runners: `cd backend && mix test` (MIX_TEST_PARTITION=_issue364), `cd voice-worker && uv run pytest`.

## Specs

- S1 "After pressing the button, the learner's next utterance reaches the impresso route and records an `impresso_requests` event; the patient generation never sees it."
- S2 "Released findings and declined requests show as they do for a typed request."
- S3 "Without pressing the button, an exam request spoken in the dialogue releases nothing (#351 holds)."
- S4 "Approach: an \"exam mode\" for the next utterance, signalled through Phoenix, so the voice worker routes it; the learner token stays without data publishing."
- S5 (task brief) `POST /sessions/:id/exam-mode` (bearer token, session owner) arms the mode for one utterance with a short expiry; disarm after one utterance, on expiry, or on cancel; typed requests unchanged; the transcript goes through `request_impresso` (same matcher/negation) with a stable request id; `request_impresso` itself is not changed (sibling #357).
- S6 (task brief) Document the endpoint and the event the client receives in `docs/unreal-station-client.md`.

Design (decided here, not by the user):
- Phoenix routes: the worker keeps posting every final to `POST /api/internal/voice/sessions/:id/transcripts`; when exam mode is armed, Phoenix consumes it and sends the text to `request_impresso/2` with request id `voice-exam-<turn_id>` instead of admitting a dialogue turn. No learner message is recorded, so no patient generation (now or later) sees it. The turn id is fenced (like a turn-only cancel) so the cursor and `turn_id_floor` move past it; a retry of the same turn replays the same impresso result.
- Exam mode state lives in `Backend.Stations.ExamMode` (ETS table owned by the supervised `MediaSession` process; node-local, like `Conversation`). Default expiry 20 s (`:exam_mode_ttl_ms`).
- The worker answers the receipt `status: "impresso_requested"` by publishing a room event `{role: "examiner", status: "impresso_requested", request_id, decision, newly_released, feedback_message}` and speaks nothing.

## Tasks

- [x] T1 S1 S3 S5: `ExamMode` + `Stations.arm_exam_mode/1`, `cancel_exam_mode/1`; voice turns routed to `request_impresso` while armed; worker receipt `impresso_requested` — inline — `097d7ef`. RED: 13/13 failed (`arm_exam_mode/1` undefined), 3/3 controller tests failed (CaseClauseError). GREEN: 13 + 43 passed; full suite 2377 passed.
- [x] T2 S4 S5 S6: `POST`/`DELETE /sessions/:id/exam-mode` in `SessionController` + router + docs — inline — `98d07f4`. RED: 5/5 failed (no route, 404). GREEN: 25 passed in `session_controller_test.exs`.
- [x] T3 S2 S4 S6: voice worker parses the receipt and publishes the room event; docs of the event — inline — `68197f4`. RED: 3 errors (`VoiceTurnReply` has no `impresso`). GREEN: `uv run python -m unittest` 171 OK.

Route evidence: one understood change per task, ~100-250 lines each; no Writer trigger reason, all inline in this bounded writer.

## Log

- L1 (2026-10-25, workflow brief) Implement #364 server side: exam mode for the learner's next utterance, signalled through Phoenix (`POST /sessions/:id/exam-mode`), worker learns it from Phoenix on its next turn and routes the transcript to `request_impresso`; patient generation never sees it; disarm after one utterance, expiry or cancel; document endpoint and event.
- L2 (2026-10-25) T1-T3 done inline. Credo strict flagged nesting depth in `process_voice_turn`/`stream_voice_turn`; fixed by `f955b63` (refactor, no behavior change).
- L3 (2026-10-25) Checks: local CI (`local_ci.sh`) LOCAL CI PASSED: web 337 + 4 tests, ExUnit 2382 passed, format, compile --warnings-as-errors, credo --strict, dialyzer. Voice worker `uv run python -m unittest`: 171 OK (not part of local CI). GitHub Actions blocked by billing.
- L4 Pending: live check with a real Unreal client and LiveKit room (button -> spoken request -> room event); the Unreal side is owned by the client track. Next step: PR to `feat/326-production-launch`.
