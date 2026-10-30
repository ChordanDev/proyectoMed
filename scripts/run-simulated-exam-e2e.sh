#!/usr/bin/env bash
# Runs a full Prova simulada and one training end to end (#427), on the local voice
# stack with no paid provider: see scripts/run-voice-stack.sh for what it needs.
# Usage: scripts/run-simulated-exam-e2e.sh
# Never sources .env: every provider here is local and fake.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Long enough for the turns of a slow machine, short enough to wait for the deadline
# twice. The script fails, rather than pass, if the turns ever take longer.
export E2E_STATION_DURATION_MS=30000
# One line per utterance: see SPOKEN_LINES in the test.
export VOICE_STACK_TRANSCRIPT="Qual é o seu nome?|Quero o exame físico.|Qual é o seu nome?"

exec "$ROOT/scripts/run-voice-stack.sh" -- \
  uv run --project "$ROOT/voice-worker" python "$ROOT/scripts/voice-stack/e2e_simulated_exam.py"
