# 252 — Use Claude for the patient, the rubric resolver and learner feedback

Issue: #252 (parent tracker #237). Branch `feat/252-claude-text-roles` from `origin/feat/237-clinician-demo-readiness` (`c24a7ec`), worktree `../proyectoMed-worktrees/issue-252`. PR target `feat/237-clinician-demo-readiness`, `Refs #252`.

## Objective

Serve the three text seams that call OpenAI today (simulated patient, rubric resolver, learner feedback) from Anthropic's Claude Messages API when one setting asks for it, keeping every seam contract: deadlines, failure classification and authored fallbacks. Jev stays on TypeSafe; voice moves in #253.

## Why

The maintainer chose Claude for the clinician demo (#237) on 2026-10-19 (provider decision for the human gates in #183).

## Constraints

- Raw HTTP with Req against `POST /v1/messages`; no SDK, no OpenAI-compatibility shim.
- Model `claude-opus-5-5` by default (`ANTHROPIC_MODEL`). No `thinking` config (adaptive is the default), never `temperature` / `top_p` / `budget_tokens`.
- Effort: patient `low` (latency), resolver and feedback `medium`.
- Headers `x-api-key`, `anthropic-version: 2023-06-01`, `anthropic-beta: server-side-fallback-2026-07-01` with `fallbacks: "default"`.
- Check `stop_reason` before reading content; `refusal` (and any stop that is not a normal end) is a technical failure of the seam.
- Resolver and feedback use structured outputs (`output_config.format`, JSON schema with `additionalProperties: false`), keeping the Phoenix-side validation.
- HTTP receive timeout follows the seam deadline as the OpenAI adapters do.
- `LLM_PROVIDER=anthropic` selects Anthropic for the three seams; `RUBRIC_RESOLVER` still turns the resolver on. Unset keeps the OpenAI behavior unchanged.
- Never log prompts, learner text or provider output. No live calls in tests (Req.Test).

## Tasks

- [x] T1 — Shared Messages client (`StationAI.AnthropicClient`) + patient adapter (`StationAI.AnthropicAdapter`) with Req.Test tests: request shape, valid reply, refusal, timeout, HTTP error, missing key. Route: inline (single writer; this worker is the delegated writer).
- [ ] T2 — Resolver adapter (`RubricAssessment.Resolver.AnthropicAdapter`), structured output reusing the OpenAI resolver prompt/schema/parsing, receive timeout from the resolver deadline. Route: inline.
- [ ] T3 — Learner feedback adapter (`LearnerFeedback.AnthropicAdapter`), structured output (array of `{criterion_id, text}` mapped to the seam's map), receive timeout from the feedback deadline. Route: inline.
- [ ] T4 — `config/runtime.exs` selection (`LLM_PROVIDER`, `ANTHROPIC_*`) with tests that read the runtime config with and without the setting; README section. Route: inline.
- [ ] T5 — Live check on acute-appendicitis with `JEV_ADAPTER=typesafe` and Claude (user-run; needs keys). Pending.

## Checks

- Per task: focused `mix test <files>` RED then GREEN.
- Closure: local CI script (`mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`, `mix test`, web suite).

## Progress

- 2026-10-19: exploration done; plan above.
- 2026-10-19: T1 done (route: inline). RED: 14/14 new tests failing (`AnthropicAdapter` undefined). GREEN: 14/14. `mix format`, `mix compile --warnings-as-errors`, `mix credo --strict` clean.

## Next step

T1.
