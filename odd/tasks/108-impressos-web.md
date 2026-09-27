# #108 Web Station client for Impressos: request modal & documents viewer

Parent: #105. Branch `feat/108-impressos-web` (from `feat/105-impressos` at 553e590, which merged
`origin/develop` after PR #111 brought `StationScreen`).

## Objective
Learners request Impressos from the web Station UI during the countdown and consult every released
document at any time.

## Backend contract (from #107)
- `POST /api/stations/active/sessions/:id/impressos/request` body `{text, request_id?}` →
  `{request_id, decision, released_impressos, newly_released, feedback_message}`.
- `GET /api/stations/active/sessions/:id/impressos` → `{released_impressos}`.
- Impresso: `{id, title, category, content}`. Errors `{error, message}`: 422 `invalid_request`,
  404 `session_not_found`, 410 `session_expired`, 409 `session_completed`.

## Tasks
- [x] T1 `client.ts`: `Impresso` types + decoders, `requestImpresso`, `getImpressos` (RED→GREEN)
- [ ] T2 `useStation`: `impressos` state + `requestImpresso` action; request errors do not fail the
      station (RED→GREEN)
- [ ] T3 `StationScreen`: exam button next to the input, request modal, feedback notice, impressos
      drawer (RED→GREEN)

## Acceptance criteria
The six criteria of issue #108.

## Checks
TDD: enabled (session config, Strict TDD Mode), runner `npm --prefix web test` (Vitest).
Close each task with `npm --prefix web test`, `npm --prefix web run typecheck`,
`npm --prefix web run lint`.

## Progress
- Base prepared: PR #111 merged into develop (ddf5555); develop merged into feat/105-impressos with
  3 additive conflicts resolved (impressos + Ticket 133 deadline). `mix precommit` 264 passed, web
  101 passed, typecheck ok. Push of feat/105-impressos pending (user).
- T1 done: added `Impresso`/`ImpressoDecision`/`RequestImpressoRequest`/`RequestImpressoResponse`/
  `ListImpressosResponse` types + decoders, `requestImpresso`/`getImpressos` client methods, and
  re-exports. RED confirmed (3 failing: `client.requestImpresso is not a function` /
  `client.getImpressos is not a function`). GREEN: web 104 passed (101 + 3 new), typecheck ok,
  lint ok.
