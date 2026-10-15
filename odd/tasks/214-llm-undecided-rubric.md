# 214 — Resolve undecided rubric actions with an LLM after Jev

Issue: #214. Branch `feat/214-llm-undecided-rubric` from `origin/develop` 62e3c90 (worktree `../proyectoMed-214`). PR target `develop`, `Closes #214`.

## Objective

After Jev's rubric batch, an LLM decides only the actions Jev left `uncertain`. Jev's clear `performed` / `not_performed` stay final. Positive LLM decisions must cite learner evidence ids from the code-supplied pool; code validates them. Any technical failure leaves those actions `uncertain`, never credited.

## Settled design (2026-10-14)

- **Placement:** a resolver step inside `Backend.Stations.RubricAssessment`, after the Jev batch decisions return in `ask/3` (`rubric_assessment.ex:~355`) and before criterion judging. Jev's undecided action is `%{classification: "uncertain", evidence_ids: []}` (`typesafe_adapter.ex:~837`).
- **Seam:** new behaviour for the rubric resolver with its own config key `:rubric_resolver_adapter` (default: disabled → resolver is a no-op, undecided stays `uncertain`). Adapter injectable via opts (`:resolver_adapter`) like `:adapter` for Jev. One real implementation: OpenAI chat completions with `response_format` `json_schema` (strict). Patient decisions keep `:jev_decision_adapter`; rubric resolver is independent, so rubric and patient can use different providers.
- **Input to the LLM:** per criterion, every authored action with Jev's classification, the learner-only evidence pool (`id`, `text`), and the list of action ids it may decide (only Jev-`uncertain` ones).
- **Output schema:** `{"actions": [{"criterion_id", "id", "classification": "performed"|"not_performed"|"uncertain", "evidence_ids": [string]}]}` (action ids are unique only within a criterion). The strict schema stays static (no per-request enum) so the provider can cache it.
- **Merge rules (in code):** decisions for ids Jev decided clearly are ignored; unknown ids ignored; `performed` needs ≥1 citation and every citation must pass `Evidence.validate` as learner evidence, otherwise the action stays `uncertain`; malformed output / error / timeout → all undecided actions stay `uncertain`.
- **Deadline:** its own deadline, `:rubric_resolver_deadline_ms` (default 10_000), overridable via opts and `RUBRIC_RESOLVER_DEADLINE_MS`; not shared with Jev's 3 s rubric deadline. Changed from 5 s to 10 s on 2026-10-14 after live measurement (1.2–4.3 s per call).
- **Docs:** amend `docs/design/jev-prototype.md` (~:155-170) to describe the resolver step; Jev contract stays probability-free.

## Tasks

- [x] T1 — Resolver seam + merge in `RubricAssessment` with stubbed tests: performed with valid citation, not performed, still undecided; invalid id, patient citation, no citation, malformed output, error, timeout; LLM contradicting a clear Jev answer is ignored; disabled resolver is a no-op. Route: delegated (writer, 2+ non-trivial files).
- [x] T2 — OpenAI resolver adapter (structured output) + `Req.Test` tests + `runtime.exs` wiring (`RUBRIC_RESOLVER=openai`, `RUBRIC_RESOLVER_MODEL`, reuse OpenAI key/base URL). Route: delegated (same writer).
- [x] T3 — `mix stations.qualify` prints the resolver adapter and runs it; amend `docs/design/jev-prototype.md`. Route: delegated (same writer).
- [x] T4 — Live `mix stations.qualify acute-appendicitis` with real keys (user-run; costs balance).

## Checks

- `cd backend && mix test`, `mix credo --strict`, `mix format --check-formatted`, `mix compile --warnings-as-errors`.

## Progress

- 2026-10-14: exploration done, design settled with maintainer (own deadline chosen).
- 2026-10-14: T1 done in `85087e9` (route: delegated writer). `Resolver` behaviour + runner and `Resolver.DisabledAdapter` under `rubric_assessment/`; wired in `assess/3` after `ask/3`. RED observed first (4 of 19 new tests failing before wiring), then GREEN.
- 2026-10-14: T2 done in `71b8044` (route: delegated writer). `Resolver.OpenAIAdapter` (strict `json_schema`), `runtime.exs` wiring (`RUBRIC_RESOLVER=openai`, `RUBRIC_RESOLVER_MODEL`). Adapter tests written alongside the adapter (no separate RED run).
- 2026-10-14: T3 done in `e756d58` (route: delegated writer). Qualification `:resolver_adapter` + `Resolver:` header; design doc amended.
- Verification at each commit (backend/): `mix format --check-formatted` clean; `mix compile --warnings-as-errors` clean; `mix credo --strict` no issues; `mix test` 981 → 989 → 991 passed, 0 failures.
- Design gap resolved technically: rubric action ids are unique only within a criterion, so each resolver output entry also carries `criterion_id` (`{"actions": [{"criterion_id", "id", "classification", "evidence_ids"}]}`). An action decided twice is ignored. The adapter receives `opts[:resolver_opts]`, never the Jev options. The OpenAI adapter also types `:refused` and `:network_error`.
- 2026-10-14: `096d6c6` — resolver latency log + `RUBRIC_RESOLVER_DEADLINE_MS` override. Live run: 15/15 resolver calls answered in 1.2–4.3 s with a 30 s deadline; the first run at 5 s had 3 timeouts, all left `uncertain` (fail-safe held). The log also showed over-answering (e.g. 15 decisions for 6 undecided actions).
- 2026-10-14: `edf2e96` (route: delegated writer) — default deadline 10 s; the OpenAI adapter now sends per criterion `decide` (Jev-uncertain actions) apart from `context_actions` (Jev's final classes, context only) plus `decision_count`, and the system prompt asks for exactly one entry per action to decide. Schema unchanged and static. Req.Test asserts the outgoing body. Verification: `mix format --check-formatted` clean; `mix compile --warnings-as-errors` clean; `mix credo --strict` no issues; `mix test` 992 passed, 0 failures.
- 2026-10-14: T4 done at `237beea` (user-run, default 10 s deadline, `gpt-4o-mini`): 15/15 resolver calls answered in 1.7–3.7 s, 0 timeouts; 14/15 returned exactly one decision per undecided action, one returned 13 for 8 (extra decisions ignored by the merge).
- 2026-10-14: pushed; PR #220 to `develop` (`Closes #214`), single PR by maintainer choice. Next: CI and review.

