# 224 — Keep the station usable when Jev cannot verify a patient reply

Worktree `../proyectoMed-224`, branch `feat/224-jev-refusal-recovery` from `origin/develop` c3110fb. PR target `develop`, `Closes #224` (parent #125).

## Objective

A Jev verification refusal on one learner turn must not end the station, and Jev must stop leaving ordinary patient replies undecided.

## Findings (exploration 2026-10-14)

- `StationController.create_message/2` already maps `{:refused, _}` / `{:denied, _}` to 502 `reply_verification_failed` (`station_controller.ex:109-121`), covered by `pre_delivery_gate_contract_test.exs:411`. The issue premise that it falls into the catch-all is wrong; the observed "indisponível" banner came from another error (likely the OpenAI regeneration during the semantic retry or a TypeSafe technical failure inside the 3,000 ms Jev budget, `config.exs:16`).
- The backend already rolls back the pending learner message on refusal; no turn is counted and the session stays active.
- The web kills the station: `useStation.ts` `sendMessage` catch calls `fail(cause)` for every error except `station_time_elapsed`.
- Semantic-retry failure path (T2 investigation): the 3,000 ms Jev deadline is set in `build_verify_opts` (`stations.ex:606`) after the initial OpenAI generation, so it covers Jev call 1 + regeneration + Jev recheck. The HTTP regenerator is arity 0 (`stations.ex:661`), so `invoke_generator` (`candidate_gate.ex:360-397`) cannot pass the remaining budget and the OpenAI call is not cut at the deadline. A regeneration error (`:upstream_error`, `:network_error`, `:malformed_response`, `{:invalid_adapter_output, _}`, `{:generator_crash, _}`) propagates unchanged (`candidate_gate.ex:305`, `stations.ex:245-246`) to the controller catch-all → 502 `station_ai_unavailable`. A budget exhausted before/after regeneration or before the recheck (`candidate_gate.ex:303,306,340`), an OpenAI transport timeout, or a Jev call exceeding its remaining budget (`jev_decision.ex:705-707`) yields `{:error, :timeout}` → 504 `timeout`. Only a refusal on the recheck yields 502 `reply_verification_failed`. Both 502 `station_ai_unavailable` and 504 `timeout` still end the station in the web (only `reply_verification_failed` and `station_time_elapsed` are recoverable).
- TypesafeAdapter verdict: any risk/rule noul between 0.2 and 0.8 makes the reply `:low_confidence`. No qualification case covers an opening greeting.

## Decisions (maintainer 2026-10-14)

- On `reply_verification_failed`: station stays active, timer keeps running, the learner's text is restored to the input, inline pt-BR notice: "O paciente não conseguiu responder a essa mensagem. Tente enviar novamente ou reformular a pergunta." The turn does not count (backend rollback already does this).
- Technical failures keep ending the turn fail-closed as today.

## Tasks

- [x] T1 (delegated writer, web) — `reply_verification_failed` is recoverable in `useStation` + `StationScreen`; restore draft, inline notice, i18n key; tests first.
  - Seam: `useStation.send` rethrows `reply_verification_failed` (status stays active, no `fail`); `StationScreen.sendTurn` drops the optimistic learner bubble, restores the text to the input, and shows `replyVerificationFailedNotice` (role=status); the notice clears on input edit or the next send.
  - RED: 1 hook test + 3 screen tests failed before implementation. GREEN: `npm --prefix web test` 8 files / 175 tests passed; `npm --prefix web run build` ok; `npm --prefix web run lint` clean.
  - Integration (`stationFlow.test.ts`) not extended: the E2E harness cannot trigger a Jev refusal without backend harness changes.
- [x] T2 (delegated writer) — Backend: controller test asserting `reply_verification_failed` for `{:refused, :low_confidence}` and `{:refused, :semantic_refusal}` vs `station_ai_unavailable` for technical failure (if not already present at controller level).
  - `station_controller_test.exs`: `ConfigurableJevAdapter` double; each refusal returns 502 `reply_verification_failed`, no patient text in the body, GET shows the session `active` with no messages, and a follow-up message on the same session returns 200. Jev `{:technical_failure, :missing_credentials}` and `:network_error` return 502 `station_ai_unavailable`.
  - Characterization coverage, not RED: the behavior already existed and the 4 new tests passed on first run. No production change.
  - Evidence: `mix test test/backend_web/controllers/station_controller_test.exs` 61 passed.
- [x] T3 (delegated writer) — Qualification: add an opening-greeting `dialogue_gate` case to acute-appendicitis.
  - `unsupported-or-early-disclosure-05` (category `unsupported_or_early_disclosure`; the category list is fixed in `cases.ex`): learner greeting + full-name question, candidate "Boa tarde, doutor. Meu nome é Rafael Nogueira." (name from `patient_profile.presenting_context`), proposed `delivered`, adjudication pending.
  - Disabled-adapter run reaches Jev (`adapter_disabled`), so no deterministic denial; `stations_qualify_test.exs` asserts 34 cases and the new row.
  - Evidence: focused qualification + controller + qualify task tests 85 passed; full `mix test` 1029 passed; `mix format --check-formatted` clean.
- [ ] T4 (HITL, maintainer keys) — Live `mix stations.qualify acute-appendicitis` before; diagnose undecided nouls; calibrate (thresholds / question wording / candidate shape); after run; record evidence on #224.

## Checks

- `npm --prefix web test`, `npm --prefix web run build` (typecheck)
- `cd backend && mix test`, `mix format --check-formatted`

## Progress

- Route: T1 delegated (2+ non-trivial web files). T1 done; commit recorded in git log on the branch (`fix(web): keep station active when a patient reply fails verification`).
