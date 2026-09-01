## Parent

Part of #22

## What to build

A `BackendWeb.StationController` and router scope that exposes the JSON API used by the Expo client. Endpoints cover starting a session, sending a learner message (text only; voice is transcribed on-device), finishing a station, and fetching the result. Error codes follow the spec.

## Acceptance criteria

- [ ] Router adds `scope "/api/stations", BackendWeb` without removing the existing `HealthController` route.
- [ ] `GET /api/stations/active` returns `{ station_id, version, display_title, language }`.
- [ ] `POST /api/stations/active/sessions` returns `{ session_id, started_at, expires_at, server_now }`.
- [ ] `POST /api/stations/active/sessions/:id/messages` accepts `{ role: "learner", modality: "voice" | "text", text }` and returns `{ reply_text, reply_audio_url?, server_now }`. Returns 410 on expired sessions, 404 on unknown ids.
- [ ] `POST /api/stations/active/sessions/:id/finish` accepts `{ reason: "user" | "timer" }` and returns `{ session_id, completed_at }`.
- [ ] `GET /api/stations/active/sessions/:id/result` returns the per-criterion feedback or 410 if the session expired before completion.
- [ ] All errors return `{ "error": "code", "message": "human-readable pt-BR" }`.
- [ ] ExUnit coverage: `BackendWeb.StationControllerTest` exercises every endpoint and every documented error code.
- [ ] `bash scripts/test.sh` exits 0.

## Blocked by

- #26 (StationAI) and #27 (Evaluator)
