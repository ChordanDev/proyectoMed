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
| T2 | S3 | inline | todo | |
| T3 | S4 | inline | todo | |
| T4 | S2, S5 | inline | todo | |
| T5 | S2, S5, S6 | inline | todo | |
| T6 | S1 | inline | todo | local CI |

- T2: worker `build_voice_tts` builds Cartesia voices from `CARTESIA_VOICE_IDS`.
- T3: worker reports `cartesia_characters`; backend usage column rename migration, price `cartesia_1k_characters`.
- T4: backend turn-based TTS adapter and pre-station notice move to Cartesia.
- T5: docs and env tables.
- T6: local CI.

## Log

- L1 (2026-10-25, user): "creo que lo de carthesia ya mi hermano lo metió en una issue ya, en algún PR. Issue 360, PR 362"
- L2: Cartesia pricing, https://cartesia.ai/pricing, read 2026-10-25: "1 credit equals 1 character"; Scale $299/month with 8M credits, overage $38 per 1M credits (Startup $45, Pro $65). Price table uses the Scale overage, $0.038 per 1,000 characters.
- L3: merge conflicts in README.md, backend/config/runtime.exs, docs/unreal-station-client.md and voice-worker/worker.py resolved keeping both sides; develop's Voice link section replaces the "lands with #191" paragraph.
