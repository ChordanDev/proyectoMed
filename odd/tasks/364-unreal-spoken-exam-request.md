# #364 Request exams and impressos aloud in the Unreal client

Objective: in a voice run the learner presses "Exames", then says the request; the spoken request goes to the impresso request, never to the patient, and shows as a typed request does.
Branch: `feat/364-exam-mode-voice` from `develop` (6f82902). Delivery: ask-on-risk. Runners: `cd backend && mix test`; `scripts/run-unreal-tests.sh` (unit specs), voice specs inside `scripts/run-voice-stack.sh`.

## Specs

Acceptance criteria of #364, verbatim:

- S1 "After pressing the button, the learner's next utterance reaches the impresso route and records an `impresso_requests` event; the patient generation never sees it."
- S2 "Released findings and declined requests show as they do for a typed request."
- S3 "Without pressing the button, an exam request spoken in the dialogue releases nothing (#351 holds)."
- S4 "Approach: an \"exam mode\" for the next utterance, signalled through Phoenix, so the voice worker routes it; the learner token stays without data publishing."

Server side (Phoenix route, worker routing and room event) is done in PR #396 and is in `develop`. Derived decisions:

- S5 (parent session, 2026-10-28) The Unreal client has no device login and calls only the deprecated `/api/stations/active/sessions/...` routes, while `exam-mode` exists only under `/sessions/:id` (device token required). Add `POST`/`DELETE /api/stations/active/sessions/:id/exam-mode` to the deprecated scope with the same `limit_session_exam_mode` limiter, reusing `SessionController.arm_exam_mode/cancel_exam_mode`, with controller tests for both routes. Every Unreal call moves to `/sessions/:id` together once Unreal has device login.
- S6 `UStationClient` arms and cancels the exam mode; `ParseStationVoiceEvent` reads the `impresso_requested` examiner event.
- S7 `UStationRunFlow`: in a voice run with the voice link up, the "Exames" panel arms the exam mode for the next utterance. That utterance shows in the exam panel, not in the conversation; its outcome joins the exam requests as a typed request's does, and the released impressos are read again with `ListImpressos`. An `impresso_requested` turn is an outcome, so a newer turn never drops it (#193). When Phoenix treats the utterance as a dialogue turn after all (the mode expired), its learner line joins the conversation before the reply.
- S8 The mode ends locally on the outcome, at `expires_at` and when the learner cancels it (`DELETE`).

## Tasks

| ID | Specs | Route | Status | Commit / evidence |
|----|-------|-------|--------|-------------------|
| T1 | S5 | inline | done | 18304e3; RED 4 controller/limit/auth tests (404), GREEN 57/57 |
| T2 | S6 | inline | done | RED 4 client/voice specs on stubs, GREEN 117/117 (see L5) |
| T3 | S1, S2, S3, S7, S8 | inline | done | RED 5 flow specs on stubs, GREEN 117/117 (see L5) |
| T4 | S1-S3 by eye (human) | human | pending | |

- T1 Phoenix: deprecated aliases of the exam-mode routes, tests, docs.
- T2 Station client: `ArmExamMode`, `CancelExamMode`, the `impresso_requested` voice event; client specs.
- T3 Run flow and HUD: the spoken exam request; unit specs.
- T4 By-eye check in the editor with the voice stack.

## Log

- L1 (2026-10-28, parent session brief): "Implement issue #364 of ChordanDev/proyectoMed: \"Request exams and impressos aloud: press \"Exames\", then say the request\". [...] what remains is most likely the Unreal client: the \"Exames\" button arms exam mode through Phoenix, the next utterance shows as an impresso request with released findings or a declined request exactly as a typed request shows (#194), and an exam request spoken without the button releases nothing (#351). The learner token stays without data publishing. Implement on the `/sessions/:id/...` routes, as the issue's note says."
- L2 (2026-10-28): mapped. Server side in develop (router.ex:129-132, voice_worker_controller.ex:172, worker.py `_publish_impresso`). `StationClient.cpp:14` uses only `/api/stations/active/sessions`, with no `Authorization` header; `/sessions/:id` runs `DeviceAuth` with no dev bypass, so an Unreal call there answers `401 missing_token`.
- L3 (2026-10-28, parent session): "Go with A. [...] Add POST/DELETE `/api/stations/active/sessions/:id/exam-mode` to the legacy scope with the same `limit_session_exam_mode` limiter, reusing `SessionController.arm_exam_mode/cancel_exam_mode`, plus controller tests for both routes. In the PR and in #364, note that every Unreal call migrates to `/sessions/:id` together once Unreal has device login."
- L4 (2026-10-28): T1. Alias added to the deprecated scope with `limit_session_exam_mode`. The alias rate-limit tests are now named by method too, since POST and DELETE share a path.
- L5 (2026-10-28): T2+T3. Stubs first: `StationClient+StationVoice.Unit+StationRun.Unit+StationRun.Phoenix` 108/117, the 9 new behaviour specs failing; then GREEN 117/117 against a scripted Phoenix on port 4364 (the #325 session shares the machine). One fix in the spec itself: Phoenix reads its clock again for `server_now`, so `expires_at - server_now` is just under 20 s. Design: opening "Exames" in a voice training arms the mode and closing it unused cancels it; the utterance that takes the mode is held out of the conversation (`SpokenExamText`) and shown as "Você solicitou: ... (solicitando...)"; an `ExaminerImpresso` outcome joins `ExamRequests` and reloads `ListImpressos`; any dialogue outcome on that turn puts the held line in the conversation first; a superseded exam turn passes the mode to the next utterance and reloads the impressos. Later refactor: `DisarmSpokenExam` replaces a cancel path that faked an expiry; covered by a new Phoenix spec (no RED: refactor guard).
- L6 (2026-10-28): PR #414 opened against develop. Open product question found after opening it: Engram decision of 2026-10-22 says exam requests "stay typed (button + text, as #354 built) in trainings" and the spoken version is for the prova simulada (#318), which the Unreal client does not have yet. T3 arms the mode when "Exames" opens in a voice training, which changes that training. Waiting for the user before review and the by-eye check. RDD: assess `high` (auth test path), consent envelope not yet relayed.
