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

- [ ] T1 S2 S4 S9 - Jev seam: `JevDecision.decide_impresso_request/2` + optional adapter callback, Disabled and TypeSafe adapters (one noul question, thresholds), deadline. Route: inline.
- [ ] T2 S1 S3-S8 S10 - Wire the classification into `Stations.request_impresso/2` unavailable branch, store it on the event, rewrite tests, docs. Route: inline. Needs `backend/lib/backend/stations/conversation.ex` (event storage), which is outside the authorized edit surface.

## Log

- L1 (2026-10-25, user): "sí, sigue en pie" — implement issue #357 on the launch branch (per-session route `POST /sessions/:id/impressos/request`).
- L2 Exploration: the event is built inside `Backend.Stations.Conversation.do_record_impresso_request/4`; storing the classification on it (S6) requires changing `conversation.ex`, not in the delegated edit surface. T1 proceeds within the surface; T2 waits for the surface to be extended.
