# #190 Start a station run from the Unreal client and meet the patient

Parent: #186, ADR-013 (#209). Branch `feat/190-unreal-station-run` from `origin/develop` (7d16ff4). Delivery: `ask-on-risk` with chain strategy `stacked-to-main` (each PR targets `develop` in order; slice 1 = T1+T2, the module and its documented interface; the last PR carries `Closes #190`). Checks: `Build.sh ProyectoMedEditor Mac Development`; Unreal automation tests (`Automation RunTests ProyectoMed.StationClient`) against a local Phoenix; `cd backend && mix test` if the backend changes; idle presence judged by the human (ChordanDev) by eye.

## Specs

Acceptance criteria quoted verbatim from #190:

- S1 "The Pre-Station Notice is shown before the station and must be acknowledged to continue."
- S2 "Starting the station creates an ephemeral session through the existing Phoenix HTTP API and loads the station content Phoenix serves for the scene."
- S3 "The MetaHuman patient is visible in the consultation scene with an idle, alive presence."
- S4 "A visible ten-minute countdown starts with the run."
- S5 "The client receives a short-lived credential scoped to one LiveKit room."
- S6 "The Unreal client holds no clinical rules and no Station Package content beyond what Phoenix serves."
- S7 "Automated tests exercise the station client module against a locally running Phoenix."
- S8 "Any behaviour missing from the Phoenix HTTP API is added and tested at that seam first."
- S9 "The public interface of the single station client module that owns Phoenix and LiveKit communication is defined and documented, so the parallel slices (#191, #192, #194, #195, #196) consume it without changing it; later changes to it are agreed by both Unreal tracks before they land."

Constraints:

- S10 The human chose to commit the scene's MetaHuman (~330 MB) to Git LFS in this PR: "Sí, a LFS (Recommended)". Check the LFS usage first and `git lfs lock` every `.uasset`/`.umap` before editing it.
- S11 In-client UI is native UMG; the MVP targets macOS and Windows desktop only. Scene and interface code depend on the station client module and never call the network directly.

## Tasks

- [x] T1 `StationClient` module: HTTP/JSON transport, active station, start, refresh and discard session, server-anchored countdown; automation tests against local Phoenix — S2, S4, S6, S7, S8 — inline — commit 094891a; RDD high, granted, approved and acknowledged (lineage review-bdd76c8eef08c303)
- [x] T2 Rest of the public interface (voice credential, turns, impressos, finish, result) with tests, and the interface doc `docs/unreal-station-client.md` — S5, S7, S9 — inline — commits 2efcadd and the advisory fix in L7; RDD high, granted, approved and acknowledged
- [ ] T3 UMG: Pre-Station Notice (pt-BR, audio consent), station brief from Phoenix, Station Timer; game flow wired to the module — S1, S2, S4, S11 — inline
- [ ] T4 Consultation scene with the MetaHuman in LFS and an idle, alive presence — S3, S10 — human + inline
- [ ] T5 Setup and runbook docs; human end-to-end check in the editor — S1–S5 — human + inline

## Log

