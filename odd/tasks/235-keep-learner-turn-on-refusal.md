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
- [x] T2 API: the refusal keeps `reply_verification_failed` and adds the stored learner turn to the body. Controller tests.
- [x] T3 Web: on that refusal the bubble stays, the input is cleared, and a pt-BR notice says the message was recorded and the patient did not answer it. Technical-failure path keeps #224 behavior. Tests.
- [x] T4 Live check on acute-appendicitis (temporary, uncommitted `station_loader.ex` change): exam findings and lab interpretation are graded when the patient reply is refused.

## Routing

- T1–T3: delegated direct (one writer; 2+ non-trivial files across backend and web).
- T4: parent-driven live run with the user.

## Checks

- `cd backend && mix test` (focused, then full), `mix format --check-formatted`, `mix compile --warnings-as-errors`.
- `npm --prefix web test`, `npm --prefix web run typecheck` (or the repo's equivalent), `npm --prefix web run build`.

## Progress

- Created 2026-10-15.
- T1 done (route: delegated writer). Commit `fdeb7c7`. `Backend.Stations.create_message` returns `{:error, {:refused, reason, learner_turn}}` on a refused patient reply; the turn resolves with the new `Conversation.resolve_turn(..., :keep_learner_turn)`. RED: 4 new tests failed (`{:refused, reason}` returned); GREEN: full backend suite 1086 passed. Updated the #224-era contract tests that asserted rollback on refusal.
- T2 done (route: delegated writer). Commit `9155d49`. Refusal body: `{"error": "reply_verification_failed", "message": ..., "learner_turn": {"role", "modality", "text", "at"}}`, HTTP 502. RED: 2 controller tests failed (no `learner_turn`); GREEN: full backend suite 1086 passed.

- T3 done (route: delegated writer). Commit `13acb97`. `ApiError.learnerTurn` decodes `learner_turn`; `keptLearnerTurnNotice` in `useStation.ts` selects the kept-turn path; `StationScreen.sendTurn` keeps the bubble, leaves the input empty, and shows `learnerTurnKeptNotice` ("Sua mensagem foi registrada, mas o paciente não respondeu a ela."). RED: 7 new web tests failed; GREEN: web suite 196 passed, typecheck, lint and build clean; backend suite 1086 passed.

- T4 done (route: parent-driven live run, 2026-10-19, `JEV_ADAPTER=typesafe RUBRIC_RESOLVER=openai`, acute-appendicitis via a temporary uncommitted `station_loader.ex` change, reverted afterwards). Three patient replies were refused and their learner turns kept: an anamnesis question (`semantic_refusal`, HTTP 502 with `learner_turn`), the exam authorization, and the verbalized exam findings. The UI kept the bubble, cleared the input, and showed the pt-BR notice; no patient text appeared. Result 9.6/10, 11/11 assessed: item 5 scored 1.2/1.2 citing the kept authorization and findings turns; item 7 scored 0.8/0.8 citing the lab interpretation (in #228 both were 0).
- Follow-ups observed, out of scope: `semantic_refusal` with every `risk:*` at `no` and only an undecided `fact_stated` (possible over-refusal); impresso requests match keywords exactly ("exame físico abdominal" was not recognized); some criteria cite an unrelated evidence turn (items 7 and 10 also cite "O que o trouxe aqui hoje?"); item 2 scored 0.4 because migration and duration were volunteered by the patient, not asked by the learner.

## Next step

Open the PR to `develop` (`Closes #235`) when the maintainer asks.
