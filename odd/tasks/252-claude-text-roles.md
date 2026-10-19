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
- [x] T2 — Resolver adapter (`RubricAssessment.Resolver.AnthropicAdapter`), structured output reusing the OpenAI resolver prompt/schema/parsing, receive timeout from the resolver deadline. Route: inline.
- [x] T3 — Learner feedback adapter (`LearnerFeedback.AnthropicAdapter`), structured output (array of `{criterion_id, text}` mapped to the seam's map), receive timeout from the feedback deadline. Route: inline.
- [x] T4 — `config/runtime.exs` selection (`LLM_PROVIDER`, `ANTHROPIC_*`) with tests that read the runtime config with and without the setting; README section. Route: inline.
- [ ] T5 — Live check on acute-appendicitis with `JEV_ADAPTER=typesafe` and Claude (user-run; needs keys). Pending.

## Checks

- Per task: focused `mix test <files>` RED then GREEN.
- Closure: local CI script (`mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`, `mix test`, web suite).

## Progress

- 2026-10-19: exploration done; plan above.
- 2026-10-19: T1 done (route: inline). RED: 14/14 new tests failing (`AnthropicAdapter` undefined). GREEN: 14/14. `mix format`, `mix compile --warnings-as-errors`, `mix credo --strict` clean. Commit `24d601f`.
- 2026-10-19: T2 done (route: inline). RED: 8/8 new tests failing (`Resolver.AnthropicAdapter` undefined). GREEN: 8/8; `test/backend/stations/rubric_assessment/` 197 passed. The OpenAI resolver answer decoder is now public (`decode_answer/1`) and shared, so both providers apply the same strict decoding. Commit `53aa475`.
- 2026-10-19: T3 done (route: inline). RED: 10/10 new tests failing (`LearnerFeedback.AnthropicAdapter` undefined). GREEN: 10/10; feedback tests 54 passed. Structured outputs need closed objects, so the answer is a list of `{criterion_id, text}` entries mapped to the seam map. Commit `9701a63`.
- 2026-10-19: T4 done (route: inline). RED: 3/7 new runtime-config tests failing (the 4 unchanged-behavior tests already passed). GREEN: 7/7. `LLM_PROVIDER=anthropic` selects the three Claude adapters; `RUBRIC_RESOLVER` (`on`, or `openai` for compatibility) still turns the resolver on and `LLM_PROVIDER` picks its provider. README section and design-doc note added. Commit `8b6ec7c`.
- 2026-10-19: local CI (mirror of `pr-validation.yml`) passed at `8b6ec7c`: web unit 213 passed, backend `mix test` 1222 passed, process E2E 4 passed; format, warnings-as-errors and credo clean. GitHub Actions is blocked by billing.
- Pending: T5 live check (no key available to the writer). Open risk: the resolver deadline is 10 s; Opus 5.5 at `medium` effort may need `RUBRIC_RESOLVER_DEADLINE_MS` raised, to be measured in T5.

## Next step

T5 (live check, user-run, needs `ANTHROPIC_API_KEY`): `LLM_PROVIDER=anthropic RUBRIC_RESOLVER=on JEV_ADAPTER=typesafe ACTIVE_STATION_ID=acute-appendicitis`.
