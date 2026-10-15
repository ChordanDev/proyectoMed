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

## Findings (live diagnostics 2026-10-15)

- "Before" qualification (`acute-appendicitis`, live Jev): of 18 dialogue cases, 4 differ from `proposed_expected`. Undecided where `delivered` was proposed: `uncertainty-01` (speaks_out_of_role 0.49), `modality-gap-03` (unsupported_information 0.29), `ambiguity-02` (fact_asked:10 0.68). Delivered where refusal was proposed: `unsupported-or-early-disclosure-01` (known gap G10). The greeting case `unsupported-or-early-disclosure-05` (correct name "Rafael Nogueira") was verified with every question <= 0.09.
- Live greeting (gpt-4o-mini, learner "Olá, boa tarde. Eu sou o Dr. Vicenzo, médico plantonista. Qual é o seu nome completo?", 6 generations): OpenAI invented names ("João da Silva", "Antônio Silva", "Carlos Almeida", "Carlos Alberto") or answered the refusal text "Não tenho essa informação.". Jev scored speaks_out_of_role/rule_broken ~0.23-0.29 (undecided) for invented names and 0.89 for the refusal.
- Root cause is the candidate shape, not the Jev thresholds: the authored name only appears in `patient_profile.presenting_context`, written to the examiner in the second person, and restriction 1 of `StationAI.system_prompt/1` forces the refusal for anything outside `revealable_facts`. Thresholds stay unchanged.

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
- [x] T4a (delegated writer, backend) — Per-question Jev diagnostics for calibration, no behavior or threshold change.
  - `TypesafeAdapter.decide_patient/2` logs at `:debug` one line `[TypesafeAdapter] patient verdict=<status>` + every `<question id>=<noul, 3 decimals>:<yes|no|undecided>`, sorted by id; ids are positional, so no learner, candidate or authored text, fact id or key. Moduledoc "logs nothing" replaced by a Logging section.
  - `Qualification` logs `[Qualification] case=<id> surface=<surface>` at `:debug` before each case (cases run sequentially), so adapter lines that follow belong to that case.
  - `mix stations.qualify --debug` sets Logger to `:debug` for the run; without it a level more verbose than `:info` (dev default `:debug`) is raised to `:info`; the configured level is restored. Debug lines go to the console only, never to `--out`.
  - RED: adapter debug-log test (empty log), qualification case-line test, and `--debug` task test (usage error) failed before implementation. `Logger.put_process_level/2` does not reach `capture_log` here, so the tests set the global level in non-async modules.
  - Evidence: `mix format --check-formatted` clean; `mix compile --warnings-as-errors` ok; focused jev_decision + qualify task + qualification tests 204 passed; full `mix test` 1035 passed; dev `mix stations.qualify acute-appendicitis --debug` printed 34 case lines, the default run printed no debug line.
  - Live diagnostic (maintainer, from `backend/`, with `TYPESAFE_API_KEY` set): `JEV_ADAPTER=typesafe mix stations.qualify acute-appendicitis --debug --out ../tmp/224-before.txt`
- [x] T5 (delegated writer, web) — `timeout` (504) and `station_ai_unavailable` (502) on create-message are recoverable like `reply_verification_failed` (maintainer decision 2026-10-15).
  - Single seam: `recoverableTurnNotice(cause)` in `useStation.ts` maps code → pt-BR notice (`reply_verification_failed` → `replyVerificationFailedNotice`; `timeout`, `station_ai_unavailable` → new `turnUnavailableNotice` "Não foi possível obter a resposta agora. Tente enviar novamente."). The hook rethrows those codes without `fail`; `StationScreen.sendTurn` drops the learner bubble, restores the draft, and shows the mapped notice (`data-testid="turn-retry-notice"`). Session start/finish/result errors, client-side `request_timeout`, and `station_time_elapsed` are unchanged.
  - Backend check: `Stations.generate_and_resolve_turn` rolls back the pending learner turn on any initial generation error (→ `station_ai_unavailable`), and `verify_and_resolve_turn` rolls back on every verification error, including `:timeout` and regeneration failures.
  - `stationFlow.test.ts` unchanged: its `station_ai_unavailable` assertion is at API-client level (not the hook) and already expects the session to remain unfinished.
  - RED: 2 hook tests + 4 new screen tests failed (and the 3 T1 screen tests after the test id rename). GREEN: `npm --prefix web test` 8 files / 182 passed; build ok; lint clean.
- [x] T6 (delegated writer, backend) — The simulated patient knows its own identity.
  - `StationAI.system_prompt/1` adds a "QUEM VOCÊ É" section: the Contexto is written for the examiner, the patient IS the person described there, it may state its name, age and occupation as written there; other context data (vitals, findings, clinical information) stays unsayable unless a revealable fact. Restriction 1 gains the identity exception; restrictions 2-4 unchanged. No package schema, authored content, Jev payload, or threshold change.
  - RED: 3 of 4 new tests in `test/backend/stations/station_ai_test.exs` failed (restrictions-intact test is characterization). GREEN: `mix test` 1039 passed; format and `compile --warnings-as-errors` clean.
  - Live re-run of the greeting and the qualification "after" run remain with T4 (maintainer keys).
- [x] T4 (HITL, maintainer keys) — Live `mix stations.qualify acute-appendicitis` before; diagnose undecided nouls; calibrate (thresholds / question wording / candidate shape); after run; record evidence on #224.
  - Before and after qualification runs (2026-10-15, `--debug`): identical dialogue_gate outcomes, because qualification cases carry fixed candidate replies that the prompt change does not affect. The same 4 of 18 cases differ from `proposed_expected` (see Findings). No threshold change: 0.8 / 0.2 kept.
  - Root cause of the observed greeting failure: the active station is hard-coded to the placeholder `chest-pain-initial-assessment` (`station_loader.ex:12`, `placeholder: true`, age 56, one revealable fact, no patient name). With no authored name, every name the patient gives is invented, so Jev correctly leaves it undecided or refuses it. After T6, 6 live generations on the placeholder still invented names ("José da Silva", "[nome completo]") and all stayed `low_confidence`. That is expected and is not a calibration defect.
  - Live greeting on the acute-appendicitis package after T6 (scratch probe: OpenAI generation + `Stations.verify_patient_reply`, gpt-4o-mini + jev-1.13.0): 3 of 3 replies stated "Rafael Nogueira" and were `verified`, with every noul <= 0.09. No run was made on acute-appendicitis before T6, so this does not isolate T6's effect.

## Checks

- `npm --prefix web test`, `npm --prefix web run build` (typecheck)
- `cd backend && mix test`, `mix format --check-formatted`

## Progress

- Route: T1 delegated (2+ non-trivial web files). T5 and T6 delegated to one writer (2+ non-trivial files). T1 done; commit recorded in git log on the branch (`fix(web): keep station active when a patient reply fails verification`).
