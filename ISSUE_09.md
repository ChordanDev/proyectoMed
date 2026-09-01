## Parent

Part of #22

## What to build

An end-to-end integration test that exercises the full learner loop against the real Phoenix API, run from Jest and wired into `scripts/test.sh`. The test must cover the happy path, the technical-failure path, and the session-expiry path using pt-BR fixtures.

## Acceptance criteria

- [ ] `mobile/__tests__/integration/stationFlow.test.ts` boots the Phoenix endpoint and runs: start → multiple messages → manual finish → result. Asserts the per-criterion shape and pt-BR strings.
- [ ] A second integration case asserts the technical-failure path: forcing a 5xx response invalidates the station and shows the pt-BR recovery notice; no partial feedback is rendered.
- [ ] A third integration case asserts the session-expiry path: an aged session returns 410 and the client offers a restart.
- [ ] All three integration tests run under `bash scripts/test.sh`.
- [ ] `README.md` documents how to run the integration suite locally.

## Blocked by

- #30 (StationScreen + ResultScreen)
