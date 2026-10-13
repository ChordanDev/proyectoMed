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
- **Out of scope.** Manual `complete/2` keeps deciding on pending text turns only (criterion 3 names the deadline handler). Barge-in and LiveKit room deletion on timer completion belong to #121.

## Scope

Allowed: `backend/lib/backend/stations/conversation.ex`, `backend/lib/backend/stations.ex`, `backend/lib/backend_web/controllers/voice_worker_controller.ex`, their test files, `voice-worker/transcripts.py`, `voice-worker/worker.py`, their tests, `README.md`, this document.

## Tasks

- [ ] **T1 — Conversation deadline policy for voice.** Criteria 1, 2, 3, 4. Tests in `backend/test/backend/conversation_test.exs`: voice turn after the deadline; voice generation resolving inside and outside grace; deadline firing with only a voice generation in flight; text rollback with an interleaved voice message. Route: delegated writer (non-trivial module plus tests, reading prepares the write).
- [ ] **T2 — Public interface and worker-facing API.** Criteria 5 (backend half), 6. `Backend.Stations` passes `:station_time_elapsed` through from both the entry check and the reply resolve, docstring and spec corrected; controller maps it to 409 `station_time_elapsed`; controller moduledoc and `README.md` document it. Tests in `stations_test.exs` and `voice_worker_controller_test.exs`. Route: delegated writer.
- [ ] **T3 — Voice worker end of session.** Criterion 5 (worker half). `PhoenixClient` maps 409 `station_time_elapsed` to a non-retryable end of session; other 409 responses unchanged. Tests in `voice-worker/test_transcripts.py`. Route: delegated writer.

## Acceptance criteria

The eight criteria of issue #201. Existing text deadline tests pass unchanged. No new code path logs transcript text (criterion 8).

## Checks

- `cd backend && mix test test/backend/conversation_test.exs` (and the other touched test files) during iteration.
- At closure: `cd backend && mix format --check-formatted && mix compile --warnings-as-errors && mix credo --strict && mix test`; `cd voice-worker && uv run python -m unittest`.
- Test-first: observe RED for each new test before the implementation.

## Delivery

Forecast: about 450 authored changed lines across three work-unit commits (T1 about 250, T2 about 130, T3 about 70). Strategy `ask-on-risk`: the chain strategy is asked before any pull request is opened. Receipt-driven development is off for this clone (clone-local), so no native review runs; verification follows the risk tier from `gentle-ai review assess`.

## Progress

- 2026-10-13: worktree `../proyectoMed-201` created and indexed; the worktree has no `backend/deps`, `mix deps.get` is required before any mix command.

## Next step

T1.
