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
- [ ] T3 — Live check on the Deepgram prerecorded API with an ElevenLabs TTS clip,
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

## Next step

T3 (live check), then local CI.
