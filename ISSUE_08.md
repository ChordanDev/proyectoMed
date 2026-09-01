## Parent

Part of #22

## What to build

The Expo station and result screens. The user starts the timer, talks or types to the Station AI, finishes manually or at zero, and lands on a per-criterion feedback view with highlighted transcript excerpts and practice recommendations.

## Acceptance criteria

- [ ] `mobile/src/screens/StationScreen.tsx` shows a ten-minute countdown, the learner message input, the running transcript, and a "Finalizar estação" button. Microphone permission is requested via `expo-av`; text input is always available.
- [ ] When voice capture fails or permission is denied, the screen falls back to text-only for the rest of the session without crashing.
- [ ] `mobile/src/screens/ResultScreen.tsx` lists each criterion as `Cumprido`, `Omitido`, or `Incerto`, with the highlighted excerpt(s) that justified the decision and a one-line recommendation. No pass/fail language.
- [ ] React Native Testing Library coverage: `StationScreen.test.tsx`, `ResultScreen.test.tsx`.
- [ ] Manual smoke check documented in the PR (steps to launch Expo Go, start a session, finish, see result) with a recorded screenshot or short clip.
- [ ] `bash scripts/test.sh` exits 0.

## Blocked by

- #29 (Expo client foundation)
