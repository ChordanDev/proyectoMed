# Text Station Flow (#52)

## Goal
Deliver the learner-facing text station flow: active station → conversation turns → finish.

## Acceptance Criteria
- A learner can read the active station, submit text turns, and receive bounded replies.
- The screen reflects loading and recoverable API failure states.
- The learner can finish the session from the text flow.

## Tasks
- [ ] Fix ResultScreen broken imports (`../../../` → `../`)
- [ ] Add StationScreen i18n strings to pt-BR.json
- [ ] Create StationScreen component with input, message list, loading, error states, finish button
- [ ] Create StationScreen tests
- [ ] Wire full flow in App.tsx: NoticeScreen → StationScreen → ResultScreen
- [ ] Verify all tests pass

## Surfaces
- `web/src/features/station/result/ResultScreen.tsx`
- `web/src/features/station/result/ResultScreen.test.tsx`
- `web/src/features/station/screens/StationScreen.tsx` (new)
- `web/src/features/station/screens/StationScreen.css` (new)
- `web/src/features/station/screens/StationScreen.test.tsx` (new)
- `web/src/features/station/i18n/pt-BR.json`
- `web/src/features/station/index.ts`
- `web/src/App.tsx`
