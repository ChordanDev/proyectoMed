# 235 — Keep the learner's message when Jev refuses the patient reply

Issue: #235 (parent #125). Branch `fix/235-keep-learner-turn-on-refusal` from `develop` 8fb1bb6. Worktree `../proyectoMed-235`. PR targets `develop` with `Closes #235`.

## Objective

When patient-reply verification refuses (`{:refused, :low_confidence}` or `{:refused, :semantic_refusal}`), commit the learner turn and drop only the patient reply, so the learner's words reach rubric grading. Technical failures keep today's rollback.

## Why

In the #228 live run, exam verbalization and lab interpretation were addressed to the examiner; Jev correctly refused the patient reply, `rollback_turn` deleted the learner turn, and items 5 and 7 were graded 0.

## Constraints

- #224 no-leak invariant: rejected or unverified patient text is never stored or returned.
- Technical failures (timeouts, provider unavailable, missing credentials) still roll back, so a retry does not duplicate the turn.
- Other API error codes unchanged. Grading code unchanged.
- Backend: `Backend.Stations` stays the public interface; `BackendWeb` stays thin. Web: feature-first under `web/src/features/station/`.

## Tasks

- [x] T1 Backend: on `{:refused, _}` patient verification, commit the learner turn without a patient reply; technical failures roll back. Tests in stations tests, including the kept turn in the rubric evidence pool.
- [ ] T2 API: the refusal keeps `reply_verification_failed` and adds the stored learner turn to the body. Controller tests.
- [ ] T3 Web: on that refusal the bubble stays, the input is cleared, and a pt-BR notice says the message was recorded and the patient did not answer it. Technical-failure path keeps #224 behavior. Tests.
- [ ] T4 Live check on acute-appendicitis (temporary, uncommitted `station_loader.ex` change): exam findings and lab interpretation are graded when the patient reply is refused.

## Routing

- T1–T3: delegated direct (one writer; 2+ non-trivial files across backend and web).
- T4: parent-driven live run with the user.

## Checks

- `cd backend && mix test` (focused, then full), `mix format --check-formatted`, `mix compile --warnings-as-errors`.
- `npm --prefix web test`, `npm --prefix web run typecheck` (or the repo's equivalent), `npm --prefix web run build`.

## Progress

- Created 2026-10-15.
- T1 done (route: delegated writer). Commit `fdeb7c7`. `Backend.Stations.create_message` returns `{:error, {:refused, reason, learner_turn}}` on a refused patient reply; the turn resolves with the new `Conversation.resolve_turn(..., :keep_learner_turn)`. RED: 4 new tests failed (`{:refused, reason}` returned); GREEN: full backend suite 1086 passed. Updated the #224-era contract tests that asserted rollback on refusal.

## Next step

T2.
