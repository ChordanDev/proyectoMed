# Issue 208: cap learner and conversation text sent to the Jev provider

Branch: `feat/208-jev-text-cap` (worktree `../proyectoMed-208`, from `origin/develop` d9adc8b). PR target: `develop`, `Closes #208`.

## Objective

Bound the text any Jev adapter can send to a provider. Oversized input fails closed with a typed error; it is never truncated. Normal-sized requests are unchanged.

## Problem

`Backend.Stations.JevDecision` caps only the candidate reply (`max_characters`, 2,000) and the number of turns (`max_context_turns`, 10). Learner messages have no length limit (only non-empty), the endpoint body limit is 20 MB, and the rubric evidence pool is unbounded. The TypeSafe adapter (#207) sends this text off-host.

## Decisions (maintainer, 2026-10-14)

- **Reject at the entry point.** A learner message longer than 2,000 characters is rejected with a clear "message too long" error and never enters the conversation. Rationale: a giant message stored in history would break every later turn of the session.
- **Fail closed in the seam, never truncate.** The seam enforces a total-size cap on the learner/conversation text it hands to any adapter (patient and rubric requests). Over the cap, the decision fails closed with `{:invalid_request, :context_limit_exceeded}`. Rationale: a truncated question can make the patient answer half a question, which is worse than not answering. With the entry cap this is a safety net that should never fire in normal use.
- Trusted, author-written package content (facts, rules, profile) is not counted against the cap.

## Scope

Backend only. The web client is not changed in this issue.

## Tasks

- [x] T1 Learner message length limit (2,000 characters) in the `Backend.Stations` public interface, mapped by `StationController.create_message` to a 422 `message_too_long` error. Tests at context and controller level.
- [x] T2 Seam total-size cap (`jev_decision_max_context_characters`) for patient requests (candidate + bounded conversation + latest learner turn) and rubric requests (evidence pool). Typed fail-closed error; a stub adapter is never called above the cap. Normal requests unchanged.

## Acceptance criteria

- An oversized learner turn: the provider stub never receives a body above the cap, or the decision fails closed with a typed error.
- Normal-sized requests are unchanged.
- The HTTP-boundary decision is recorded (this document and the PR).

## Checks

- `cd backend && mix test` (full suite), `mix format --check-formatted`, `mix compile --warnings-as-errors`.

## Progress

- Route: delegated direct (one writer; 2+ non-trivial files: seam, context, controller, tests).
- T1 done in `33aeff8` (`feat(stations): reject learner messages over the length limit`). `Backend.Stations.create_message/2` rejects text over `:learner_message_max_characters` (default 2,000, `String.length`) with `{:error, :message_too_long}` before `Conversation.begin_turn`; the controller maps it to 422 `message_too_long`. RED observed: 2 failing tests (context returned `{:ok, _}`, controller returned 200); GREEN after implementation.
- T2 done in `75b9f5e` (`feat(stations): cap total text the Jev seam sends to adapters`). `JevDecision.max_context_characters/0` (config `:jev_decision_max_context_characters`, default 24,000, opts `:max_context_characters`) caps candidate + bounded conversation + latest learner turn for `decide_patient/2`, and the evidence pool for `decide_rubric/2` and `decide_rubric_batch/2`. Over the cap: `{:invalid_request, :context_limit_exceeded}` before any adapter call. RED observed: 7 failing tests; GREEN after implementation.
- Learner text paths: `create_message/2` (text and voice modality, `post_message/2` alias) is the only production path that stores learner text in the conversation; `Conversation.append_message/2` is used only by tests, and transcription returns text to the client without storing it.
- Decision (maintainer, 2026-10-14): rubric requests get their own cap. The rubric evidence pool is the whole transcript; stations last 10 minutes and a real session totals about 20,000-30,000 characters, so `decide_rubric/2` and `decide_rubric_batch/2` use `JevDecision.max_rubric_context_characters/0` (config `:jev_decision_max_rubric_context_characters`, default 120,000, opts `:max_rubric_context_characters`), about 4-5x headroom while still bounding abuse (fail closed, never truncate). Patient requests keep the 24,000 cap. Done in `55e136e` (`feat(stations): give rubric requests their own Jev text cap`). RED observed: 6 failing tests; GREEN after implementation.
- Verification (after T2): `mix format --check-formatted`: OK; `mix compile --force --warnings-as-errors`: OK; `mix test`: 927 passed, 0 failed.
- Verification (after the rubric cap): `mix format --check-formatted`: OK; `mix compile --force --warnings-as-errors`: OK; `mix test`: 931 passed, 0 failed.
- Jorge SP-208-1 (confirmed, maintainer-approved fix): `request_impresso/2` stored request text without a bound, and that text enters the rubric evidence pool. Fixed in `438bd8f` (`fix(stations): cap impresso request text at the learner message limit`): text over the learner message limit (2,000) is rejected with `{:error, :message_too_long}` (HTTP 422 `message_too_long`) before recording, never truncated. RED observed: 2 failing tests; GREEN after the fix. Verification: `mix format --check-formatted`: OK; `mix compile --force --warnings-as-errors`: OK; `mix test`: 934 passed, 0 failed.
- Next step: open the PR to `develop` with `Closes #208`.
