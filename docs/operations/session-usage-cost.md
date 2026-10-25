# Session usage and cost

Issue #342. Every finished station session gets one row in `session_usages`
with what it used from each provider and an estimated USD cost. Operators read
the median cost per station from it.

## What is measured, and where

| Provider | Unit | Measured by |
|---|---|---|
| Claude (patient, rubric resolver, learner feedback, undecided-verdict adjudicator) | `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`, per model | Phoenix, from each 2xx Messages response (`usage`; for a stream, `message_start` plus the last `message_delta`) |
| Jev (TypeSafe System One) | requests that got an HTTP response | Phoenix |
| Deepgram | seconds of learner audio pushed to the STT stream | the voice worker |
| ElevenLabs | characters of reply text sent to synthesis | the voice worker |
| LiveKit | participant minutes in the room (the worker plus each learner connection) | the voice worker |

Audio never passes through Phoenix (ADR-013 #209), so the worker reports its
counts when its job ends:

```
POST /api/internal/voice/sessions/:id/usage
Authorization: Bearer $VOICE_WORKER_SECRET

{"report_id": "<LiveKit job id>", "deepgram_audio_seconds": 312.5,
 "elevenlabs_characters": 1830, "livekit_participant_minutes": 21.25}
```

`202 {"status": "recorded"}` on success, `400 invalid_usage` for a malformed
report, `404 session_not_found` / `410 session_expired` when the session is
gone, `401` without the secret. Counts are cumulative per `report_id`: a retried
report replaces the earlier one, and reports of two jobs of the same session
add up. A failed report is logged by kind and never stops the worker.

## When the row is written

The row is an upsert keyed by `session_id`, written when the session is
finished (`POST /sessions/:id/finish`, or the timer), again after the
educational result (grading and feedback call Claude after the finish), and
again after a worker report. The row is computed at the call and written in a
separate process, so a slow or unreachable database never delays the finish or
the result; a failed write is logged as `session usage not persisted` with the
error type only. A write never replaces a row computed later. A session that is never finished, or that expires
in memory before it is finished, has no row. Discarding a session drops its
in-memory counters, never an existing row.

## Content-free

The row holds the session id, the station id and version, start and finish
times, the counts above, the cost per provider (`cost_by_provider`), any Claude
model without a price (`unpriced_models`) and `estimated_cost_usd`. It holds no
user id, transcript, reply, prompt or audio (ADR-001, ADR-009). The session id
is the ephemeral station session's id and links to nothing else in the
database.

## Price table

Defaults live in `backend/config/runtime.exs` with their sources (read on
2026-10-25). All prices are USD.

| Entry | Default | Source |
|---|---|---|
| `claude-haiku-5-5` per MTok: input / output / cache read / 5-minute cache write | 0.10 / 0.50 / 0.01 / 0.125 | <https://platform.claude.com/docs/en/about-claude/pricing> (prompts up to 100,000 tokens) |
| `claude-sonnet-5-5` per MTok | 2.00 / 10.00 / 0.10 / 2.50 | same |
| `claude-opus-5-5` per MTok | 4.00 / 20.00 / 0.20 / 5.00 | same |
| `deepgram_minute` (Nova-3 streaming, Pay As You Go) | 0.0048 | <https://deepgram.com/pricing> |
| `elevenlabs_1k_characters` (Flash) | 0.04 | <https://elevenlabs.io/pricing/api> (not labeled as the overage rate) |
| `livekit_participant_minute` (WebRTC, Ship overage) | 0.0005 | <https://docs.livekit.io/home/cloud/quotas-and-limits/> |
| `jev_call` | 0 | no public price page; set it from the contract |

`USAGE_PRICES_JSON` overrides entries with an object of the same shape. A model
entry replaces that model's four prices; a model not in the table is listed in
`unpriced_models` and adds nothing to the cost.

```
USAGE_PRICES_JSON='{"jev_call": 0.001, "deepgram_minute": 0.0042,
  "claude": {"claude-haiku-5-5": {"input": 0.1, "output": 0.5,
  "cache_read": 0.01, "cache_write": 0.125}}}'
```

Invalid JSON stops the boot. An unknown key, a model without all four prices or
a negative or non-numeric price raises when a cost is estimated, and the row is
not written (logged as `session usage not persisted reason=ArgumentError`).

The estimate is a list-price estimate: plan fees, included minutes, prepaid
discounts and Haiku's higher price above 100,000 prompt tokens are not modeled.
A row keeps the cost computed with the prices at the time it was written.

## Median cost per station

From a release:

```
bin/backend rpc 'IO.inspect(Backend.Stations.session_cost_report(~U[2026-11-21 00:00:00Z], ~U[2026-11-22 00:00:00Z]))'
```

From a checkout: `cd backend && mix run -e '...'` with the same expression. It
returns, per `station_id`, the number of sessions finished in `[from, to)`,
`median_cost_usd` and `total_cost_usd`.

The same report in SQL:

```sql
SELECT station_id,
       count(*) AS sessions,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY estimated_cost_usd::double precision)
         AS median_cost_usd,
       sum(estimated_cost_usd) AS total_cost_usd
FROM session_usages
WHERE finished_at >= '2026-11-21T00:00:00Z' AND finished_at < '2026-11-22T00:00:00Z'
GROUP BY station_id
ORDER BY station_id;
```

Per provider, replace the cost column with, for example,
`(cost_by_provider->>'claude')::double precision`.

## Example

A live 10-turn text station (acute appendicitis, 2026-10-25) with every Claude
seam on `claude-haiku-5-5`, Jev live, finished and graded with feedback:
8,298 input, 2,258 output, 36,450 cache-read and 6,061 cache-write tokens, 13
Jev calls, estimated Claude cost USD 0.003081 (no audio: text only).
