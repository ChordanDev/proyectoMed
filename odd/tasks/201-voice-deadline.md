# 201 — Voice turns honor the station deadline

Issue: #201 (parent #116). Branch: `feat/201-voice-deadline`, cut from `feat/116-realtime-voice` at `5953935`. Target of the pull request: `feat/116-realtime-voice`.

## Objective

Make the real-time voice turn path take part in the station deadline lifecycle that text turns already follow, with one deadline policy in `Backend.Stations.Conversation`.

## Problem

The deadline from #133 is enforced only in `begin_turn`. The voice path from #119 never reads `deadline_at` and the deadline handler looks only at pending text turns. Observed with `station_duration_ms=200` and `turn_grace_ms=3000` while a text turn was pending at the deadline: text `begin_turn` returned `{:error, :station_time_elapsed}`, `begin_voice_turn` returned `{:ok, :committed, 1}`, `resolve_patient_reply` succeeded, and the final transcript kept the unanswered text message, the late voice message and the late patient reply.

## Evidence map (verified by reading, `5953935`)

- `backend/lib/backend/stations/conversation.ex`: text deadline check `:324-359`; deadline handler `:660-672` and manual `complete` `:404-416` decide on `state.turns` only; grace expiry `:674-686`; `resolve_turn` `:361-383`; tail-only rollback `do_rollback_pending_message` `:911-923`; `pop_last_message` `:961-992`; voice entry `:183-190`, `commit_voice_turn/5` `:702-733`, `resolve_patient_reply/3` `:443-480`; in-flight voice generation lives in the ETS session (`active_generation_id`, `active_voice_turn_id`, `active_generation_message_index`), not in GenServer state.
- `backend/lib/backend/stations.ex`: `process_voice_turn/3` `:659-680` with docstring `:623-627` and spec `:650-658`; `ensure_active` `:786` returns `:completed` before reaching the conversation; `process_voice_reply` else clause `:813-829` turns any unlisted error into `:station_ai_unavailable`.
- `backend/lib/backend_web/controllers/voice_worker_controller.ex`: error table `:123-132`, no catch-all clause; moduledoc `:2-16` documents the internal API. Text maps `:station_time_elapsed` to 409 in `station_controller.ex:133-139`.
- `voice-worker/transcripts.py`: `_request` `:268-289` classifies by status only; every 409 becomes `stale_generation`, which `_do_commit` swallows (`:533-538`); `session_inactive` (403, 404, 410, 422) is the non-retryable end-of-session path (`worker.py:80-89`).
- `README.md:250-291` documents the internal voice API walkthrough.

## Decisions

- **One policy, text parity.** A voice turn that starts at or after `deadline_at`, or on a session completed by the timer, returns `{:error, :station_time_elapsed}` and appends nothing. The check lives in the shared private `commit_voice_turn/5`, so the legacy `commit_voice_turn/3` entry gets it too.
- **Grace for an in-flight voice generation.** When the deadline fires with an active voice generation, the handler defers and arms the same grace window used for a pending text turn. Resolving inside the window appends the reply and then completes with reason `:timer`. At grace expiry the session completes, and a later resolve returns `{:error, :station_time_elapsed}` and appends nothing.
- **Transcript after grace expiry.** The unanswered voice learner message is removed, as the unanswered text learner message already is. The issue asks for the same transcript answer on both paths.
- **Rollback by identity.** Text rollback removes its own learner message wherever it sits, and `active_generation_message_index` is corrected when an earlier message is removed.
- **Worker-facing API.** `409` with `{"error": "station_time_elapsed"}`, the same status and code as the learner API. The worker reads the body code for 409 and maps this one to a non-retryable end of session; any other 409 stays `stale_generation`.
- **Manual completion.** `complete/2` with reason `:timer` follows the deadline handler's decision (see T1b; this reverses the first plan, which left manual completion out). `complete/2` with any other reason keeps deciding on pending text turns only.
- **Voice contract after T1.** `begin_voice_turn/3` and `commit_voice_turn/3` may return `{:error, :station_time_elapsed}`. `resolve_patient_reply/3` returns it only for the generation the deadline cut off (`elapsed_generation_id`), and inside grace returns `{:ok, session}` whose session is already `:completed` with reason `:timer`. A retry of an already admitted turn past the deadline still returns `{:ok, :duplicate}`.
- **Out of scope.** Barge-in and LiveKit room deletion on timer completion belong to #121; a session completed by the deadline handler does not run the voice-room cleanup that `Stations.complete_session/2` runs.

