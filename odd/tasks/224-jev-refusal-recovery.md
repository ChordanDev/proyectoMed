# 224 — Keep the station usable when Jev cannot verify a patient reply

Worktree `../proyectoMed-224`, branch `feat/224-jev-refusal-recovery` from `origin/develop` c3110fb. PR target `develop`, `Closes #224` (parent #125).

## Objective

A Jev verification refusal on one learner turn must not end the station, and Jev must stop leaving ordinary patient replies undecided.

## Findings (exploration 2026-10-14)

- `StationController.create_message/2` already maps `{:refused, _}` / `{:denied, _}` to 502 `reply_verification_failed` (`station_controller.ex:109-121`), covered by `pre_delivery_gate_contract_test.exs:411`. The issue premise that it falls into the catch-all is wrong; the observed "indisponível" banner came from another error (likely the OpenAI regeneration during the semantic retry or a TypeSafe technical failure inside the 3,000 ms Jev budget, `config.exs:16`).
- The backend already rolls back the pending learner message on refusal; no turn is counted and the session stays active.
- The web kills the station: `useStation.ts` `sendMessage` catch calls `fail(cause)` for every error except `station_time_elapsed`.
- TypesafeAdapter verdict: any risk/rule noul between 0.2 and 0.8 makes the reply `:low_confidence`. No qualification case covers an opening greeting.

## Decisions (maintainer 2026-10-14)

- On `reply_verification_failed`: station stays active, timer keeps running, the learner's text is restored to the input, inline pt-BR notice: "O paciente não conseguiu responder a essa mensagem. Tente enviar novamente ou reformular a pergunta." The turn does not count (backend rollback already does this).
- Technical failures keep ending the turn fail-closed as today.

## Tasks

- [x] T1 (delegated writer, web) — `reply_verification_failed` is recoverable in `useStation` + `StationScreen`; restore draft, inline notice, i18n key; tests first.
  - Seam: `useStation.send` rethrows `reply_verification_failed` (status stays active, no `fail`); `StationScreen.sendTurn` drops the optimistic learner bubble, restores the text to the input, and shows `replyVerificationFailedNotice` (role=status); the notice clears on input edit or the next send.
  - RED: 1 hook test + 3 screen tests failed before implementation. GREEN: `npm --prefix web test` 8 files / 175 tests passed; `npm --prefix web run build` ok; `npm --prefix web run lint` clean.
  - Integration (`stationFlow.test.ts`) not extended: the E2E harness cannot trigger a Jev refusal without backend harness changes.
- [ ] T2 (inline/delegated) — Backend: controller test asserting `reply_verification_failed` for `{:refused, :low_confidence}` and `{:refused, :semantic_refusal}` vs `station_ai_unavailable` for technical failure (if not already present at controller level).
- [ ] T3 — Qualification: add an opening-greeting `dialogue_gate` case to acute-appendicitis.
- [ ] T4 (HITL, maintainer keys) — Live `mix stations.qualify acute-appendicitis` before; diagnose undecided nouls; calibrate (thresholds / question wording / candidate shape); after run; record evidence on #224.

## Checks

- `npm --prefix web test`, `npm --prefix web run build` (typecheck)
- `cd backend && mix test`, `mix format --check-formatted`

## Progress

- Route: T1 delegated (2+ non-trivial web files). T1 done; commit recorded in git log on the branch (`fix(web): keep station active when a patient reply fails verification`).
