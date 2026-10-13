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
- [ ] T1 Merge `origin/develop`, resolve all conflicts, restore green suites, commit the
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

## Next step
T1.
