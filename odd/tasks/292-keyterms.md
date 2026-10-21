# 292 — Give Deepgram the station's medical vocabulary automatically

Locator: `odd/tasks/292-keyterms.md` · Engram mirror: `odd/292-keyterms/tasks` · Issue #292 · Parent #237
Branch: `feat/292-stt-keyterms` (base `feat/237-clinician-demo-readiness`)

## Objective

The voice worker's Deepgram nova-3 `keyterm` list is derived automatically from the
active Station Package, so clinical vocabulary (eponyms such as McBurney, Blumberg,
Rovsing; terms such as palpação, fossa ilíaca direita) is boosted without authoring
`stt_keyterms` by hand.

## Why

The 2026-10-20 rehearsals transcribed "Blumberg" as "Bloomberg", "McBurney" as
"Magburn" and "palpação" as "Parpação", which also degraded Jev's "asked" scores.
acute-appendicitis has no `stt_keyterms`, so the list sent to Deepgram was empty.

## Constraints

- Deterministic derivation (same package in, same ordered list out), tested.
- Explicit `stt_keyterms` always kept and listed first.
- Respect Deepgram limits. Primary source https://developers.deepgram.com/docs/keyterm:
  "Key Terms are limited to 500 tokens per request"; recommended "the most important
  20-50 terms"; multi-word phrases are one keyterm; repeat `keyterm` per term.
  The tokenizer is not published, so the cap is 50 terms and a conservative estimated
  budget (ceil(chars / 2) per term, at most 450) below the 500-token hard limit.
- livekit-plugins-deepgram 1.8.3 (voice-worker/uv.lock) sends a `keyterm` list via
  `urlencode(..., doseq=True)`, i.e. one repeated parameter per term: no worker change.
- Internal module under `backend/lib/backend/stations/`; `Backend.Stations` stays the
  only public interface; `BackendWeb` untouched.

## Acceptance criteria

- acute-appendicitis voice context contains McBurney, Blumberg, palpação and fossa
  ilíaca direita without editing the package (tested).
- Explicit `stt_keyterms` still included; the list respects the cap (tested).
- Live check: "Na palpação há dor no ponto de McBurney, sinal de Blumberg positivo"
  transcribes those terms correctly (prerecorded API on a TTS clip, with/without keyterms).

## Tasks

- [x] T1 — `Backend.Stations.SttKeyterms.for_package/1`: explicit terms, eponyms after
  anchor nouns (sinal/ponto/manobra/...), shared pt-BR lexicon terms present in the
  package text, impresso keywords; case-insensitive dedupe; cap. Unit tests.
  Route: inline (one new module + one test file, already understood).
- [x] T2 — Wire into `Backend.Stations.voice_worker_context/1`; context test on the
  acute-appendicitis package; README voice section. Route: inline (mechanical).
- [x] T3 — Live check on the Deepgram prerecorded API with an ElevenLabs TTS clip,
  with and without keyterms; record both transcripts here. Route: inline (no source).

## Checks

- `cd backend && mix test` (focused, then full), `mix format --check-formatted`, `mix credo` as in CI.
- Local CI script: must print `LOCAL CI PASSED`.

## Progress

- T1 done (inline). RED: 13/13 failing (module undefined), then 1/14 failing for the
  case-insensitive lexicon test; GREEN: 14/14. Checks: format, compile
  --warnings-as-errors, credo --strict on the new files. Derived lists: acute-appendicitis
  50 terms / 331 est. tokens; chest-pain 50 / 317 (authored 8 kept first).
  Commit `69f4000`.
- T2 done (inline). RED: voice context test for acute-appendicitis failed (1/2 passed,
  keyterms empty); GREEN: 2/2. Full `mix test`: 1587 passed; credo --strict clean.
  Commit `3b3a5d7`.
- T3 done (live check, no source change). Sentence "Na palpação há dor no ponto de
  McBurney, sinal de Blumberg positivo." synthesized with ElevenLabs (station voice) and
  sent to the Deepgram prerecorded API (`nova-3`, `pt-BR`, `smart_format`), with no
  keyterms and with the 50 derived acute-appendicitis keyterms:
  - `eleven_flash_v2_5` clip (4.1 s): without → "Na palpação, adorno, ponto de McBurney,
    sinal de bloomberg positivo."; with → "Na palpação, adorno, ponto de McBurney, sinal
    de Blumberg positivo."
  - `eleven_multilingual_v2` clip (5.0 s): without → "Na palpação, há dor sinal de
    Bloomberg positivo."; with → "Na palpação, há dor sinal de Blumberg positivo."
    "no ponto de McBurney" is dropped with and without keyterms (also with only 4
    keyterms), so it looks like that TTS rendering, not the list.
  - Outcome: Blumberg fixed by keyterms in both clips; palpação and McBurney correct
    where spoken clearly; "há dor no" → "adorno" is a short-word error keyterms do not
    target. A human spoken check in a live session is still pending.

## Next step

Local CI, push, PR to `feat/237-clinician-demo-readiness`; human live-session check.
