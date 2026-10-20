# 301 - Rubric resolver: one call per criterion, in parallel, 30 s deadline

Issue: #301 (parent #237). Branch: `feat/301-rubric-resolver-parallel`, PR to
`feat/237-clinician-demo-readiness`.

## Objective

Stop the rubric resolver from leaving covered criteria "Incerto" for lack of
time, keep the educational result inside the web client's wait, and make a
finished session's grade stable across refreshes.

## Why

The 2026-10-20 spoken rehearsal (d9db2e7) showed 6 of 11 criteria uncertain,
including items the learner clearly covered. Log:
`Rubric resolver left undecided actions uncertain after 10001 ms: timeout`.
One request carried every undecided criterion under a 10 s deadline; a single
timeout lost all of them. The result was also recomputed on every fetch.

## Constraints

- Code-side validation of resolver answers is unchanged (performed must cite
  valid learner evidence, only from Jev's candidates when offered).
- A failure or timeout affects only its own criterion and never invalidates
  the attempt.
- Logs carry criterion ids, outcomes and latency only, never transcript text.
- `BackendWeb` stays thin; caching lives behind `Backend.Stations`.
- resolver + feedback deadlines fit inside `EDUCATIONAL_RESULT_TIMEOUT_MS`
  with margin.

## Checklist

- [x] T1 - Resolver sends one request per criterion with undecided actions,
  concurrently (bounded), under one overall deadline; a criterion that fails
  or times out stays uncertain, the others keep their decisions; per-criterion
  outcome/latency logs. Route: inline (one module plus its test).
- [ ] T2 - Default resolver deadline 30 000 ms; OpenAI adapter honours it as
  `receive_timeout`; feedback default and web timeout rebalanced; runtime caps
  keep resolver + feedback inside the budget; invariant test. Route: inline
  (small edits across config, adapter and client constant).
- [ ] T3 - Educational result graded once per finished session and served from
  the session afterwards (assessment cached in `Conversation`, per-session
  serialization of concurrent first fetches). Route: inline.
- [ ] T4 - Live check on acute-appendicitis with a transcript covering items
  1, 2 and 4; record per-criterion latencies and statuses. Route: inline
  (scratch script, no repository change).

## Checks

- `mix test` (backend), `npm --prefix web test` for the client constant.
- Local CI script (mirrors `pr-validation.yml`; GitHub Actions is blocked by
  billing) must print `LOCAL CI PASSED`.

## Progress

- T1 done in `d66f7ce`. RED: 4 new resolver tests failed (multi-criterion
  request crashed the per-criterion double). GREEN: `mix test
  test/backend/stations` 1035 passed. `issue_228_regression_test` updated to
  expect one request per criterion.
- T2: RED 6 failing (budget invariant x2, default 30 s, runtime caps, OpenAI
  receive timeout, feedback default 45 s). GREEN: backend `mix test` 1668
  passed; web `client.test.ts` 42 passed (its 80 s expectation moved to 95 s).
  Budget: resolver 30 s + feedback 45 s + 15 s margin <= web 95 s; runtime
  caps resolver at 40 s and feedback at 80 s minus the resolver deadline.

## Follow-ups (outside allowed edit surfaces)

- `README.md` (~798) and `docs/educational-result-api.md` (~30-35) still
  describe the 10 s / 60 s / 65 s cap / 80 s wait.
- `web/src/features/station/i18n/pt-BR.json` `loadingResultFeedbackWait` says
  "até um minuto"; the first fetch can now take up to ~95 s.

## Next step

T3.
