# 206 — Live TypeSafe Jev decision adapter

Issue: #206. Branch: `feat/206-jev-typesafe-adapter`, cut from `develop` at `6e855eb`. Target of the pull request: `develop`.

## Objective

Give `Backend.Stations.JevDecision` an adapter that calls the TypeSafe System One HTTP API (model Jev), so that a patient candidate reply can be verified by a real decision instead of being denied by the disabled adapter. The adapter is selectable by configuration and off by default.

## Problem

Only two adapters exist: `DisabledAdapter` (denies everything, the default) and the development-only approving adapter. The patient can therefore deliver only approved generic replies and the canonical refusal, in text and in voice.

## Evidence map (read on `6e855eb`; paths relative to `backend/`)

- Seam `lib/backend/stations/jev_decision.ex`: adapter resolution `:199-202` (`opts[:adapter]`, then app env `:jev_decision_adapter`); the seam enforces the deadline with a task and a brutal kill `:603-632`; `opts` reach the adapter only when it exports the arity-2 function `:607-611`; the request handed to the adapter is minimized `:389-471` (string-keyed `package` with `patient_profile`, `revealable_facts`, `response_rules`, `language`; last 10 turns labelled with `role` and `trust`); output validation `:658-730` (`used_fact_ids` must be ids of the minimized package's facts); error sanitization `:814-837` (`{:upstream_error, code >= 500}` becomes `{:upstream_5xx, code}`; unknown terms become `{:technical_failure, :adapter_error}`).
- Behaviour `lib/backend/stations/jev_decision/adapter.ex`: `decide_patient/1` and `decide_rubric/1` required, `decide_rubric_batch/1` optional.
- `lib/backend/stations/candidate_gate.ex:277-299`: `:verified` delivers the candidate; `:semantic_refusal` and `:low_confidence` are treated alike (one regeneration, then refusal); `used_fact_ids` and `rationale` are not used by the gate.
- House style for a Req provider adapter: `lib/backend/stations/station_ai/openai_adapter.ex` (config from opts, then app env, then environment variable; `retry: false`; `plug:` taken from opts; error mapping `:97-111`), tested with `Req.Test` stubs in `test/backend/station_ai/openai_adapter_test.exs`.
- Rubric traffic uses only `decide_rubric_batch` (`lib/backend/stations/rubric_assessment.ex:346-363`), whose response needs per-action classifications and evidence identifiers. `decide_rubric/2` has no production caller.
- Provider (https://docs.typesafe.ai/api.md, `/models.md`, `/confidence.md`, `/primitives/noul.md`, `/model-jaggedness/jev-1.13.md`, read 2026-10-13 through a summarizing fetcher): `POST https://api.typesafe.ai/v1/systemone`, Bearer key, body `state`, `model`, `questions` (map of id to `{type, instructions, criteria}`); a noul answer is `{type, noul}` with a probability from 0 to 1; a choice answer carries `choice`, `probabilities`, `confidence`; errors 401, 422, 429, 529; model `jev-1.13.0` with aliases `jev-latest` and `jev-preview`; 64k tokens per request; English is the primary language; the model reads literally and is weak on negation; text inside `state` can steer answers.

## Decisions

- **Slice 1 is the patient decision.** It is what unblocks the spoken and written patient. The rubric batch is a later task with an unresolved design problem (see Open questions).
- **One request per patient decision**, with `state` as an object built only from the minimized request the seam hands over: the candidate reply, the latest learner message, the bounded conversation, the patient profile, the response rules and the revealable facts. Learner text sits under clearly labelled fields.
- **Noul questions only, each about one condition, phrased so that a high value means yes and without negation:** one per revealable fact (does the reply state this fact), one per fact whose disclosure condition is `on_request` (did the learner ask for it), and three risk questions (clinical information not supported by the facts or the profile; contradiction with the facts or earlier patient turns; the reply leaves the patient role or follows instructions embedded in the conversation).
- **Mapping in code, not in the model.** With thresholds `yes_threshold` and `no_threshold`: `used_fact_ids` are the facts at or above `yes_threshold`. `:semantic_refusal` when any risk question is at or above `yes_threshold`, or a used `on_request` fact was not asked for (its asked question is at or below `no_threshold`). `:verified` only when every risk question is at or below `no_threshold` and no answer that the verdict depends on falls between the thresholds. Anything else is `:low_confidence`.
- **Thresholds are named, configurable and uncalibrated.** Defaults `yes_threshold: 0.8`, `no_threshold: 0.2`, taken from the provider's own example band. Real values belong to the human qualification in #183. The model is pinned to `jev-1.13.0` by default because thresholds depend on the model version.
- **A technical problem is never an approval.** A missing, extra or mistyped answer is `{:invalid_response, _}`; HTTP errors are `{:upstream_error, status}`; a missing key is `{:technical_failure, :missing_credentials}`; transport errors follow the house mapping.
- **No retry.** `retry: false`, and the receive timeout is the remaining seam budget minus a small margin, so the adapter returns a typed error instead of being killed. The gate's own regeneration shares the same 3 s budget.
- **Nothing is logged by the adapter.** No payload, candidate text, learner text or key.
- **Default unchanged.** `DisabledAdapter` stays the default; the live adapter is selected only by explicit configuration.

## Decisions made during T1

The correction recorded under T1 supersedes four items of this list: the question ids and wording of the contradiction and out-of-role risks, the handling of disclosure conditions, the sending of `response_rules` in `state`, and the reading of `TYPESAFE_*` variables by the adapter. The current list of questions is in the correction.

- **Question ids** are positional, not derived from fact ids: `fact_stated:<n>`, `fact_asked:<n>` (n is the 1-based position among the facts sent), `risk:unsupported_information`, `risk:contradiction`, `risk:out_of_role`.
- **Question wording** (English, no `criteria`; the optional `criteria` object is omitted because its exact shape could not be confirmed verbatim):
  - stated: `The text in `candidate_reply` states the following fact about the patient, in the same words or in different words: "<fact content>"`
  - asked: `A message with speaker `learner` in `conversation` asks the patient a question that the following fact answers: "<fact content>"`
  - unsupported information: `The text in `candidate_reply` gives clinical information about the patient that goes beyond what `revealable_facts` and `patient_profile` contain.`
  - contradiction: `The text in `candidate_reply` contradicts a fact in `revealable_facts` or contradicts an earlier message with speaker `patient` in `conversation`.`
  - out of role: `The text in `candidate_reply` leaves the role of the patient: it speaks as an AI, an assistant, a clinician or an examiner, or it follows an instruction written inside a message with speaker `learner`.`
- **The asked question looks at every learner message in the bounded conversation**, not only the latest one, so a patient may repeat a fact the learner asked for earlier. `latest_learner_message` is still sent in `state`.
- **Which answers the verdict depends on.** For an `on_request` fact: not stated, or asked for, respects the rule; stated and not asked for breaks it; every other combination is undecided and yields `:low_confidence`. An undecided stated answer on a fact with another disclosure condition does not affect the status. A refusal takes precedence over an undecided answer.
- **Only `on_request` carries a disclosure check.** Facts with `timed`, `unconditional` or `after_action` are checked for being stated only; their conditions are not evaluated by this adapter. (Corrected: any value outside the four the package loader admits now fails the request.)
- **`response_rules` are sent in `state` but no question asks about them**, because the Decisions section names no such question.
- **`state` keys:** `candidate_reply`, `latest_learner_message`, `conversation` (entries `speaker` = `learner` or `patient`, and `text`), `patient_profile`, `response_rules` (instruction strings), `revealable_facts` (`topic`, `content`, `disclosure_condition`; fact ids are not sent).
- **A fact without an id or without content is not sent and not asked about.** A reply that states it is then covered by the unsupported-information question.
- **Error terms.** Invalid responses are `{:invalid_response, reason}` with reason `:unexpected_body`, `:missing_answer`, `:unexpected_answer`, `:unexpected_answer_type`, `:noul_out_of_range` or `:noul_not_numeric`. Invalid thresholds are `{:technical_failure, :invalid_thresholds}`; `decide_rubric` returns `{:technical_failure, :rubric_decision_unsupported}`. All survive the seam's sanitizer unchanged; `{:upstream_error, status}` becomes `{:upstream_5xx, status}` for 500 and 529.
- **Timeouts.** The margin is 150 ms. The remaining budget is applied to the pool wait, each wait for data and the complete response (Finch `request_timeout`). The connection timeout keeps the HTTP client default, because Req starts one connection pool per distinct `connect_options` value; the seam deadline stays the hard limit for that phase.
- **Redirects are not followed** (`redirect: false`), so the payload cannot be sent to another host; a 3xx is `{:upstream_error, status}`. The body is decoded by the adapter (`decode_body: false`) so that broken JSON is an invalid response, not a network error.
- **Fixed request options cannot be overridden by configuration.** Unlike the OpenAI adapter, `retry`, `redirect` and the timeouts are applied after `req_options`; only `plug` is taken from the call options.
- **Configuration names.** `TYPESAFE_API_KEY`, `TYPESAFE_BASE_URL`, `TYPESAFE_MODEL`, `TYPESAFE_YES_THRESHOLD`, `TYPESAFE_NO_THRESHOLD`; an unparseable threshold is rejected, not replaced by the default. `JEV_ADAPTER=typesafe` selects the adapter outside `:test`; the E2E approving switch is evaluated later and wins in `dev`.
- **Call options share the gate's keyword list.** The seam passes the gate's options to the adapter, so `:api_key`, `:base_url`, `:model`, `:yes_threshold`, `:no_threshold`, `:plug` and `:req_options` in that list configure this adapter. No production caller sets them today.
- **Size.** T1 is 1,329 changed lines against a forecast of about 550; most of the difference is the test file and the formatter's line breaks. The work was not split.

## Scope

Allowed: `backend/lib/backend/stations/jev_decision/typesafe_adapter.ex` (new), `backend/test/backend/stations/jev_decision/typesafe_adapter_test.exs` (new), `backend/config/runtime.exs`, `README.md`, `docs/design/jev-prototype.md`, this document.

Out of scope: the seam, the candidate gate, the bounded reply policy, the voice path, enabling the adapter in any deployed environment, the human gates of #183, any call to the live API.

## Tasks

- [x] **T1 — Patient decision through TypeSafe.** `decide_patient/1,2` with the mapping above; `decide_rubric/1,2` and the batch are not implemented in this slice (`decide_rubric` returns a typed technical failure; the optional batch callback is not exported). Runtime configuration (adapter selection and key from the environment) and its documentation. Tests with `Req.Test` stubs for every status, every failure path, the request shape, the deadline-derived timeout and the absence of logs. Route: delegated writer (new module plus tests, reading prepares the write).
  - Code commit: `c095d46`. 1,328 insertions and 1 deletion in 5 files: adapter 504, tests 777, `runtime.exs` 16, `README.md` 30, `docs/design/jev-prototype.md` 1 changed line.
  - RED: with only the test file present, `mix test test/backend/stations/jev_decision/typesafe_adapter_test.exs` reported 0 of 47 passed; every test failed with `UndefinedFunctionError` (module `Backend.Stations.JevDecision.TypesafeAdapter` is not available). During GREEN two tests were corrected: `Req.Test.transport_error/2` rejects `:connect_timeout`, so the transport-timeout test stubs `:timeout` only; and a case for a 2xx body with a JSON content type and broken JSON was added.
  - GREEN, observed on `c095d46`: adapter tests 47 passed; `mix test` 885 passed (also with `JEV_ADAPTER=typesafe TYPESAFE_API_KEY=x` in the environment); `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict` (no issues) and `mix dialyzer` (0 errors) passed.
  - Adapter selection observed with `MIX_ENV=dev mix run --no-start`: no variable gives `DisabledAdapter`; `JEV_ADAPTER=typesafe` gives `TypesafeAdapter`; `JEV_ADAPTER=other` gives `DisabledAdapter`; `JEV_E2E_APPROVING_ADAPTER=true` gives the approving adapter, also when `JEV_ADAPTER=typesafe` is set. The `prod` path was not booted.
  - Not verified: anything about the live API. No request was sent to TypeSafe. The field names come from the provider documentation read through a summarizing fetcher, which declined to quote the JSON examples verbatim.
- [x] **T1 correction — hardening after independent verification.** Code commit `a1519ca` (548 insertions, 133 deletions in 4 files). The verifier found no approval on a technical or malformed input, and the following, each fixed with a test written first:
  1. *An unknown `disclosure_condition` failed open.* Any value other than the exact string `on_request` got no check. Now only `on_request`, `after_action`, `timed` and `unconditional` (the values `StationPackage` admits) are accepted; any other value, a missing one or a non-map fact fails the whole request with `{:technical_failure, :invalid_disclosure_condition}` before the provider is called. `{:invalid_request, _}` was not used because the seam's sanitizer turns it into a generic adapter error. RED: the test failed with "provider must not be called".
  2. *The adapter read `TYPESAFE_*` from the operating system at call time.* It now resolves call options, then the application environment, and nothing else. `config/runtime.exs` copies key, base URL, model and thresholds into the application environment at boot, outside `:test`. Choice for an unparseable threshold: it is kept as written and rejected as `:invalid_thresholds` on every decision; the boot does not fail and the default is never used in its place. RED: the runtime configuration tests failed (`yes_threshold` was `nil`, the adapter keyword list was incomplete).
  3. *Any 2xx was a success.* Only HTTP 200 is now a decision; 201, 202, 203 and 206 with a valid body are `{:upstream_error, status}`. A 200 body with a top-level `error` key is `{:invalid_response, :provider_error}`, even when it also carries valid answers.
  4. *Two risk questions asked two conditions each.* They are split; see the list below.
  5. *Response rules were not verified.* One risk question per rule with a non-blank instruction, id `rule_broken:<n>` by position. `response_rules` is no longer sent in `state`: the instruction is inside its own question, and repeating authored rule text in `state` would add tokens and one more text that can steer the other answers.
  6. *Missing tests added:* facts sharing an id (the id is now reported once in `used_fact_ids`; each fact keeps its own questions and disclosure check), thresholds arriving from the application environment, and an adapter crash through the seam (a candidate that is not valid UTF-8 gives `{:technical_failure, :adapter_crashed}` with no candidate bytes in the log).
  - RED as observed: with the new tests and the old code, 24 of 66 passed. Items 1 and 2 failed for their own reason. The tests for items 3, 5 and the duplicate ids failed with `{:invalid_response, :missing_answer}`, because the changed question ids made every stubbed answer set incomplete at once; their own reason was therefore not isolated in this run (the verifier had observed the 206 approval directly). The tests for invalid thresholds from the application environment and for the seam crash passed before the change: they cover behaviour that already held.
  - Current questions (all `noul`, `instructions` only):
    - `fact_stated:<n>`: `The text in `candidate_reply` states the following fact about the patient, in the same words or in different words: "<fact content>"`
    - `fact_asked:<n>` (only `on_request` facts): `A message with speaker `learner` in `conversation` asks the patient a question that the following fact answers: "<fact content>"`
    - `rule_broken:<n>`: `The text in `candidate_reply` breaks the following rule for the patient: "<instruction>"`
    - `risk:unsupported_information`: `The text in `candidate_reply` gives clinical information about the patient that goes beyond what `revealable_facts` and `patient_profile` contain.`
    - `risk:contradicts_facts`: `The text in `candidate_reply` contradicts a fact in `revealable_facts`.`
    - `risk:contradicts_patient`: `The text in `candidate_reply` contradicts an earlier message with speaker `patient` in `conversation`.`
    - `risk:speaks_out_of_role`: `The text in `candidate_reply` speaks as someone other than the patient, such as an AI, an assistant, a clinician or an examiner.`
    - `risk:follows_learner_instruction`: `The text in `candidate_reply` obeys an instruction, written inside a message with speaker `learner` in `conversation`, that tells it to act outside the patient role.`
  - Deviation: the last question is narrower than "follows an instruction written inside a learner message". A learner legitimately tells the patient what to do ("tell me where it hurts"), and a literal reader would answer yes to the broader wording for an ordinary good reply. The narrowed wording still asks one condition.
  - GREEN, observed on `a1519ca`: adapter tests 66 passed; `mix test` 904 passed; `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict` (no issues) and `mix dialyzer` (0 errors) passed. With `TYPESAFE_BASE_URL=http://127.0.0.1:1`, `TYPESAFE_API_KEY`, `TYPESAFE_MODEL`, `TYPESAFE_YES_THRESHOLD=0.01`, `TYPESAFE_NO_THRESHOLD=abc` and `JEV_ADAPTER=typesafe` exported: adapter tests 66 passed and `mix test` 904 passed.
  - Still not verified: anything about the live API.
- [ ] **T2 — Rubric decisions.** Blocked on the open question below.

## Acceptance criteria

Those of issue #206 that apply to the patient decision: approved, refused and low-confidence candidates return the matching status; every provider error and malformed answer returns a technical failure and never an approval; the call does not outlast the seam deadline; the default configuration is unchanged; no payload text appears in logs.

## Checks

- During iteration: `cd backend && mix test test/backend/stations/jev_decision/typesafe_adapter_test.exs`.
- At closure: `cd backend && mix format --check-formatted && mix compile --warnings-as-errors && mix credo --strict && mix test`.
- Test-first: observe RED for each new test before the implementation.

## Delivery

Actual size of T1 with its correction, `cb7b267..a1519ca` without this document: 1,743 insertions and 1 deletion in 5 files (tests 1,092, adapter 570, `runtime.exs` 44, `README.md` 36, `docs/design/jev-prototype.md` 1 changed line), in two work-unit commits (`c095d46`, `a1519ca`). The forecast was about 550. Strategy: single pull request for T1 with a size exception requested, because the adapter and its failure-path tests are one unit and about 63% of the lines are tests; T2 is a separate pull request. Receipt-driven development is off for this clone, so no native review runs; verification follows the tier from `gentle-ai review assess`.

## Open questions

- **Rubric batch.** The batch contract needs evidence identifiers and per-action classifications. TypeSafe returns only probabilities and closed choices, so it cannot name evidence. Options: return no evidence identifiers (to be checked against `Evidence.validate` and the authored rules), or a second fan-out of noul questions over evidence items. The 3 s default deadline for 11 criteria and 48 actions is also unverified.
- **Timed and action-dependent facts.** `timed` and `after_action` facts are checked only for being stated. Whether enough time has passed or the required action was performed is not checked, because the request the seam hands to an adapter carries neither.
- **Paraphrase recall.** When the model wrongly answers "not stated" for an `on_request` fact the learner did not ask for, the reply is approved with the fact in it. This is the main model-side risk of the mapping, and it is likely to be worse on paraphrased pt-BR content. It must be measured in the qualification run of #183.
- **Connect phase.** The remaining budget bounds the pool wait, each wait for data and the complete response, but not connection establishment. That phase is bounded only by the seam killing the adapter task at its deadline.
- **Selection without a key.** `JEV_ADAPTER=typesafe` without `TYPESAFE_API_KEY` boots without any warning and then fails every decision closed. Whether the boot should warn or fail is undecided.
- **Portuguese.** The provider states English as its primary language and gives no accuracy for Portuguese; the station content is pt-BR. Only the qualification run can answer this.
- **Zero data retention.** The provider documents it as an enterprise arrangement through sales; no retention period is stated. This is the human gate in #183 item 4.
- `docs/design/jev-prototype.md:155` says no probability or confidence value is read. That sentence is about the rubric contract; the patient adapter necessarily thresholds noul probabilities. T1 clarifies the sentence.

## Progress

- 2026-10-13: branch created; document written. No source change yet.
- 2026-10-13: T1 done in `c095d46`. The adapter is implemented, tested with stubs and documented; it is not enabled anywhere and has never called the live API.
- 2026-10-13: T1 corrected in `a1519ca` after independent verification (six findings, listed under T1).

## Next step

Parent verification and the pull request for T1 to `develop`, with the size exception. Before any live use: the human gates of #183, and a qualification run that calibrates the thresholds and checks the question wording on pt-BR content. T2 stays blocked on the rubric open question.