## Scope

Allowed: `backend/lib/backend/stations/conversation.ex`, `backend/lib/backend/stations.ex`, `backend/lib/backend_web/controllers/voice_worker_controller.ex`, their test files, `voice-worker/transcripts.py`, `voice-worker/worker.py`, their tests, `README.md`, this document.

## Tasks

- [x] **T1 — Conversation deadline policy for voice.** Criteria 1, 2, 3, 4. Tests in `backend/test/backend/conversation_test.exs`: voice turn after the deadline; voice generation resolving inside and outside grace; deadline firing with only a voice generation in flight; text rollback with an interleaved voice message. Route: delegated writer (non-trivial module plus tests, reading prepares the write). Evidence: `44e6dce`, 546 changed lines (313 tests). RED observed by the writer: 12 of 13 new tests failed before the implementation. Writer: `mix test` 977 passed, format, `compile --warnings-as-errors` and `credo --strict` clean. Parent spot check: `mix test test/backend/conversation_test.exs`, 76 passed. Assessed tier: medium (`slice_budget_reached`); receipt-driven development off, no native review. No existing test changed.
- [x] **T1b — Client timer finish keeps the voice grace.** Evidence: `74a4f25`, 176 changed lines (87 tests). RED observed by the writer: the three manual `:timer` tests failed because the caller was answered at once. Writer: `mix test` 981 passed, format, `compile --warnings-as-errors` and `credo --strict` clean. Parent spot check: `mix test test/backend/conversation_test.exs`, 80 passed. Assessed tier: medium (`under_budget`). The deadline handler and manual `:timer` completion share `defer_or_complete_timer/3`. Consequence: the HTTP finish with reason `timer` can block up to `turn_grace_ms` with a voice generation in flight, as it already does with a pending text turn; whether the client's HTTP timeout tolerates that was not checked. Task as planned: Added after T1: the learner client calls `finish("timer")` when its countdown ends (`web/src/features/station/hooks/useStation.ts:365`, `:572`), which reaches manual `Conversation.complete/2` through `Stations.complete_session/2` (`stations.ex:118-122`). With a pending text turn that call already defers; with only a voice generation in flight it completes at once, so criterion 2 fails on the ordinary path whenever the client's finish arrives before the server timer. `complete/2` with reason `:timer` must defer for an in-flight voice generation exactly as the deadline handler does. Other reasons stay unchanged. Route: same delegated writer as T1.
- [x] **T2 — Public interface and worker-facing API.** Evidence: `936098e`, 322 changed lines (264 tests). RED observed by the writer: 5 of 8 new tests failed (`:completed` or 422 instead of the deadline outcome, and a `FunctionClauseError` in the controller for a turn past the deadline). Writer: `mix test` 989 passed, format, `compile --warnings-as-errors` and `credo --strict` clean. Assessed tier: medium. No existing test changed. Task as planned: Criteria 5 (backend half), 6. `Backend.Stations` passes `:station_time_elapsed` through from both the entry check and the reply resolve, docstring and spec corrected; controller maps it to 409 `station_time_elapsed`; controller moduledoc and `README.md` document it. Tests in `stations_test.exs` and `voice_worker_controller_test.exs`. Route: delegated writer.
- [x] **T3 — Voice worker end of session.** Evidence: `d70e7e6`, 152 changed lines (135 tests). Distinct failure kind `station_time_elapsed`; `worker.py` unchanged because only `stale_generation` is swallowed. RED observed by the writer: the client test got `stale_generation`, the orchestration test timed out. Writer: `uv run python -m unittest` 120 OK. No existing test changed. Task as planned: Criterion 5 (worker half). `PhoenixClient` maps 409 `station_time_elapsed` to a non-retryable end of session; other 409 responses unchanged. Tests in `voice-worker/test_transcripts.py`. Route: delegated writer.

