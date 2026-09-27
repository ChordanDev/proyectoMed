# Feature: Establish the LiveKit WebRTC media session

Tracking task for GitHub Issue #117 (child of #116, Ticket 13; ADR-009 #114).
Parent branch: `feat/116-realtime-voice` (from `develop`; Draft PR to `develop`).
Feature branch: `feat/117-livekit-media-session` (PR to `feat/116-realtime-voice`, `Refs #117`).
Worktree: `Revalida-worktrees/117-livekit-media-session`.

## Objective

Add the real-time media plane for an active station: Phoenix issues a short-lived,
session-scoped LiveKit token through `Backend.Stations`; the Vite station feature joins the
room, publishes one microphone track, and plays one patient audio track. LiveKit owns media
transport only; Phoenix stays the authority for session state.

## Design decisions

- **Token signing with stdlib** (`:crypto` HMAC-SHA256 + `Jason`), no JWT dependency. Claims:
  `iss` = API key, `sub` = identity, `nbf`, `exp`, `video` grant with `roomJoin`, one `room`,
  `canPublish`, `canPublishSources: ["microphone"]`, `canSubscribe`, `canPublishData: false`.
  No `roomList`/`roomAdmin`/`roomCreate` for the learner.
- **Deterministic names**: room `station-session-<session_id>`, identity `learner-<session_id>`.
  One room and one identity per session, so reconnects cannot mint new rooms and LiveKit's
  duplicate-identity rule prevents overlapping learner connections.
- **TTL**: short join TTL (default 120 s), capped by the session `expires_at`.
- **Rate limit**: per-session sliding window (default 5 tokens / 60 s) in an ETS-backed
  `Backend.Stations.MediaSession` process; state loss only resets counters.
- **Cleanup authority is Phoenix**: `complete_session/2` and `discard_session/1` delete the
  room through the LiveKit RoomService (Twirp over `Req`); a periodic sweep lists
  `station-session-*` rooms and deletes those whose session is not active (covers expiry,
  invalidation, and backend restarts). Delete of a missing room counts as success (idempotent).
- **Unconfigured LiveKit** (`LIVEKIT_URL`/`LIVEKIT_API_KEY`/`LIVEKIT_API_SECRET` absent) →
  `503 voice_unavailable`; the text path is untouched.
- **Browser**: `livekit-client` behind an injected room factory; `useVoiceSession` state
  machine (`idle → connecting → connected ⇄ reconnecting → disconnected | failed`), no
  automatic re-mint loop; disconnect on finish, failure, and unmount.
- Telemetry counters deferred (amendment says "may"); no token, audio, or transcript is logged.

## TDD

Strict TDD enabled (source: global `~/.claude/CLAUDE.md`). Runners: `cd backend && mix test`,
`npm --prefix web test`. RED → GREEN → REFACTOR per task.

## Tasks

- [ ] T1 Backend: token module, `Stations.create_voice_session/2` (active, unexpired, consent,
  rate limit), `POST /api/stations/active/sessions/:id/voice` endpoint, config, param filtering.
  Route: delegated writer (writer trigger: 4+ non-trivial files).
- [ ] T2 Backend: RoomService adapter, room deletion on complete/discard, orphan sweep.
  Route: delegated writer (same trigger).
- [ ] T3 Web: `livekit-client`, API client method, `useVoiceSession`, `VoicePanel`, `App` wiring.
  Route: delegated writer (same trigger).
- [ ] T4 Docs: README manual test with `livekit-server --dev`, env vars.
  Route: bundled with T3 writer.
- [ ] T5 Jorge el curioso advisory review, fix confirmed findings.

## Acceptance Criteria

- Token issuance requires an active, unexpired session with audio consent; no LiveKit secret reaches the browser.
- `BackendWeb` calls only `Backend.Stations` for session/token operations.
- The browser connects over WebRTC, publishes one microphone track, and can receive one patient audio track.
- Room and tracks close when the station completes, expires, is invalidated, or the learner exits.
- Raw audio is neither persisted nor logged.
- The text path keeps working with no LiveKit room.
- Tests cover authorization, cross-session access, expired/replayed tokens, token storms,
  reconnect boundaries, cleanup, and browser state transitions without production credentials.

## Checks

`bash scripts/test.sh`, `mix format --check-formatted`, `mix compile --warnings-as-errors`,
`mix credo --strict`, `mix dialyzer`, `npm --prefix web run typecheck`, `npm --prefix web run lint`.

## Delivery

Forecast ~1,100 authored lines (> 400). User chose `single-pr` (2026-09-27): one PR
`feat/117-livekit-media-session` → `feat/116-realtime-voice`, one commit per task.

## API contract (shared by T1 and T3)

`POST /api/stations/active/sessions/:id/voice` (no body) →
`201 {"url", "token", "room", "identity", "expires_at"}` (`expires_at` ISO 8601 UTC).
Errors `{"error", "message"}`: 404 `session_not_found`, 410 `session_expired`,
422 `session_completed`, 403 consent code reused from the TTS controller, 429 `rate_limited`,
503 `voice_unavailable`.

## Evidence

- Commits: (pending)

## Next step

Ask the chain strategy, then T1.
