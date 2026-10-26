# 398 Integrate develop (Cartesia voice, Unreal voice) into the launch branch

Objective: merge `origin/develop` into `feat/326-production-launch` and move the launch voice features from ElevenLabs to Cartesia. Branch `chore/398-integrate-develop-cartesia` (PR to `feat/326-production-launch`). Delivery: single PR, one commit per task. Runners: `uv run python -m unittest` (voice-worker), `MIX_TEST_PARTITION=_issue398 mix test` (backend), `npm --prefix web test`, local CI script.

Why: `develop` replaced ElevenLabs with Cartesia for real-time speech (#360, #362) and added the Unreal voice link (#191) and fake voice providers; launch features #341, #342, #334, #337, #339 were built on ElevenLabs.

Constraints: keep both sides of every conflict; Unreal code is only textually merged (not built here); no ElevenLabs reference outside history (ADRs, changelogs, migrations, odd logs).

## Specs

- S1 "The launch branch contains every `develop` commit; local CI passes."
- S2 "No ElevenLabs reference remains in code, config or docs except history (ADR text, changelogs)."
- S3 "#341 per-actor voices: `ELEVENLABS_VOICE_IDS` (`key=id,...`) becomes a Cartesia voice map (e.g. `CARTESIA_VOICE_IDS`), keeping the voice keys infantil / masculina-adulta / feminina-adulta / masculina-idosa / feminina-idosa and `CARTESIA_VOICE_ID` as the default." Acceptance: "A companion station speaks each actor with its own Cartesia voice (worker tests), and a single-actor station uses `CARTESIA_VOICE_ID`."
- S4 "#342 usage metering: the voice worker reports Cartesia usage (characters or seconds, as Cartesia bills) and the price table gets a Cartesia row with its public price, source URL and date; ElevenLabs rows are removed." Acceptance: "Session usage records Cartesia usage and an estimated cost (tests)."
- S5 "#334 pre-station notice and #337/#339 docs: every place that names ElevenLabs names Cartesia, consistent with the #362 consent copy." Acceptance: "The pre-station notice lists Deepgram and Cartesia for real-time voice."
- S6 "docs/unreal-station-client.md, docs/operations/*, docs/research/production-infrastructure.md and README env tables."
- Assumption: the backend turn-based voice path (`VOICE_PROVIDER=deepgram_elevenlabs`, `Backend.Stations.TTS.ElevenLabs`) is code that names ElevenLabs, so S2 moves it to Cartesia (`VOICE_PROVIDER=deepgram_cartesia`).

## Tasks

| ID | Specs | Route | Status | Commit / evidence |
|---|---|---|---|---|
| T1 | S1 | inline | done | 23bebb5 merge; worker 189 tests, 4 errors (#341 tests on `worker.elevenlabs`, fixed by T2); backend 2432 passed |
| T2 | S3 | inline | done | a889e63; RED 4 of 8 BuildVoiceTTSTest failed (3 F, 1 E); GREEN worker 193 OK |
| T3 | S4 | inline | done | 29931f9; RED worker 5 F 2 E, backend KeyError `:cartesia_characters`; GREEN worker OK, backend 2432 passed |
| T4 | S2, S5 | inline | done | e08cca9; RED 9 failures (notice, transcription, TTS); GREEN backend 2432 passed |
| T5 | S2, S5, S6 | inline | done | 593ca77; docs only, structural check: `rg -i eleven` leaves history (SPEC_MVP, jev-prototype, spike-189, migrations, odd) and regression tests |
| T6 | S1 | inline | done | LOCAL CI PASSED: web 342, backend 2432, e2e 4; worker 193 OK; `git rev-list HEAD..origin/develop` = 0 |

- T2: worker `build_voice_tts` builds Cartesia voices from `CARTESIA_VOICE_IDS`.
- T3: worker reports `cartesia_characters`; backend usage column rename migration, price `cartesia_1k_characters`.
- T4: backend turn-based TTS adapter and pre-station notice move to Cartesia.
- T5: docs and env tables.
- T6: local CI.

## Log

- L1 (2026-10-25, user): "creo que lo de carthesia ya mi hermano lo metió en una issue ya, en algún PR. Issue 360, PR 362"
- L2: Cartesia pricing, https://cartesia.ai/pricing, read 2026-10-25: "1 credit equals 1 character"; Scale $299/month with 8M credits, overage $38 per 1M credits (Startup $45, Pro $65). Price table uses the Scale overage, $0.038 per 1,000 characters.
- L3: merge conflicts in README.md, backend/config/runtime.exs, docs/unreal-station-client.md and voice-worker/worker.py resolved keeping both sides; develop's Voice link section replaces the "lands with #191" paragraph.
- L4: Cartesia `/tts/bytes`, https://docs.cartesia.ai/api-reference/tts/bytes, read 2026-10-25: Bearer key, `Cartesia-Version: 2026-08-14`, mp3 needs `sample_rate` and `bit_rate`. Concurrency, https://docs.cartesia.ai/use-the-api/concurrency-limits-and-timeouts: Scale 15.
- L5: `session_usages.elevenlabs_characters` is renamed by a new migration (20261025190000) instead of editing the create migration, so databases that already ran it follow. The worker and Phoenix must deploy together: Phoenix now refuses a report without `cartesia_characters`.
- L6: Next step: PR to `feat/326-production-launch`; live checks pending (a real Cartesia key for the turn-based adapter and a companion station with `CARTESIA_VOICE_IDS`).
