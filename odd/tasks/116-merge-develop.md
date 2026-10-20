# #116 Merge `develop` into `feat/116-realtime-voice`

## Objective
Bring `develop` (`6e855eb`) into the real-time voice parent branch (`c1591b8`) so the
voice path runs on top of the current domain code, including the Jev verification
boundary (#127), and the parent PR #151 becomes mergeable again.

## Problem
The branches diverged: `develop` is 150 commits ahead and the voice branch 70. A trial
merge conflicts in 12 files (29 hunks). On the voice branch
`Backend.Stations.verify_patient_reply/3` is a pass-through stub, so voice replies are
not verified by Jev.

## Why this approach
- A merge (not a rebase) keeps the already reviewed child merges (#150, #155, #163-#166,
  #184, #185, #199) intact and matches how the parent branch has been built.
- The repository requires changes to enter through a pull request, so the merge is done
  on `chore/116-merge-develop` and proposed to `feat/116-realtime-voice`.
- This is an integration, not a redesign: each conflict is resolved by keeping both
  sides' behaviour. No new product behaviour is introduced.

## Scope
- Resolve the 12 conflicted files:
  - `backend/config/runtime.exs`
  - `backend/lib/backend/stations.ex`
  - `backend/lib/backend/stations/conversation.ex`
  - `backend/test/backend/architecture_test.exs`
  - `backend/test/backend/conversation_test.exs`
  - `backend/test/backend/stations_test.exs`
  - `web/src/App.tsx`
  - `web/src/features/station/api/client.test.ts`
  - `web/src/features/station/api/client.ts`
  - `web/src/features/station/hooks/useStation.ts`
  - `web/src/features/station/i18n/pt-BR.json`
  - `web/src/features/station/index.ts`
- Fix any semantic break that the merge causes in files that merged without textual
  conflict (compile errors, failing tests, type errors).
- Voice replies must go through the real `verify_patient_reply` from `develop`, not the
  stub.

## Out of scope
- Relaxing `admit_voice_reply/2` (canonical refusal or exact package fact). Whether the
  voice path may speak Jev-verified paraphrases is a product decision, reported back and
  not changed here.
- #121 (barge-in during playback, learner-facing rendering, realism validation).
- Any refactor not required to make the merged tree compile and pass.

## Constraints
- Preserve the invariants in `AGENTS.md`: `Backend.Stations` is the only public context
  interface, `BackendWeb` stays thin, web dependency flow `app -> features -> shared`.
- Preserve from the voice branch: voice turn generations and cancellation in
  `Conversation`, the worker API, bounded voice replies, the LiveKit media session.
- Preserve from `develop`: Jev verification, educational results v2, rubric evaluation,
  impressos, station deadline, session discard.
- Text, audio and provider payloads are never logged.

## TDD
A merge has no meaningful RED step. Verification is the full existing suites on the
merged tree; a test is added only where a resolution needs behaviour neither side
covered.

## Tasks
- [x] T1 Merge `origin/develop`, resolve all conflicts, restore green suites, commit the
  merge. Route: delegated (writer trigger: 12 non-trivial files; preparation reading of
  both sides).

## Checks
- `cd backend && mix precommit`
- `cd backend && mix credo --strict` and `mix dialyzer --format short`
- `npm --prefix web run typecheck`, `npm --prefix web run lint`, `npm --prefix web test`
- `bash scripts/test.sh`
- `cd voice-worker && uv run python -m unittest` (115 expected)

## Delivery
- Branch `chore/116-merge-develop` from `feat/116-realtime-voice`; one PR to
  `feat/116-realtime-voice` with `Refs #116`. A merge commit is one work unit and is not
  sliced by size. Push and PR creation are the user's decision.
- RDD: off for this clone; ordinary checks only.

## Progress / evidence
- Worktree `../proyectoMed-116-sync`; trial merge: 12 conflicted files, 29 hunks, 141
  files staged cleanly from `develop`.

- T1 done in merge commit `38ab34b` (parents `7af554c`, `6e855eb`). All 12 conflicted
  files resolved keeping both sides; no separate follow-up commit.

### Resolution decisions
- `stations.ex`: one `verify_patient_reply/3`, `develop`'s Jev gate; the voice stub is
  gone. `process_voice_reply` calls it with `build_verify_opts(package, session,
  context, %{})`, the same options as the text path (conversation, case state,
  regeneration generator, default Jev deadline). The return shape is unchanged for the
  voice caller (a map carrying `:text`).
- Jev rejection (`{:refused, _}`, `{:denied, _}`), `:timeout` and an unavailable
  adapter take the existing voice failure path: `Conversation.fail_generation/3` and
  `{:error, :station_ai_unavailable}`. The text path releases no patient text on those
  outcomes (it rolls the turn back and returns an error; it never substitutes the
  canonical refusal), so the voice path mirrors that instead of speaking a refusal.
- `admit_voice_reply/2` is untouched.
- `complete_session/2`: `develop`'s timer deadline guard plus the voice branch's
  best-effort LiveKit room cleanup on every successful completion.
- `conversation.ex`: sessions carry impresso and voice generation fields; voice
  generation state is cleared in `complete_now/2`, where `develop` moved completion;
  all handlers from both sides kept.
- `runtime.exs`, `architecture_test.exs`, web client, feature index, `pt-BR.json`:
  union of both sides.
- `conversation_test.exs`: `Conversation` aliases `Backend.Stations.Conversation` (voice
  branch), `StationConversation` is kept for `develop`'s tests and `LegacyConversation`
  for the delegate test. `develop`'s tests that used the legacy alias now call the real
  module directly.
- `useStation.ts`: `sessionId` is exposed next to `develop`'s state; set on start and on
  resume, cleared on failure, reset and pagehide discard.
- `App.tsx`: `develop`'s notice -> station -> result flow, with `VoicePanel` mounted in
  the active state when audio consent was given. `StationSession` stays exported and
  tested but is no longer rendered by `App`.

### Non-conflicted files fixed
- `backend/test/backend_web/controllers/voice_worker_controller_test.exs`: configures a
  verifying Jev adapter (7 tests returned 503 because the default adapter fails closed).
- `backend/test/backend/stations_test.exs`: two new tests (voice turn reaches Jev; Jev
  rejection or unavailability fails the generation without text).
- `web/src/features/station/hooks/useStation.test.ts`: one new test (resumed session
  exposes `sessionId`, cleared after reset).
- `README.md`: the voice manual test states that Jev fails closed by default.

### Checks observed on `38ab34b`
- `mix precommit`: 964 passed, exit 0.
- `mix credo --strict`: no issues.
- `mix dialyzer --format short`: 0 errors, passed.
- `npm --prefix web run typecheck`: clean.
- `npm --prefix web run lint`: clean.
- `npm --prefix web test`: 11 files, 201 tests passed.
- `bash scripts/test.sh`: exit 0 (web unit 197, backend 964, E2E 4 passed).
- `uv run python -m unittest` in `voice-worker/`: 115 tests OK.

### Open points for the parent
- The default Jev adapter is `DisabledAdapter`, so outside tests and the E2E-only
  approving adapter every voice turn now fails with `station_ai_unavailable`, exactly
  like the text path on `develop`.
- The timer auto-completion inside `Conversation` does not delete the LiveKit room;
  only `complete_session/2` and `discard_session/1` do.
- Voice turns are not subject to `develop`'s `deadline_at` admission check; they stop
  once the deadline timer completes the session.
- `App` now shows both `StationScreen`'s push-to-talk voice and the LiveKit
  `VoicePanel` under audio consent. The `App` wiring has no test of its own
  (`web/src/App.test.tsx` was outside the allowed edit surface).

### Independent verification (2026-10-13, on `89ae637`)
- Verdict: sound with notes. No regression from the resolution: the merged public and
  private function sets, `GenServer` clauses, exports, client methods and `pt-BR.json`
  keys equal the union of both parents; no test from either side was dropped.
- Re-run by the verifier: `mix compile --warnings-as-errors`, `mix test` (964 passed),
  `mix format --check-formatted`, web typecheck, lint and tests (201 passed), worker
  unit tests (115 passed). The parent re-ran `mix test`: 964 passed.
- Cross-feature gaps the merge exposes (not regressions; neither parent covered them):
  - Voice turns bypass the `deadline_at` admission check. Reproduced: with a text turn
    pending when the deadline fires, `begin_turn` returns `:station_time_elapsed` but
    `begin_voice_turn` still commits and `resolve_patient_reply` succeeds.
  - A text turn's rollback is skipped when a voice message was appended after it, so
    the unanswered text message stays in the transcript.
  - An in-flight voice generation gets no grace at the deadline, unlike a text turn.
  - Jev adds up to 3 s plus one regeneration to a voice turn, against the worker's 5 s
    HTTP timeout; not measured.
  - `StationSession` is exported and tested but no longer rendered by `App`.

## Next step
Open the PR to `feat/116-realtime-voice` (user decision). Track the gaps above as
follow-up issues before the voice prototype is enabled.
