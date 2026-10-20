#!/usr/bin/env bash
# Spike #189, stage 1: publishes a synthetic Brazilian Portuguese patient voice into
# a local LiveKit dev server as participant "voice-worker", looping, and prints a
# token for the Unreal client. Needs `livekit-server --dev` running, plus lk,
# ffmpeg and the macOS `say` voice "Luciana" (pt_BR).
set -euo pipefail

ROOM="${ROOM:-patient-voice-spike}"
URL="${LIVEKIT_URL:-ws://127.0.0.1:7880}"
KEY="${LIVEKIT_API_KEY:-devkey}"
SECRET="${LIVEKIT_API_SECRET:-secret}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

TEXT="Doutor, eu estou com uma dor no peito desde ontem à noite. Começou depois do jantar, é uma dor em aperto, aqui no meio do peito, e às vezes vai para o braço esquerdo. Eu também fiquei com falta de ar quando subi a escada. Não, eu nunca tive isso antes. Eu tomo remédio para pressão, mas esqueci de tomar ontem."

say -v Luciana -o "$WORK/voice.aiff" "$TEXT"
# One second of silence on each side makes the mouth's rest pose visible between loops.
ffmpeg -loglevel error -f lavfi -t 1 -i anullsrc=r=48000:cl=mono -i "$WORK/voice.aiff" \
  -filter_complex "[0][1][0]concat=n=3:v=0:a=1,aresample=48000" -ac 1 \
  -c:a libopus -b:a 48k -frame_duration 20 -application voip "$WORK/patient-voice.ogg"

echo "Unreal token (identity unreal-observer, room $ROOM):"
lk token create --url "$URL" --api-key "$KEY" --api-secret "$SECRET" \
  --join --room "$ROOM" --identity unreal-observer --valid-for 4h 2>/dev/null | grep -oE 'eyJ[A-Za-z0-9._-]+' | head -1
echo
echo "In the Unreal console: patientvoice.Token <token>"
echo "Publishing $WORK/patient-voice.ogg as voice-worker in a loop (Ctrl+C to stop)..."

while true; do
  lk room join --url "$URL" --api-key "$KEY" --api-secret "$SECRET" \
    --identity voice-worker --publish "$WORK/patient-voice.ogg" --exit-after-publish "$ROOM"
done
