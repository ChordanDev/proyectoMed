# 214 — Resolve undecided rubric actions with an LLM after Jev

Issue: #214. Branch `feat/214-llm-undecided-rubric` from `origin/develop` 62e3c90 (worktree `../proyectoMed-214`). PR target `develop`, `Closes #214`.

## Objective

After Jev's rubric batch, an LLM decides only the actions Jev left `uncertain`. Jev's clear `performed` / `not_performed` stay final. Positive LLM decisions must cite learner evidence ids from the code-supplied pool; code validates them. Any technical failure leaves those actions `uncertain`, never credited.

## Settled design (2026-10-14)

- **Placement:** a resolver step inside `Backend.Stations.RubricAssessment`, after the Jev batch decisions return in `ask/3` (`rubric_assessment.ex:~355`) and before criterion judging. Jev's undecided action is `%{classification: "uncertain", evidence_ids: []}` (`typesafe_adapter.ex:~837`).
- **Seam:** new behaviour for the rubric resolver with its own config key `:rubric_resolver_adapter` (default: disabled → resolver is a no-op, undecided stays `uncertain`). Adapter injectable via opts (`:resolver_adapter`) like `:adapter` for Jev. One real implementation: OpenAI chat completions with `response_format` `json_schema` (strict). Patient decisions keep `:jev_decision_adapter`; rubric resolver is independent, so rubric and patient can use different providers.
- **Input to the LLM:** per criterion, every authored action with Jev's classification, the learner-only evidence pool (`id`, `text`), and the list of action ids it may decide (only Jev-`uncertain` ones).
- **Output schema:** `{"actions": [{"id", "classification": "performed"|"not_performed"|"uncertain", "evidence_ids": [string]}]}`.
- **Merge rules (in code):** decisions for ids Jev decided clearly are ignored; unknown ids ignored; `performed` needs ≥1 citation and every citation must pass `Evidence.validate` as learner evidence, otherwise the action stays `uncertain`; malformed output / error / timeout → all undecided actions stay `uncertain`.
- **Deadline:** its own deadline, `:rubric_resolver_deadline_ms` (default 5_000), overridable via opts; not shared with Jev's 3 s rubric deadline.
- **Docs:** amend `docs/design/jev-prototype.md` (~:155-170) to describe the resolver step; Jev contract stays probability-free.

## Tasks

- [ ] T1 — Resolver seam + merge in `RubricAssessment` with stubbed tests: performed with valid citation, not performed, still undecided; invalid id, patient citation, no citation, malformed output, error, timeout; LLM contradicting a clear Jev answer is ignored; disabled resolver is a no-op. Route: delegated (writer, 2+ non-trivial files).
- [ ] T2 — OpenAI resolver adapter (structured output) + `Req.Test` tests + `runtime.exs` wiring (`RUBRIC_RESOLVER=openai`, `RUBRIC_RESOLVER_MODEL`, reuse OpenAI key/base URL). Route: delegated (same writer).
- [ ] T3 — `mix stations.qualify` prints the resolver adapter and runs it; amend `docs/design/jev-prototype.md`. Route: delegated (same writer).
- [ ] T4 — Live `mix stations.qualify acute-appendicitis` with real keys (user-run; costs balance).

## Checks

- `cd backend && mix test`, `mix credo --strict`, `mix format --check-formatted`, `mix compile --warnings-as-errors`.

## Progress

- 2026-10-14: exploration done, design settled with maintainer (own deadline chosen).
