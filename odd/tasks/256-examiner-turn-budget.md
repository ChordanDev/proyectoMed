# 256 — Keep examiner-addressed turns when the patient reply cannot be verified in time; serve the patient from Claude Sonnet 5.5

Issue: #256 (parent tracker #237). Branch `fix/256-examiner-turn-budget` from `origin/feat/237-clinician-demo-readiness` (`f63395d`), worktree `../proyectoMed-worktrees/issue-256`. PR target `feat/237-clinician-demo-readiness`, `Refs #256`.

## Objective

A refused patient candidate whose single regeneration cannot finish inside the Jev budget keeps the learner turn (the #235 kept-turn path) instead of rolling it back with a 504. The patient runs on Claude Sonnet 5.5 (its own model setting) while the resolver and feedback stay on `ANTHROPIC_MODEL`. Patient generations and Jev verifications log their latency at debug level.

## Why

In the 2026-10-19 Claude rehearsal the verbalized exam findings failed twice with HTTP 504: the first candidate was refused, the regeneration on Opus 5.5 did not fit the 3 s Jev budget, and the `{:error, :timeout}` rolled the learner turn back. The maintainer chose Sonnet 5.5 for the patient on 2026-10-19 for latency.

## Constraints

- #235/#224: refused or unverified patient text is never stored, returned or logged.
- A timeout with no prior refusal keeps today's rollback (HTTP 504).
- Sonnet 5.5 request rules: no `temperature`/`top_p`; thinking off is `thinking: {type: "between_tools"}` with no other thinking field, at effort `high` or below (`disabled` returns a 400; `between_tools` is a 400 on every other model). Patient effort `low`.
- Opus 5.5 (resolver/feedback): no `thinking` field, effort `medium`.
- `fallbacks: "default"` (beta `server-side-fallback-2026-07-01`) is accepted by both Opus 5.5 and Sonnet 5.5 on the Claude API, so it stays on both.
- Latency logs carry only role, outcome category and milliseconds: no prompt, learner or patient text.
- No live calls in tests (Req.Test / doubles).

## Tasks

- [x] T1 — CandidateGate: when a refused candidate's regeneration runs out of budget (before or during regeneration, or its verification times out), return the original refusal so `Stations.create_message` keeps the learner turn; a timeout with no refusal still rolls back. Tests in `candidate_gate_test.exs` and `pre_delivery_gate_contract_test.exs`. Route: inline (delegated writer).
- [x] T2 — Patient model setting `ANTHROPIC_PATIENT_MODEL` (default `claude-sonnet-5-5`) and Sonnet 5.5 request fields (`thinking: between_tools`, effort `low`) in the shared client; resolver/feedback keep `ANTHROPIC_MODEL`. Runtime config, README. Route: inline.
- [x] T3 — Debug latency logs for each patient generation and each Jev patient verification, without text. Route: inline.
- [ ] T4 — Live check (user-run, needs keys): verbalized exam findings and lab interpretation produce a patient reply or "Examinador: Anotado.", never the retry notice. Pending.

## Checks

- Per task: focused `mix test <files>` RED then GREEN.
- Closure: local CI script (format, warnings-as-errors, credo strict, `mix test`, web suite, process E2E).

## Progress

- 2026-10-19: exploration done; plan above.
- 2026-10-19: T1 done (route: inline). RED: 3 changed/new gate tests failing (`{:error, :timeout}` instead of the refusal) plus 2/2 new Stations/HTTP contract tests; the non-timeout regeneration guard already passed. GREEN: 91/91 in the two files; full backend 1244 passed; format and credo clean. The no-refusal timeout rollback (HTTP 504) stays covered by the existing contract test. Commit `9f90ea7`.
- 2026-10-19: T2 done (route: inline). RED: 4 failing (patient payload model/thinking, patient ignores `:model`, `:patient_model` from config, runtime config writes `ANTHROPIC_PATIENT_MODEL`); 4 guards already passed (non-Sonnet patient gets no thinking; resolver and feedback keep `:model`, effort `medium`, no thinking). GREEN: 43/43; full backend 1248 passed; credo and warnings-as-errors clean. `fallbacks: "default"` stays on both models (the reference lists it for Opus 5.5 and Sonnet 5.5 on the Claude API).
- 2026-10-19: T2 commit `1ac9900`.
- 2026-10-19: T3 done (route: inline). RED: 1/1 new log test failing (no `patient_generation` lines). GREEN: 22/22 in the contract file; full backend 1249 passed; credo and warnings-as-errors clean. `Stations` logs `[Stations] patient_generation latency_ms=N outcome=ok|error` and `JevDecision` logs `[JevDecision] patient_verification latency_ms=N outcome=<status>|error`, both at debug, with no text.
- 2026-10-19: T3 commit `21ad514`. Local CI (mirror of `pr-validation.yml`) passed at `21ad514`: web unit 213 passed, backend `mix test` 1249 passed, process E2E 4 passed; format, warnings-as-errors and credo clean. GitHub Actions is blocked by billing.
- Pending: T4 live check (no key available to the writer). The first patient generation runs before the Jev deadline starts, so only the regeneration shares the 3 s budget; the debug latencies will show whether `:jev_decision_default_deadline_ms` (3 s, `config/config.exs`, no environment override yet) needs tuning.

## Next step

 T4 (live check, user-run): `LLM_PROVIDER=anthropic JEV_ADAPTER=typesafe` with debug logs to read the latencies.
