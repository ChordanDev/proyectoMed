# 341 — Play stations with a patient and a companion

Issue: #341 (parent spec #326). Branch: `feat/341-patient-and-companion` → PR base `feat/326-production-launch`. Delivery strategy: `single-pr`. Test runner: `(cd backend && MIX_TEST_PARTITION=_issue341 mix test)` and `(cd voice-worker && uv run pytest)`; full gate: `local_ci.sh <worktree>`.

Why: real exam stations often have a companion (the mother of an infant, a relative of a polytrauma patient) who answers the anamnesis. Until now every fact of a case went into one patient voice and one profile.

## Specs

- **S1** (Issue #341 verbatim): "Stations can declare a companion besides the patient. The generator marks replies [PACIENTE], [ACOMPANHANTE] or [EXAMINADOR]; each actor answers with its own profile, facts and ElevenLabs voice; the voice worker labels each reply with its speaker; companion mandatory questions are asked near the end; a question criterion counts when asked to either actor."
- **S2** (AC verbatim): "A reference case with a companion (e.g. polytrauma) parses and plays"
- **S3** (AC verbatim): "Replies are attributed to the right actor and voice, and the speaker label reaches the client"
- **S4** (AC verbatim): "Single-actor stations behave as today"
- **S5** (AC verbatim): "Grading credits questions asked to the companion"
- **S6** (parent task constraints): "actors declared in the package; generator marker extended to [ACOMPANHANTE]; each actor answers with its own profile and facts; companion mandatory questions asked near the end (reuse whatever mechanism patient mandatory questions use, or add a minimal one); a question criterion counts when asked to either actor; voice keys mapped to ElevenLabs voice ids via config/env (no ids committed beyond the existing default); the voice worker labels every spoken reply with its speaker (keep one LiveKit track; add a speaker field to the published event — document it in docs/unreal-station-client.md for the Unreal client, tied to #322). Single-actor stations must behave exactly as today. Do NOT touch Accounts, auth, router, controllers or session auth (sibling #337 owns them)". Live check with Claude Haiku on the bronquiolite companion fixture.
- **S7** (invariants, AGENTS.md): internal modules under `backend/lib/backend/stations/`; `BackendWeb` untouched.

Assumptions (marked): a station has at most one companion, since one `[ACOMPANHANTE]` marker cannot tell two apart; the format rejects a second one. Patient mandatory questions keep today's behaviour in single-actor stations (they are listed facts; nothing asks them).

## Tasks

| ID | Specs | Route | Status | Evidence |
| --- | --- | --- | --- | --- |
| T1 | S1, S4, S6 | inline | done | RED 8/45 failing (`Addressee.split/2` undefined, no companion prompt, no companion rule) → GREEN 102/102 across prompt, addressee, marker, case-format tests. Addressee reads `[ACOMPANHANTE]` only for a station with a companion; multi-actor patient prompt (each actor's profile and facts, three markers); single-actor prompt byte-identical; at most one companion in the format |
| T2 | S1, S3, S4, S5 | inline | pending | Companion replies on text, voice and streamed voice: stored with `speaker`, shown to the generator with `[ACOMPANHANTE]`, verified/audited against the companion's own profile and facts; streamed sentences of a multi-actor station carry `speaker` and `voice`; grading evidence test |
| T3 | S1, S6 | inline | pending | Mandatory questions of a multi-actor station asked in the final minutes (per-turn prompt section) |
| T4 | S3, S6 | inline | pending | Voice worker: `speaker` on every published reply event, voice key → ElevenLabs voice id via `ELEVENLABS_VOICE_IDS`, one track; docs (`unreal-station-client.md`, `turn-addressee.md`, case format) |
| T5 | S2, S3 | inline | pending | Live check with Claude Haiku on the bronquiolite fixture |

Routing: all inline (one behaviour chain, dependent tasks; no writer trigger).

## Log

- **L1** (2026-10-25, parent orchestrator task, verbatim excerpt): "Build: actors declared in the package; generator marker extended to [ACOMPANHANTE]; each actor answers with its own profile and facts; companion mandatory questions asked near the end (reuse whatever mechanism patient mandatory questions use, or add a minimal one); a question criterion counts when asked to either actor; voice keys mapped to ElevenLabs voice ids via config/env (no ids committed beyond the existing default); the voice worker labels every spoken reply with its speaker (keep one LiveKit track; add a speaker field to the published event — document it in docs/unreal-station-client.md for the Unreal client, tied to #322). Single-actor stations must behave exactly as today."
- **L2** (2026-10-25, exploration): the case format (#330) already puts `actors` (role, voice, persona, tone, fact ids, mandatory question ids) in the package; every fact still lands in `revealable_facts`. Patient mandatory questions are plain `timed` facts in the prompt: no code asks them. Sessions are in-memory (ETS), so a `speaker` on a stored message is not a persisted format. The controller passes each streamed sentence map through (`Map.put(sentence, :type, "sentence")`), so `speaker`/`voice` reach the worker without a controller change; the non-streamed `committed` body is built field by field in the controller, so it carries no speaker (the worker reads a missing speaker as `patient`). Grading reads learner turns whatever their addressee, so a question to the companion is evidence like one to the patient.
- **L3** (2026-10-25, T1): `Backend.Stations.Actors` holds the actor lookups and per-speaker package views; the single-actor prompt function is untouched (`single_actor_prompt/1`), and the companion prompt is its own text because most sections differ (who speaks, two fact lists, three markers).
- **L4** (next step): T2.