## Acceptance criteria

The eight criteria of issue #201. Existing text deadline tests pass unchanged. No new code path logs transcript text (criterion 8).

## Checks

- `cd backend && mix test test/backend/conversation_test.exs` (and the other touched test files) during iteration.
- At closure: `cd backend && mix format --check-formatted && mix compile --warnings-as-errors && mix credo --strict && mix test`; `cd voice-worker && uv run python -m unittest`.
- Test-first: observe RED for each new test before the implementation.

## Delivery

Forecast: about 450 authored changed lines across three work-unit commits (T1 about 250, T2 about 130, T3 about 70). Running count after T1: 546, already past the budget, so this feature will be delivered as more than one pull request. Strategy `ask-on-risk`: the chain strategy is still to be asked and is required before any pull request is opened; slice boundaries are the work-unit commits. Receipt-driven development is off for this clone (clone-local), so no native review runs; verification follows the risk tier from `gentle-ai review assess`.

## Progress

- 2026-10-13: worktree `../proyectoMed-201` created and indexed; the worktree has no `backend/deps`, `mix deps.get` is required before any mix command.

- 2026-10-13: T1 (`44e6dce`) and T1b (`74a4f25`) done. Running count 722 authored changed lines.

- 2026-10-13: T2 (`936098e`) and T3 (`d70e7e6`) done. Parent spot check on `d70e7e6`: `mix test` 989 passed, `uv run python -m unittest` 120 OK. Total against `5953935`, excluding `odd/`: 9 files, 1097 insertions, 45 deletions.

## Known gaps

- **Provider failure after the timer completed the session.** `process_voice_reply` answers `:completed` (422 `session_completed`), not `:station_time_elapsed`, because `Conversation.fail_generation/3` returns `:completed` there. The worker still ends the session through `session_inactive`. Not fixed.
- **Learner finish request can outlast the web client timeout.** The web API client applies 15 s to every request (`web/src/features/station/api/client.ts:492`), while a finish with reason `timer` can wait up to `turn_grace_ms` (30 s default) for a pending text turn (already the case before this issue) or, since T1b, an in-flight voice generation. The client then shows its generic error although the server completes the session at grace expiry. Not fixed; web code is outside this issue.
- **Voice-room cleanup** does not run when the deadline handler completes the session (#121).

## Slices

Chain strategy: feature-branch chain onto `feat/116-realtime-voice`, the pattern used for #120 and #128; each slice targets the previous slice's branch and they merge in order. Authorized by the user on 2026-10-13 (push and pull requests).

1. `feat/201-conversation-deadline` -> `feat/116-realtime-voice`: `b2b8116`, `44e6dce`, `74a4f25`, `76db730`. Conversation deadline policy for voice (T1, T1b). 668 changed lines outside `odd/`, 400 of them tests; size exception requested because T1b closes a hole in T1 and the policy is one unit.
2. `feat/201-voice-deadline` -> `feat/201-conversation-deadline`: `936098e`, `d70e7e6` and the documentation commits. Worker-facing contract and its consumer (T2, T3). 474 changed lines, 399 of them tests; kept together because the backend status and the worker's handling of it are one contract.
3. `feat/116-voice-jev-parity` -> `feat/201-voice-deadline`: separate change (Refs #116), stacked here only because it edits the same function.

## Next step

Review and merge the slices in order; then update the parent pull request #151.
