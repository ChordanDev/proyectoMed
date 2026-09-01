## Parent

Part of #22

## What to build

The Expo client foundation: a typed HTTP client, a `useStation` hook, the `NoticeScreen`, and pt-BR i18n strings. After this ticket the app can call the API and render the pre-station notice, but the station and result screens are still placeholders.

## Acceptance criteria

- [ ] `mobile/src/api/client.ts` exposes `getActiveStation`, `startSession`, `sendMessage`, `finishSession`, `fetchResult` with typed inputs and outputs and a typed `ApiError`.
- [ ] `mobile/src/i18n/pt-BR.json` contains every learner-facing string used by the app. No English strings in learner-facing copy.
- [ ] `mobile/src/hooks/useStation.ts` owns the session lifecycle and exposes `start`, `send`, `finish`, `result`, `status`, `error`.
- [ ] `mobile/src/screens/NoticeScreen.tsx` renders the educational-use notice and an "Entendi" button that triggers `start`.
- [ ] On any API error, the hook surfaces a pt-BR message and offers "Reiniciar estação".
- [ ] Jest coverage: `client.test.ts`, `useStation.test.ts`, `NoticeScreen.test.tsx`.
- [ ] `bash scripts/test.sh` exits 0 (Jest smoke + ExUnit still green).

## Blocked by

- #28 (StationController)
