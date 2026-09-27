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
- [x] T2 `useStation`: `impressos` state + `requestImpresso` action; request errors do not fail the
      station (RED→GREEN)
- [x] T3 `StationScreen`: exam button next to the input, request modal, feedback notice, impressos
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
  lint ok. Commit 17ade3c.
- T2 done: `useStation` gained `impressos`/`impressoError` state and a `requestImpresso(text)`
  action; a failed request sets `impressoError` (ApiError message or a pt-BR fallback) and keeps
  the station active — it never calls `fail()`. No-op (resolves null) without a live session.
  Resuming an active session (refresh) also restores previously released impressos via
  `getImpressos`, best-effort. RED confirmed (5 failing: `requestImpresso is not a function` x2,
  wrong impressoError state, undefined impressos on resume). GREEN: web 109 passed (104 + 5 new),
  typecheck ok, lint ok. Commit ebf486f.
- T3 done: `StationScreen` gained a required `onRequestImpresso` prop (+ optional `impressos`,
  `impressoError`), an exam-request button (`impresso-request-button`) next to the message input, a
  request modal (`role="dialog"`, labelled textarea, submit/cancel, Escape-to-close), a
  `role="status"` feedback notice showing `feedback_message` after each request, and an
  always-available collapsible `impresso-drawer` listing released impressos with full content on
  selection. `impressoError` is shown inside the still-open modal on failure. Added pt-BR keys
  (`impressoRequestButton`, `impressoModalTitle`, `impressoModalLabel`, `impressoModalSubmit`,
  `impressoModalCancel`, `impressoDrawerToggle`, `impressoDrawerEmpty`) and wired `App.tsx` to
  `station.requestImpresso`/`impressos`/`impressoError`. RED confirmed (8 failing: no dialog role
  found, `impresso-request-button`/`impresso-drawer-toggle` test ids missing, etc.). GREEN: web
  117 passed (109 + 8 new), typecheck ok, lint ok (fixed 4 jsx-a11y errors on the modal backdrop by
  dropping click-outside-to-dismiss in favor of Escape + explicit Cancel button).

Product decisions made while implementing (for review):
- Impresso request button placed inside `.station-input-area`, between the text input and the
  voice/send buttons (reuses the existing `disabled` prop, i.e. disabled only when the countdown
  has elapsed, matching every other control in that row).
- Modal has no click-outside-to-dismiss (only Escape and an explicit Cancel button) to keep the
  backdrop non-interactive and avoid jsx-a11y violations.
- On a failed request, the modal stays open and shows `impressoError` inline (via
  `data-testid="impresso-error"`); on success it closes and the feedback message is shown as a
  separate page-level notice (`impresso-feedback`).
- The impressos drawer is a single always-rendered, collapsible panel below the input area (not
  gated by `disabled`), so documents remain browsable even once the countdown elapses.

## Commits
- T1: 17ade3c feat(station): add impresso client methods (Refs #108)
- T2: ebf486f feat(station): add impresso state and request action to useStation (Refs #108)
- T3: 6e9ad29 feat(station): add impresso request modal and drawer to StationScreen (Refs #108)
