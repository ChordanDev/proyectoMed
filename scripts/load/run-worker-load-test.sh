#!/usr/bin/env bash
# Voice worker capacity test (#401), with no paid provider.
# Starts its own livekit-server --dev (ports 7990/7991, UDP 7992), the mock OpenAI,
# Phoenix in dev on port 4159 with its own database (backend_load401) and one voice
# worker with fake speech providers, runs N simulated learners per step and stops
# everything it started. Never sources .env: each process gets an allow-list of
# toolchain variables only (voice-worker/loadtest/stack.py).
# Usage:
#   scripts/load/run-worker-load-test.sh                         # N = 10,25,50,100,200
#   scripts/load/run-worker-load-test.sh --steps 10,25 --turns 5 # a quick run
# Options are those of `python -m loadtest.run --help`. Results: results.json and
# table.md in --out (default: a new temporary directory, printed at the end).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/voice-worker"
exec uv run python -m loadtest.run "$@"
