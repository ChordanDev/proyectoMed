# proyectoMed

Planning and specification repository for a Revalida clinical-practice MVP.
The application is a Vite + React + TypeScript web SPA (`web/`) talking to a
JSON-only Phoenix API (`backend/`). Issue source-of-truth lives on the
[GitHub issue tracker](https://github.com/ChordanDev/proyectoMed/issues); see
[`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md) for how agents
and humans interact with it.

This repository currently hosts the **runtime scaffold** for the planned stack.
The scaffold is intentionally minimal: one Vite + React + TypeScript SPA under
`web/`, one JSON-only Phoenix API without Ecto or HTML tooling, a deterministic
root test orchestrator, and baseline smoke coverage per runtime.
It adds no clinical, product, or `#12` behavior.

---

## Toolchain (pinned)

| Tool       | Version          | Source                                      |
| ---------- | ---------------- | ------------------------------------------- |
| Node       | `>=20.0.0`       | `web/package.json` `engines.node`           |
| npm        | `>=10.0.0`       | `web/package.json` `engines.npm`            |
| Vite       | `^5.4.19`        | `web/package.json` `devDependencies.vite`   |
| React      | `^18.3.1`        | `web/package.json` `dependencies.react`     |
| TypeScript | `~5.6.3`         | `web/package.json` `devDependencies.typescript` |
| Vitest     | `^2.1.9`         | `web/package.json` `devDependencies.vitest` |
| Elixir     | `1.20.2-otp-29`  | `backend/.tool-versions`                    |
| OTP        | `29.0.5`         | `backend/.tool-versions`                    |
| Phoenix    | `~> 1.8.13`      | `backend/mix.exs`                           |

The web SPA is managed under `web/` with `npm --prefix web`. The backend was
generated with:

- `mix phx.new backend --app backend --module Backend --no-html --no-ecto --no-assets --no-gettext --no-mailer --no-dashboard --no-install --no-agents-md --no-version-check`

Both front-end and back-end are wrapped by
[`scripts/scaffold.sh`](scripts/scaffold.sh) so the preflight, ordering,
version pin, and partial-output policy are testable and reproducible.

---

## Prerequisites and install

Install the pinned Node/npm and Elixir/OTP versions listed above, then install
both runtime dependency sets:

```sh
# Web SPA (Vite + React + TypeScript).
npm --prefix web install

# Backend (Phoenix / Elixir).
( cd backend && mix deps.get )
```

The process-level E2E suite also requires `mix` on `PATH` and permission to
bind ephemeral localhost ports. It starts a real Phoenix server and a local,
deterministic OpenAI-compatible mock; it needs neither an OpenAI credential nor
external network access. No separately running Vite or Phoenix server is
required.

The repository commits both lockfiles (`web/package-lock.json` and
`backend/mix.lock`) so a fresh clone builds deterministically.

---

## Run

```sh
# Web SPA — boots Vite dev server on http://localhost:5173.
npm --prefix web run dev

# Backend — boots the JSON API on http://localhost:4000.
( cd backend && mix phx.server )
```

The backend exposes health and Station HTTP routes. Representative responses:

```sh
$ curl -i http://localhost:4000/
HTTP/1.1 200 OK
content-type: application/json; charset=utf-8

{"status":"ok"}

$ curl -i http://localhost:4000/api/stations/active
HTTP/1.1 200 OK
content-type: application/json; charset=utf-8

{"station_id":"chest-pain-initial-assessment","version":"1.0.0","language":"pt-BR","display_title":"Avaliação inicial de dor torácica"}
```

During local development, Vite proxies `/api` requests to the Phoenix backend
at `http://localhost:4000`, avoiding a separate CORS dependency. Set
`VITE_API_URL` only when the API is hosted at a different origin; production
may instead serve the SPA and API from the same origin.

### Impressos (manual test)

Learners request Impressos (physical exam / labs / imaging / reports) by
free text during an active session. The backend matches the text against the
active package's authored impressos (normalized keyword substring match) and
releases every matched Impresso in authored order.

```sh
BASE=http://localhost:4000/api/stations/active

# Start a session.
SESSION_ID=$(curl -s -X POST "$BASE/sessions" \
  -H 'content-type: application/json' -d '{"audio_consent": false}' \
  | jq -r .session_id)

# Request an Impresso — decision "released", releases the matching exam.
curl -s -X POST "$BASE/sessions/$SESSION_ID/impressos/request" \
  -H 'content-type: application/json' \
  -d '{"text": "quero ver os sinais vitais"}' | jq

# Repeat the same request — decision "already_released", nothing new.
curl -s -X POST "$BASE/sessions/$SESSION_ID/impressos/request" \
  -H 'content-type: application/json' \
  -d '{"text": "quero ver os sinais vitais"}' | jq

# Ask for an exam the station does not carry — decision "unavailable".
curl -s -X POST "$BASE/sessions/$SESSION_ID/impressos/request" \
  -H 'content-type: application/json' \
  -d '{"text": "tomografia de crânio"}' | jq

# List everything released so far, in release order.
curl -s "$BASE/sessions/$SESSION_ID/impressos" | jq
```

---

## Voice session (LiveKit) — manual test

The real-time voice plane (#117) is not covered by the automated suites, which
run without production credentials. Verify it manually against a local
`livekit-server`.

**Install:**

```sh
brew install livekit livekit-cli
```

**Run a dev LiveKit server** (uses the well-known dev keys `devkey` / `secret`,
listening on `ws://127.0.0.1:7880`):

```sh
livekit-server --dev
```

**Start the backend** with LiveKit configured, then the web SPA as usual:

```sh
cd backend && LIVEKIT_URL=ws://127.0.0.1:7880 LIVEKIT_API_KEY=devkey \
  LIVEKIT_API_SECRET=secret mix phx.server

npm --prefix web run dev
```

**Checklist:**

1. Open the SPA, accept the audio consent checkbox, press **Conectar voz**.
   The browser prompts for microphone permission; the panel status moves to
   "Voz conectada" once granted.
2. From another terminal, confirm the room and the learner's published track
   (`lk room list` shows the room name, which carries the session id):

   ```sh
   lk room list --url http://127.0.0.1:7880 --api-key devkey --api-secret secret
   ROOM=station-session-xxxx   # paste the Name column from the table above
   lk room participants list "$ROOM" \
     --url http://127.0.0.1:7880 --api-key devkey --api-secret secret
   ```

   One participant (`learner-` followed by the session id) should show one
   published audio track.
3. Simulate the patient's audio track and confirm you can hear it in the
   browser:

   ```sh
   lk load-test --room "$ROOM" --audio-publishers 1 \
     --identity-prefix patient-test \
     --url ws://127.0.0.1:7880 --api-key devkey --api-secret secret
   ```

   (`lk room join --publish-demo` only publishes a demo *video* track; use
   `load-test --audio-publishers` for an audio track, or `room join --publish
   <file>.ogg` to publish a specific pre-encoded audio file.)
4. Press **Finalizar estação** and confirm the panel disconnects and the room
   disappears from `lk room list` (Phoenix deletes it on completion). Closing
   the tab also leaves the room; the periodic sweep (60 s) deletes rooms whose
   session expired or no longer exists.
5. Without `LIVEKIT_URL`/`LIVEKIT_API_KEY`/`LIVEKIT_API_SECRET` set on the
   backend, confirm the panel shows "Falha na conexão de voz" /
   `voice_unavailable`; session start and finish keep working.
6. Press **Conectar voz** repeatedly in a short burst to see the `429`
   rate-limit error surface in the panel.

**No secret reaches the browser:** open DevTools → Network while connecting
and confirm the only LiveKit-related payload is the short-lived
`POST .../voice` response (`url`, `token`, `room`, `identity`, `expires_at`);
`LIVEKIT_API_SECRET` never appears client-side.

## Voice transcription (Deepgram worker) — manual test

`voice-worker/` is a Python [LiveKit Agents](https://docs.livekit.io/agents/) worker
(#118). It joins every `station-session-*` room, asks Phoenix whether the session is
active and consented, streams only the learner microphone to Deepgram (`nova-3`,
`pt-BR`, keyterms from the station package `stt_keyterms`), publishes interim
transcripts to the room (data topic `transcript`) and POSTs each final utterance to
Phoenix with a monotonic `turn_id`. Phoenix commits each turn at most once. The web
does not render transcripts yet (#121). The patient reply Phoenix returns for each turn
is spoken by the same worker; see
["Patient speech (ElevenLabs)"](#patient-speech-elevenlabs--manual-test) below.

**Prerequisites:** the LiveKit setup from the previous section, `brew install uv`, and
a Deepgram API key.

**Start the backend** with a worker secret, as an IEx session so you can read the
committed turns:

```sh
cd backend && VOICE_WORKER_SECRET=dev-worker-secret LIVEKIT_URL=ws://127.0.0.1:7880 \
  LIVEKIT_API_KEY=devkey LIVEKIT_API_SECRET=secret iex -S mix phx.server
```

**Start the worker:**

```sh
cd voice-worker && uv sync
LIVEKIT_URL=ws://127.0.0.1:7880 LIVEKIT_API_KEY=devkey LIVEKIT_API_SECRET=secret \
  DEEPGRAM_API_KEY=<your-key> PHOENIX_URL=http://localhost:4000 \
  VOICE_WORKER_SECRET=dev-worker-secret uv run python worker.py dev
```

The worker log shows it registered with the LiveKit server.

**Checklist:**

1. Open the SPA, accept audio consent, press **Conectar voz**. Then:

   ```sh
   lk room list --url http://127.0.0.1:7880 --api-key devkey --api-secret secret
   ROOM=station-session-xxxx; SID=${ROOM#station-session-}
   lk room participants list "$ROOM" \
     --url http://127.0.0.1:7880 --api-key devkey --api-secret secret
   ```

   Two participants: `learner-$SID` and `voice-worker`.
2. Say a short sentence in Portuguese (e.g. "Onde dói? Desde quando começou a dor
   torácica?") and pause. Then:

   ```sh
   curl -s -H "authorization: Bearer dev-worker-secret" \
     localhost:4000/api/internal/voice/sessions/$SID
   ```

   `last_turn_id` is `1` and `keyterms` lists the station terms. Speak again: it
   becomes `2`. One utterance, even a long one, adds exactly one turn.
3. In the IEx shell, read the committed text:

   ```elixir
   {:ok, s} = Backend.Stations.get_session("<SID>"); s.messages
   ```

   Each turn is a `%{role: :learner, modality: :voice, text: ...}` in order.
4. Duplicates are ignored. Replay the last turn by hand:

   ```sh
   curl -s -X POST -H "authorization: Bearer dev-worker-secret" \
     -H "content-type: application/json" -d '{"turn_id": 1, "text": "repetido"}' \
     localhost:4000/api/internal/voice/sessions/$SID/transcripts
   ```

   It answers `{"status":"duplicate"}` and `s.messages` does not change.
5. Without the header (or with a wrong secret) the same `curl` answers `401`.
6. Reconnect: press **Desconectar voz**, then **Conectar voz**, speak again. The next
   turn continues the numbering (no turn is reused or duplicated).
7. Restart the worker (Ctrl-C, start again) and reconnect voice: numbering still
   continues from Phoenix's `last_turn_id`.
8. Start the worker with `DEEPGRAM_API_KEY=wrong`, connect and speak: the worker logs
   `voice worker stopped for session <id>: auth`, with no key, transcript or audio in
   the log. The station keeps working through text.
9. Press **Finalizar estação**: the room is deleted, the worker job ends, and a
   `curl` to the context endpoint answers `422` (`session_completed`).

   When the station time runs out instead, the transcripts endpoint answers `409`
   (`station_time_elapsed`): for a new turn at or after the deadline, for any turn on
   a session the timer completed, and for a reply that missed the grace window left
   to a turn already in flight at the deadline. It is a non-retryable end of session,
   so the worker must stop instead of retrying. `409` (`stale_generation`) is
   different: it drops one superseded or cancelled turn and the session keeps going.
10. The worker never logs transcript text: scan its output from steps 2–7 and confirm
    only lifecycle lines and session ids appear.

Worker unit tests (no credentials): `cd voice-worker && uv run python -m unittest`.

## Patient speech (ElevenLabs) — manual test

When Phoenix commits a learner turn it returns the approved patient reply to the worker
(`reply_text` with its `generation_id`, #119). The worker (#120) does two things with
it, in this order:

1. Publishes the approved text to the room (data topic `transcript`), so the reply can
   be read whatever happens to the audio.
2. Sends that text, and nothing else, to ElevenLabs streaming TTS and publishes the
   audio frame by frame on one patient audio track (`patient-voice`) of the
   `voice-worker` participant.

Playback is fenced by the turn's generation: a newer accepted turn, a barge-in on a
pending turn, a stale result or the learner disconnecting stops the provider stream,
clears the buffered audio and drops any frame that arrives late. Phoenix remains the
only text authority; the worker never composes, edits or retries reply text. Learner
speech over an answer that is already playing does not stop it by itself until the next
reply is accepted; that barge-in detection belongs to #121. The web
does not render these events yet (#121); the patient audio is already audible because
the SPA attaches the subscribed audio track.

**Worker environment** (never sent to the browser or published to the room):

| Variable              | Required | Purpose                                                                 |
| --------------------- | -------- | ----------------------------------------------------------------------- |
| `ELEVENLABS_API_KEY`  | yes      | ElevenLabs API key.                                                     |
| `ELEVENLABS_VOICE_ID` | yes      | Voice used for the patient.                                             |
| `ELEVENLABS_MODEL`    | no       | TTS model. Default `eleven_flash_v2_5` (low latency, supports pt-BR).   |

If the key or the voice id is missing the worker keeps transcribing and delivers every
reply as text followed by a `synthesis_failed` event.

**Room events** (all on data topic `transcript`, reliable, JSON):

| Event                 | Shape                                                                                   |
| --------------------- | --------------------------------------------------------------------------------------- |
| Learner transcript    | `{"session_id", "turn_id", "final", "text"}`                                            |
| Patient text          | `{"session_id", "turn_id", "generation_id", "role": "patient", "text"}`                 |
| Speech failure        | `{"session_id", "turn_id", "generation_id", "failure": "synthesis_failed"}`             |
| Text delivery failure | `{"session_id", "turn_id", "generation_id", "failure": "text_delivery_failed"}`         |
| Worker stopped        | `{"session_id", "error": "<kind>"}`                                                     |

`failure` is not fatal: the worker keeps serving the session. `synthesis_failed` covers
any provider error, provider disconnect or track publication error, and carries no
provider message; the patient text for that generation was already delivered.
`text_delivery_failed` means the room rejected the patient text event: the reply is
still spoken, and Phoenix keeps the approved text in the session transcript. `error`
still means the worker job stopped. Reply text is never logged; worker logs carry the session id, turn
id, generation id and failure kind only.

**Prerequisites** (on top of the Deepgram checklist above):

- The backend needs `OPENAI_API_KEY`: Station AI generates the reply text, and without
  it no turn gets a reply to speak.
- `LIVEKIT_URL` must be `ws://127.0.0.1:7880` for the local `livekit-server --dev`, in
  both the backend and the worker; the `.env.example` value is a cloud placeholder.
- `ELEVENLABS_VOICE_ID` must be a voice the API key may use. On the free plan, library
  voices answer `402 paid_plan_required`; use a default voice. Check a voice before
  starting the worker (expects `http 200`):

  ```sh
  curl -s -o /dev/null -w 'http %{http_code}\n' -X POST \
    "https://api.elevenlabs.io/v1/text-to-speech/$ELEVENLABS_VOICE_ID/stream?output_format=pcm_24000" \
    -H "xi-api-key: $ELEVENLABS_API_KEY" -H "content-type: application/json" \
    -d '{"text":"Olá, tudo bem?","model_id":"eleven_flash_v2_5"}'
  ```

- An API key restricted to the Text to Speech endpoint is enough.
- Browser extensions or VPNs that block local WebRTC make **Conectar voz** fail before
  the microphone prompt; use a browser profile without them.

Every voice reply passes through Jev verification (#127) before it is admitted. With the
default `Backend.Stations.JevDecision.DisabledAdapter` the turn fails closed with
`station_ai_unavailable` and nothing is spoken, so for this manual test start Phoenix
with `JEV_E2E_APPROVING_ADAPTER=true` (see
["E2E-only Jev adapter"](#e2e-only-jev-adapter)). Jev is the single gate on both
channels: the voice path speaks the verified reply exactly as the text path would show
it, and a reply that is denied or refused fails the turn with nothing spoken.

**Manual test** (continues the Deepgram checklist above, same backend):

1. Start the worker with the extra variables:

   ```sh
   LIVEKIT_URL=ws://127.0.0.1:7880 LIVEKIT_API_KEY=devkey LIVEKIT_API_SECRET=secret \
     DEEPGRAM_API_KEY=<your-key> ELEVENLABS_API_KEY=<your-key> \
     ELEVENLABS_VOICE_ID=<voice-id> PHOENIX_URL=http://localhost:4000 \
     VOICE_WORKER_SECRET=dev-worker-secret uv run python worker.py dev
   ```

2. Connect voice in the SPA and ask a question the station can answer (e.g. "Onde
   dói?"). The patient answers aloud in Portuguese shortly after you stop speaking.
   `lk room participants list "$ROOM" ...` shows one audio track published by
   `voice-worker`.
3. Ask a second question while the first answer is still playing: when the new reply
   is ready the old audio stops and only the new answer is heard.
4. Press **Desconectar voz** mid-answer, then **Conectar voz**: the interrupted answer
   does not resume and the next question is answered normally.
5. Restart the worker with `ELEVENLABS_API_KEY=wrong` and ask a question: no audio, the
   worker logs `speech stopped for session <id> turn <n> generation <n>:
   synthesis_failed` and keeps running; the next learner turn is still committed.
6. Scan the worker output: no reply text, API key or provider message appears.

---

## Test

The standard root command runs three explicit phases in order: web unit tests,
backend ExUnit, then process-level E2E scenarios.

```sh
bash scripts/test.sh
```

Focused and complete web commands:

```sh
# Web unit tests only (Vitest + @testing-library/react).
npm --prefix web run test:unit

# Backend tests only (ExUnit).
( cd backend && mix test )

# Process/API E2E scenarios only (Vitest starts a real Phoenix process).
npm --prefix web run test:e2e

# Complete web suite: web unit tests plus process-level E2E.
npm --prefix web test
```

The E2E suite is process/API integration, not browser automation. It drives the
web API client against a real Phoenix HTTP process and a deterministic local
provider mock. It covers these scenarios and expected outcomes:

- **Station E2E Happy Path:** starts a consented session, exchanges a learner
  message, finishes the session, and returns criterion-level feedback; invalid
  session access also returns the structured `404 session_not_found` error.
- **Station E2E Technical Failure:** converts an upstream provider failure into
  `502 station_ai_unavailable`, keeps unfinished feedback unavailable with
  `422 session_not_finished`, and permits recovery through a fresh session.
- **Station E2E Session Expiry:** rejects expired sessions with `410
  session_expired` (or `404 session_not_found` after purge), serves no stale
  result, and permits a fresh recovery session.

### E2E-only Jev adapter

Jev has no live provider yet, and its default adapter
(`Backend.Stations.JevDecision.DisabledAdapter`) fails closed: every patient
reply and every rubric decision is refused. The E2E harness therefore starts
Phoenix with `JEV_E2E_APPROVING_ADAPTER=true`, which selects
`Backend.E2ESupport.ApprovingJevAdapter` (`backend/e2e_support/`).

**This adapter bypasses Jev verification and is test-only.** It reads no text
and calls no provider: it verifies every patient reply, and it awards a
criterion its last authored level only when a learner evidence item exists to
cite, staying `uncertain` otherwise. The level and points in the E2E result
prove the result contract, not the quality of any assessment.

- It is compiled only for `dev` and `test` (`elixirc_paths` in
  `backend/mix.exs`) and is not compiled into `prod`.
- `backend/config/runtime.exs` honors the variable only in `dev`, where the
  harness runs; in `test` and `prod` it is ignored and the default adapter stays
  in place.
- Do not set the variable outside the E2E suite.

The runner is fail-fast. A failed phase exits with that phase's exact non-zero
status and prevents all later phases from running, so an E2E failure can occur
only after the web unit and backend phases have passed.

---

## Pull-request CI

Every pull request runs the `Pull Request Validation` GitHub Actions workflow.
It installs the web dependencies with `npm ci`, fetches the Phoenix
dependencies with `mix deps.get`, and then runs the single root command:

```sh
bash scripts/test.sh
```

The workflow reads its Node version from `web/package.json` and its Erlang
and Elixir versions from `backend/.tool-versions`.

---

## Available harnesses

| Script                                       | Purpose                                                                                  |
| -------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `scripts/scaffold.sh`                        | Sole generator boundary — preflight, git-root authority, Vite then Phoenix, partial preservation. |
| `scripts/test.sh`                            | Root test orchestrator — web unit, backend ExUnit, then process-level E2E.               |
| `tests/scripts/scaffold_red.sh`              | RED/GREEN acceptance tests for `scripts/scaffold.sh` (16 invariants).                   |
| `tests/scripts/test_red.sh`                  | Hermetic acceptance tests for three-phase ordering and exact fail-fast propagation.     |

Both shell acceptance harnesses use bash fake-command stubs over `PATH`, so
they are hermetic: no network access and no real npm/npx/mix or Vite/Phoenix
generators. The application E2E suite is separate: it starts a real local
Phoenix process while replacing only the external provider with a local mock.

```sh
# All RED harnesses from a clean state.
bash tests/scripts/scaffold_red.sh
bash tests/scripts/test_red.sh
```

---

## Limitations

### Audio / voice input

Voice runs over a LiveKit WebRTC room (#117): the browser publishes one
microphone track and subscribes to one patient audio track through
`livekit-client`, joined with a short-lived, session-scoped token minted by
`Backend.Stations` (`POST /api/stations/active/sessions/:id/voice`). LiveKit
carries media only; Phoenix stays the authority for session state and deletes
the room on completion, expiry, or learner exit. When LiveKit is not
configured on the backend, or the microphone permission is denied, the panel
reports the failure and the text path keeps working unaffected.
The `voice-worker/` Python process transcribes the learner microphone through
Deepgram and commits final utterances to Phoenix (#118), then speaks each reply
Phoenix approves through ElevenLabs on the patient audio track (#120).
`NoticeScreen` requires explicit audio consent whenever voice support is
enabled; callers can pass `voiceSupport={false}` for text-only mode. See
["Voice session (LiveKit) — manual test"](#voice-session-livekit--manual-test)
above for how to exercise it locally.

### Other known limitations

- **No persistence layer.** `--no-ecto` was chosen so the database adapter
  is a deliberate downstream decision (see `#13` evaluation). The router
  currently exposes health, active station, transcription, and synthesis endpoints.
- **No view layer.** The backend serves only JSON responses.

- **No strict TDD.** `openspec/config.yaml` keeps `strict_tdd: false`. The
  harness is available, but test-first discipline is left to the change that
  implements the first real capability.
- **Toolchain drift.** Pinned versions in `web/package.json` and
  `backend/.tool-versions` are the only supported way to reproduce the
  scaffold.

---

## Repository layout

```
.
├── AGENTS.md                    Agent conventions (issue tracker, triage labels).
├── docs/
│   └── agents/                  Agent reference docs.
├── web/                         Vite + React + TypeScript SPA.
├── backend/                     Generated Phoenix API.
├── scripts/
│   ├── scaffold.sh              Sole generator orchestrator.
│   └── test.sh                  Root test orchestrator.
├── tests/scripts/               RED harnesses for both scripts.
└── openspec/
    ├── config.yaml              SDD harness config; `strict_tdd: false`.
    ├── specs/                   Archived capability specs.
    └── changes/                 Active change folders (proposal → archive).
```

---

## See also

- [`openspec/changes/scaffold-expo-phoenix-runtime/`](openspec/changes/scaffold-expo-phoenix-runtime/) —
  the proposal, design, and tasks for the runtime scaffold (historical record).
- [`docs/agents/domain.md`](docs/agents/domain.md) — domain vocabulary.
- [`docs/agents/triage-labels.md`](docs/agents/triage-labels.md) — canonical
  five-label triage vocabulary used on GitHub Issues.
