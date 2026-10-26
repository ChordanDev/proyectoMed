# 357 Unavailable impresso wording

Objective: answer an `unavailable` impresso request as the Revalida examiner does ("Considere solicitado." / "Não consta no script."), classified by Jev and mapped to fixed texts in code.
Branch: `feat/357-unavailable-impresso-wording` (base `feat/326-production-launch`). Delivery: single PR to the launch branch. Runner: `mix test` (backend, local Postgres, `MIX_TEST_PARTITION=_issue357`).

## Specs

- S1 Only an `unavailable` request is classified. `released` and `already_released` do not change, never call Jev, and the matcher does not change.
- S2 Jev decides, as a constrained classification over the case and the request text (`plausible` or `not_plausible`). Code maps the label to one of the two fixed texts; the model never writes the text the learner reads.
- S3 `plausible` → `feedback_message: "Considere solicitado."`; `not_plausible` → `feedback_message: "Não consta no script."`.
- S4 Any other case answers "Não consta no script.": Jev disabled (its default), a timeout, malformed output, transport failure or low confidence. The event is still recorded.
- S5 `decision` stays `"unavailable"`; no new decision value; the text travels in `feedback_message`.
- S6 The classification is stored on the request's `impresso_requests` event. A retried request with the same `request_id` returns the same text without asking Jev again (Jev at most once).
- S7 The classification is not graded: the rubric assessment of a session is the same whatever the classification.
- S8 The backend tests that assert "Exame não disponível nesta estação" are rewritten for the two new texts, not deleted.
- S9 The Jev call is metered by session usage (#342) and bounded by a deadline that keeps `POST /sessions/:id/impressos/request` responsive.
- S10 `request_impresso/2` docs and `docs/design/jev-prototype.md` describe the classification and the fallback.
- S11 (optional) Live check with real requests for one station; misclassifications logged in the PR.

## Tasks

- [x] T1 S2 S4 S9 - Jev seam: `JevDecision.decide_impresso_request/2` + optional adapter callback, Disabled and TypeSafe adapters (one noul question, thresholds), deadline. Route: inline. Commit 14ca914. RED 0/14 (undefined functions), GREEN 14/14.
- [x] T2 S1 S3-S10 - Wire the classification into `Stations.request_impresso/2` unavailable branch, store it on the event (`Conversation.record_impresso_request/5`), rewrite tests, docs. Route: inline. RED conversation 103/105, stations+controller 8 failing; GREEN 105 and 190.

## Log

- L1 (2026-10-25, user): "sí, sigue en pie" — implement issue #357 on the launch branch (per-session route `POST /sessions/:id/impressos/request`).
- L2 Exploration: the event is built inside `Backend.Stations.Conversation.do_record_impresso_request/4`; storing the classification on it (S6) requires changing `conversation.ex`, not in the delegated edit surface. T1 proceeds within the surface; T2 waits for the surface to be extended.
- L3 T1 done (14ca914): `test/backend/stations/jev_decision/impresso_request_test.exs` RED 0/14, GREEN 14/14; Jev suites 281 passed; full backend `mix test` 2356 passed; `mix compile --warnings-as-errors` and `mix format --check-formatted` clean. Deadline: 2,000 ms default (`:jev_decision_impresso_deadline_ms`), so the impresso route waits at most ~2 s for Jev. Metering: the TypeSafe call goes through `execute_request/3`, which records one Jev call per HTTP response (verified by test).
- L4 Next step: extend the edit surface with `backend/lib/backend/stations/conversation.ex` and `backend/test/backend/conversation_test.exs` (store the classification on the event, idempotent retry), then T2 in `stations.ex` (unavailable branch only), tests and docs (`docs/design/jev-prototype.md`, `request_impresso/2`).
- L5 (2026-10-25, parent): edit surface extended to `conversation.ex` and `conversation_test.exs`, limited to storing an optional classification on the event; merged `origin/feat/326-production-launch` (#351, #363) cleanly.
- L6 T2 done: unavailable branch asks Jev only for a new request_id on an active session with `matched_ids == []`; `:plausible` → "Considere solicitado.", every other outcome → "Não consta no script." (failures stored as `:unclassified`). Tests: plausible/not_plausible/fallbacks (undecided, upstream error, invalid label, timeout, disabled), released/already_released never call Jev, retry returns the same response and calls Jev once, completed session never calls Jev, rubric invariance (Evaluator and Evidence.build unchanged when the classification is swapped), metering via the TypeSafe adapter (jev_calls == 1). Rewrote the two "Exame não disponível nesta estação" assertions. Full backend `mix test` 2386 passed; compile with warnings-as-errors and format check clean. Docs: `request_impresso/2`, `docs/design/jev-prototype.md`, `docs/unreal-station-client.md`. Known limit: two identical request_ids arriving concurrently may each ask Jev; the first recorded classification wins and both return its text.
- L7 PR #394 opened against `feat/326-production-launch` (head e19ce4b; LOCAL CI PASSED). Jorge advisory review (mapper, 3 specialists, refuter, all COMPLETE): no CONFIRMED findings. TR-357-1 (concurrent identical request_ids may each ask Jev) THEORETICAL: sequential retries call Jev once, the client retry contract is sequential (15 s timeout vs 2 s deadline), and the limit is documented. SP-357-1 (no per-session rate limit on paid Jev calls) THEORETICAL: pre-existing route posture shared with `create_message`; a hardening item for the #183 human gate. No repairs applied. S11 (live check) not done: Jev live use waits on #183.
