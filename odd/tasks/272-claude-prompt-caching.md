# 272 - Cache the stable prompt prefix in the Claude adapters

Issue: #272 (parent #237). Branch: `feat/272-claude-prompt-caching` from
`feat/237-clinician-demo-readiness`.

## Objective

Mark the stable prompt prefix of every Claude request with prompt-caching
`cache_control`, keep per-turn content after the breakpoint, and log (debug,
no content) the cache usage and generation latency so a live run shows hits.

## Why

Every patient turn resends the same system prompt (safety rules, patient
profile, revealable facts); the resolver and feedback resend their large
fixed system prompts. Generation dominated latency (1.1-1.7 s per patient turn
in the 2026-10-20 rehearsal).

## Constraints

- Caching is a prefix match (render order `tools -> system -> messages`): stable
  bytes first, no timestamps or ids in the cached part.
- Minimum cacheable prefix is 512 tokens on Claude Opus 5.5 and Claude Sonnet
  5.5; a shorter prefix silently does not cache (no error, no charge). One
  breakpoint at the end of the whole stable prefix keeps it as long as possible.
- Keep every request rule from #252/#256: per-model thinking fields, effort,
  `fallbacks: "default"` with its beta, deadlines/receive timeouts.
- Raw HTTP with Req; tests stub Req, no live calls.

## Design

- `AnthropicClient` renders `system` as text blocks: the stable `system` block
  carries `cache_control: {type: "ephemeral"}` (5-minute TTL); an optional
  `system_suffix` (per-turn) follows it without a marker. Messages stay after
  the breakpoint.
- The patient splits its system prompt with `StationAI.system_prompt_parts/2`:
  the base prompt (stable per station) is cached, the withheld-facts section of
  a regeneration (issue #242) is the uncached suffix.
- The resolver and feedback system prompts are static, so they are cached as is;
  their per-request JSON user message stays outside the prefix.
- `create_message/2` logs at debug level the model, `input_tokens`,
  `cache_read_input_tokens`, `cache_creation_input_tokens` and the request
  latency in ms; never the key, prompt or output.

## Checklist

- [x] T1 Client: cached stable system block, optional uncached suffix, debug usage/latency log; resolver and feedback carry the breakpoint (tests: client body + log, adapter payloads).
- [ ] T2 Patient: split base prompt (cached) from withheld section (uncached); prefix byte-identical across two turns (tests).
- [ ] T3 Docs: README Claude section on caching and the debug log; live check recorded as pending.

## Routing

All tasks inline in this bounded writer (one writer, issue-scoped surfaces).

## Checks

- Focused: `mix test test/backend/station_ai test/backend/stations/learner_feedback/anthropic_adapter_test.exs test/backend/stations/rubric_assessment/resolver_anthropic_adapter_test.exs test/backend/station_ai_test.exs test/backend/stations/station_ai_test.exs`
- Closure: local CI script (`LOCAL CI PASSED`).
- Live check (pending, needs a key): from the second patient turn on,
  `cache_read_input_tokens > 0`; report patient latency before/after.

## Progress

- (none yet)

## Next step

T1.