- L1 (2026-10-21) User request: "Hacé la 190". Issue #190 body as quoted in Specs; labels `ready-for-agent`, `jorge:required`.
- L2 (2026-10-21) Phoenix map (explorer, sonnet): the public `/api/stations/*` routes have no auth, CSRF or CORS, and the session id acts as the bearer, so Unreal calls Phoenix directly with JSON on port 4000. `GET /api/stations/active` serves `display_title`, `candidate_brief{scenario,tasks}` and `voice_mode`. `POST /api/stations/active/sessions {audio_consent}` returns `started_at`, `deadline_at` (server-owned 10 min), `expires_at` (30 min) and `server_now`. `POST .../sessions/:id/voice` returns 201 `{url, token, room, identity, expires_at}`, with a 120 s join token scoped to `station-session-<id>`; it needs `audio_consent:true` and LiveKit env vars on Phoenix. The Pre-Station Notice text is not served by Phoenix: the SPA hardcodes it in `web/src/features/station/i18n/pt-BR.json`. It is UI copy, not Station Package content, so the Unreal client ships its own pt-BR copy (S6 holds). No HTTP API gap is known yet for S8.
- L3 (2026-10-21) LFS decision: the human answered "Sí, a LFS (Recommended)" to committing the MetaHuman in #190's PR (S10).
- L4 (2026-10-21) Delivery: the human chose "Encadenado a develop (Recommended)", that is `stacked-to-main` with `develop` as the base. Slice 1 (T1+T2) lands the module and its documented interface first, so #192/#194/#195 can start.
- L5 (2026-10-21) T1 evidence. RED: with a stub implementation, `scripts/run-unreal-tests.sh ProyectoMed.StationClient.Unit` failed the parse, clock and no-session tests (`EXIT CODE: -1`). GREEN: with the real implementation and a local Phoenix (`VOICE_MODE=realtime LIVEKIT_URL=ws://127.0.0.1:7880 LIVEKIT_API_KEY=devkey LIVEKIT_API_SECRET=secret mix phx.server`), `scripts/run-unreal-tests.sh ProyectoMed.StationClient` passed 20 of 20 (`EXIT CODE: 0`): 12 unit and 8 Phoenix tests. The Phoenix tests confirm `deadline_at - started_at` is ten minutes, served by Phoenix (S4), and that a discarded session answers 404. S8: no HTTP API gap found for T1.
- L6 (2026-10-21) T2 evidence. RED: with stubs, 15 new tests failed (`EXIT CODE: -1`). GREEN: `scripts/run-unreal-tests.sh ProyectoMed.StationClient` passed 36 of 36 against local Phoenix. S5: the voice credential test checks room `station-session-<id>`, identity `learner-<id>` and an expiry within five minutes; a run without consent gets 403 `no_consent`. Patient replies and results need Phoenix's LLM provider (no deterministic dev adapter exists: a curl probe got 502 `station_ai_unavailable` and 502 `invalid_attempt`), so their parsing is unit-tested on real shapes, and the doc tells the slices to add a deterministic seam to Phoenix first if they need one (S8). T1 RDD advisories handled: the timer reads zero once the run is completed; the runner fails when no test matches or the editor exits non-zero. Not changed: discard always answers 204 in Phoenix (`StationController.discard/2`), so the "discard 404 wedges the client" advisory cannot occur; a start that times out client-side may leave a Phoenix session that expires after 30 minutes.
- L7 (2026-10-21) T2 RDD (four lenses) approved and acknowledged with eight non-blocking advisories. Applied the ones that affect the shared contract: `RefreshSession` skips transcript lines with an unknown speaker instead of failing (RED: the new unit test failed; GREEN: 37 of 37); the docs say `SendTurn` is not idempotent and that a retrying caller creates its own impresso request id; a misleading helper comment is fixed. Left as follow-ups: `FinishSession` and `FetchResult` do not use the shared send helper (readability only), and there is no full turn round-trip test without an LLM provider.
- L8 (2026-10-21) Fix commit d3c478a assessed medium, under_budget (no review due). Slice 1 (T1+T2, 094891a..d3c478a, about 2.4k lines with tests and docs) is ready for a PR to develop; push and PR await the human.
- L19 (2026-10-21) Jorge review of PR #320: CHANGES REQUESTED, with 1 blocker and 4 warnings. The human chose "Todos, T4 solo doc (Recommended)". New `ProyectoMed.StationClient.FakePhoenix` spec serves a fake Phoenix in-process (`HTTPServer`, non-shipping only) to control timing. RED: all three tests failed for Jorge's reasons (`network_error` at 15 s; `CompletedAt` lost on refresh; a late `active` refresh reopened a finished run). Fixes:
  - T1 (blocker): `FetchResult` waits 95 s, as the web client does.
  - T3: `RefreshSession` never reopens a run this client saw finish and keeps `CompletedAt`, and `FinishSession` writes only the closing fields onto the live session.
  - T2, T4 and T5 are doc changes: retry after `reply_verification_failed`, behaviour after the Mac sleeps, and the 409 `session_completed` from impressos together with the rule to branch on `Code`. The doc example now captures the client weakly.
  GREEN: `scripts/run-unreal-tests.sh ProyectoMed` passed 40 of 40 on this branch.
