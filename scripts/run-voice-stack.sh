#!/usr/bin/env bash
# Starts the local real-time voice stack with no paid provider (#191):
#   livekit-server --dev, a mock OpenAI, Phoenix (dev, approving Jev adapter)
#   and the voice worker with its fake speech providers.
# Usage:
#   scripts/run-voice-stack.sh                 # run until Ctrl-C
#   scripts/run-voice-stack.sh -- <command>    # run <command> once the stack is up,
#                                              # then stop everything and exit with its status
# Environment (all optional):
#   VOICE_STACK_PHOENIX_PORT     Phoenix port, default 4000
#   VOICE_STACK_MOCK_PORT        mock OpenAI port, default 18766
#   VOICE_STACK_TRANSCRIPT       what the fake STT hears, default "Qual é o seu nome?"
#   VOICE_STACK_PATIENT_REPLY    what the mock patient answers, default "Meu nome é Carlos."
# Never sources .env: every provider here is local and fake.
set -euo pipefail
set -m # each background process gets its own process group, stopped as a whole

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PHOENIX_PORT="${VOICE_STACK_PHOENIX_PORT:-4000}"
MOCK_PORT="${VOICE_STACK_MOCK_PORT:-18766}"
LIVEKIT_PORT=7880 # fixed by `livekit-server --dev`
LOGS="$(mktemp -d "${TMPDIR:-/tmp}/voice-stack.XXXXXX")"
WORKER_SECRET="voice-stack-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
PIDS=()

stop() {
  for pid in ${PIDS[@]+"${PIDS[@]}"}; do kill -TERM -- "-$pid" 2>/dev/null || true; done
  wait 2>/dev/null || true
}
trap stop EXIT
trap 'exit 130' INT TERM

fail() {
  echo "voice stack: $1 (logs: $LOGS)" >&2
  exit 1
}

command -v nc >/dev/null || fail "nc is needed to check that the ports are free"
for port in "$LIVEKIT_PORT" "$PHOENIX_PORT" "$MOCK_PORT"; do
  if nc -z 127.0.0.1 "$port" 2>/dev/null; then fail "port $port is already in use"; fi
done

wait_for() { # <seconds> <description> <pid> <command...>
  local seconds=$1 what=$2 pid=$3
  shift 3
  for _ in $(seq "$seconds"); do
    if "$@" >/dev/null 2>&1; then echo "voice stack: $what ready"; return 0; fi
    kill -0 "$pid" 2>/dev/null || fail "$what exited before it was ready"
    sleep 1
  done
  fail "$what did not start within ${seconds}s"
}

LIVEKIT_ENV=(LIVEKIT_URL="ws://127.0.0.1:$LIVEKIT_PORT" LIVEKIT_API_KEY=devkey LIVEKIT_API_SECRET=secret)

# The agents worker reports its real CPU load even in dev mode, and LiveKit offers a
# job only to workers under its target load (0.7 by default): with a busy editor the
# worker would never be sent to the room.
LIVEKIT_CONFIG=$'keys:\n  devkey: secret\nagents:\n  target_load: 2\n'
livekit-server --dev --bind 127.0.0.1 --config-body "$LIVEKIT_CONFIG" >"$LOGS/livekit.log" 2>&1 &
PIDS+=($!)
MOCK_LLM_REPLY="${VOICE_STACK_PATIENT_REPLY:-Meu nome é Carlos.}" \
  python3 "$ROOT/scripts/voice-stack/mock_openai.py" "$MOCK_PORT" >"$LOGS/mock.log" 2>&1 &
PIDS+=($!)
(
  cd "$ROOT/backend"
  exec env -u LLM_PROVIDER -u ANTHROPIC_API_KEY -u ANTHROPIC_BASE_URL \
    "${LIVEKIT_ENV[@]}" MIX_ENV=dev PORT="$PHOENIX_PORT" PHX_SERVER=true \
    VOICE_MODE=realtime VOICE_WORKER_SECRET="$WORKER_SECRET" \
    OPENAI_API_KEY=voice-stack-stub-key OPENAI_BASE_URL="http://127.0.0.1:$MOCK_PORT" \
    JEV_E2E_APPROVING_ADAPTER=true mix phx.server
) >"$LOGS/phoenix.log" 2>&1 &
PIDS+=($!)

wait_for 30 "LiveKit" "${PIDS[0]}" curl -sf "http://127.0.0.1:$LIVEKIT_PORT"
wait_for 10 "mock OpenAI" "${PIDS[1]}" curl -sf "http://127.0.0.1:$MOCK_PORT"
wait_for 240 "Phoenix" "${PIDS[2]}" sh -c "curl -sf http://127.0.0.1:$PHOENIX_PORT/api/stations/active | grep -q '\"voice_mode\":\"realtime\"'"

(
  cd "$ROOT/voice-worker"
  exec env -u DEEPGRAM_API_KEY -u CARTESIA_API_KEY -u CARTESIA_VOICE_ID -u CARTESIA_VOICE_IDS \
    "${LIVEKIT_ENV[@]}" PHOENIX_URL="http://127.0.0.1:$PHOENIX_PORT" \
    VOICE_WORKER_SECRET="$WORKER_SECRET" VOICE_WORKER_FAKE_PROVIDERS=true \
    VOICE_WORKER_FAKE_TRANSCRIPT="${VOICE_STACK_TRANSCRIPT:-Qual é o seu nome?}" \
    uv run python worker.py dev --no-reload # dev: no CPU-load cap while the editor starts
) >"$LOGS/worker.log" 2>&1 &
PIDS+=($!)
wait_for 120 "voice worker" "${PIDS[3]}" grep -q "registered worker" "$LOGS/worker.log"

echo "voice stack: Phoenix on http://127.0.0.1:$PHOENIX_PORT, LiveKit on ws://127.0.0.1:$LIVEKIT_PORT (logs: $LOGS)"

if [ "${1:-}" = "--" ]; then
  shift
  set +e +m # the command runs in the foreground, in this process group
  "$@"
  status=$?
  set -e
  exit "$status"
fi
wait
