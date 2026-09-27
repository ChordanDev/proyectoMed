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

## Install

```sh
# Web SPA (Vite + React + TypeScript).
npm --prefix web install

# Backend (Phoenix / Elixir).
( cd backend && mix deps.get )
```

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
   lk room participants list station-session-<session_id> \
     --url http://127.0.0.1:7880 --api-key devkey --api-secret secret
   ```

   One participant (`learner-<session_id>`) should show one published audio
   track.
3. Simulate the patient's audio track and confirm you can hear it in the
   browser:

   ```sh
   lk load-test --room station-session-<session_id> --audio-publishers 1 \
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

---

## Test

The root entry point runs web Vitest and Phoenix ExUnit in sequence and
propagates the first non-zero exit from either suite:

```sh
bash scripts/test.sh
```

Equivalent per-runtime commands:

```sh
# Web SPA (Vitest + @testing-library/react).
npm --prefix web test

# Backend (ExUnit).
( cd backend && mix test )
```

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
| `scripts/test.sh`                            | Root test orchestrator — `npm --prefix web test` then `( cd backend && mix test )`.     |
| `tests/scripts/scaffold_red.sh`              | RED/GREEN acceptance tests for `scripts/scaffold.sh` (16 invariants).                   |
| `tests/scripts/test_red.sh`                  | RED/GREEN acceptance tests for `scripts/test.sh` (ordering + exit-code propagation).    |

Both RED harnesses use bash fake-command stubs over `PATH`, so they are
hermetic: no network access and no real npm/npx/mix or Vite/Phoenix generators.

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
