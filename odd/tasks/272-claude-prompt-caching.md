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
- [x] T2 Patient: split base prompt (cached) from withheld section (uncached); prefix byte-identical across two turns (tests).
- [x] T3 Docs: README Claude section on caching and the debug log; live check recorded as pending.

## Routing

All tasks inline in this bounded writer (one writer, issue-scoped surfaces).

## Checks

- Focused: `mix test test/backend/station_ai test/backend/stations/learner_feedback/anthropic_adapter_test.exs test/backend/stations/rubric_assessment/resolver_anthropic_adapter_test.exs test/backend/station_ai_test.exs test/backend/stations/station_ai_test.exs`
- Closure: local CI script (`LOCAL CI PASSED`).
- Live check (pending, needs a key): from the second patient turn on,
  `cache_read_input_tokens > 0`; report patient latency before/after.

## Progress

- T1 (inline) `fbfb089` feat(station-ai): cache the stable system prefix of Claude requests.
  RED: 7 failures (5 new client tests, resolver and feedback payload asserts).
  GREEN: focused 25/25; full backend 1277/1279 until the two patient asserts
  moved to the block form, then station_ai 60/60.
- T2 (inline) `15006d0` split the patient prompt. RED: 3 failures (2 `system_prompt_parts/2`
  tests, the withheld suffix assert); the byte-identical two-turn test already
  passed after T1 and stays as a guard. GREEN: full backend 1282/1282.
- Measured stable prefixes (chars): appendicitis patient 6292 (caches),
  chest-pain patient 1882 (near the 512-token minimum), resolver system 977 and
  feedback system about 1300 (likely below 512 tokens: the marker is a silent
  no-op there until the prefix grows; see follow-ups).

## Follow-ups

- Resolver and feedback: their stable part is only the fixed system prompt
  (rubric criteria are mixed with per-session decide/context splits in the user
  JSON shared with the OpenAI resolver). Moving the rubric ahead of the
  breakpoint needs a prompt-contract change, out of scope here.
- Patient conversation tail: top-level automatic caching would also cache the
  growing history; left out so per-turn content stays outside the cache.

- T3 (inline) README section on caching and the debug log (passive docs, no
  RED; structural readback).
- Local CI: LOCAL CI PASSED (see PR evidence).

## Next step

Live check (pending, needs `ANTHROPIC_API_KEY`): run a station with the logger
at debug, confirm `cache_read_input_tokens > 0` from the second patient turn,
and report patient `latency_ms` before/after.
