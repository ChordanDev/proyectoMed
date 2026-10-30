# #323 Training overtime, 20-minute cap and penalty (Phoenix slice)

Locator: `odd/tasks/323-training-overtime.md` · branch `feat/323-training-overtime-backend` (from `develop`) · runner `cd backend && mix test` · delivery `ask-on-risk`, PR to `develop`.

## Specs
- S1: In a training (a session without a mode is a training), reaching `deadline_at` does not end the run; Phoenix keeps accepting turns and impresso requests.
- S2: Hard cap at `started_at + 20 min`: Phoenix completes the training with a completion reason distinct from `:timer` and `:user` (`:cap`), with the existing in-flight turn grace; later turns and impresso requests get 409 `station_time_elapsed`. The payload exposes `cap_at`.
- S3: Session expiry stays after the cap (30 min).
- S4: The result returns `overtime_seconds = max(0, completed_at - deadline_at)`; 0 when finished within ten minutes.
- S5: Penalty = `0.25 × min(10, ceil(overtime_seconds / 60))` points: 0 s → 0; 1 s → 0.25; 60 s → 0.25; 61 s → 0.5; 200 s → 1; 600 s → 2.5; past 600 s → 2.5.
- S6: Training score = `max(0, total − penalty)` as an exact decimal string; null when `total` is null; rubric `total`, `scored_subtotal`, `scored_max`, `eligible_max` unchanged.
- S7: A real test session (`:simulated_exam`) keeps the hard ten-minute end, no overtime, no penalty.
- S8 (out of this slice): Unreal station client module shows expected-time-over and overtime, result screen shows overtime/penalty/training score; both Unreal tracks agree on the #190 interface first.

## Tasks
- [x] T1 Phoenix: cap + overtime + penalty + training score (S1-S7) · inline · full suite 2549 passed (RED observed first: 18/18 failing)
- [ ] T2 Unreal client (S8) · not started, needs the interface agreement

## Log
- L1 (2026-10-29): user, verbatim: "El #323 ya está implementado y listo? o que estaría faltando? avanza con eso."
- L2: status verified: only docs PR #376 merged; no cap, overtime or penalty in `backend/`. Blockers #190 and #195 are closed.
- L3: decision from triage (2026-10-23): cap is 20 min, 0.25 per started minute, separate training score (see issue comment).
- L4: tests that asserted the hard ten-minute end with a mode-less session (34) now start `:simulated_exam`, where that rule lives (S7). Training default overtime allowance is `:training_overtime_ms` (10 min).
