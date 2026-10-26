"""Self-check of the local voice stack: one spoken turn, as the learner (#191).

Starts a consented session on Phoenix, joins its LiveKit room with Phoenix's learner
credential, speaks a tone burst into a microphone-source track and waits for the
voice worker's `transcript` events and the patient's audio. Exits non-zero when any
step is missing. Prints event kinds and counts, never transcript or reply text.

Run inside the voice stack, from the voice-worker environment:
  scripts/run-voice-stack.sh -- \
    uv run --project voice-worker python scripts/voice-stack/probe_spoken_turn.py
"""

# pyright: reportMissingImports=false
import asyncio
import json
import math
import os
import sys
import urllib.request

from livekit import rtc

PHOENIX = os.environ.get("STATION_PHOENIX_URL", "http://127.0.0.1:4000")
SAMPLE_RATE = 48000
FRAME_SAMPLES = 480  # 10 ms
TIMEOUT_S = 30


def post(path: str, body: dict | None = None) -> dict:
    request = urllib.request.Request(
        PHOENIX + path,
        data=json.dumps(body or {}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.loads(response.read() or b"{}")


def tone_frame(index: int, loud: bool) -> rtc.AudioFrame:
    frame = rtc.AudioFrame.create(SAMPLE_RATE, 1, FRAME_SAMPLES)
    data = frame.data
    for i in range(FRAME_SAMPLES):
        t = (index * FRAME_SAMPLES + i) / SAMPLE_RATE
        data[i] = round(8000 * math.sin(2 * math.pi * 300 * t)) if loud else 0
    return frame


async def main() -> int:
    session = post("/api/stations/active/sessions", {"audio_consent": True})
    session_id = session["session_id"]
    credential = post(f"/api/stations/active/sessions/{session_id}/voice")

    room = rtc.Room()
    learner_final = asyncio.Event()
    patient_text = asyncio.Event()
    patient_done = asyncio.Event()
    patient_audio = asyncio.Event()
    kinds: list[str] = []

    @room.on("data_received")
    def on_data(packet: rtc.DataPacket) -> None:
        if packet.topic != "transcript" or packet.participant is None:
            return
        if packet.participant.identity != "voice-worker":
            return
        event = json.loads(packet.data)
        if event.get("session_id") != session_id:
            return
        if event.get("final") is True:
            kinds.append("learner-final")
            learner_final.set()
        elif event.get("final") is False:
            kinds.append("learner-interim")
        elif event.get("role") == "patient" and event.get("status") == "complete":
            kinds.append("patient-complete")
            patient_done.set()
        elif event.get("role") == "patient" and event.get("text"):
            kinds.append("patient-text")
            patient_text.set()
        else:
            kinds.append(
                str(event.get("failure") or event.get("error") or event.get("status"))
            )

    async def listen(track: rtc.Track) -> None:
        async for frame_event in rtc.AudioStream(track):
            if any(frame_event.frame.data):
                patient_audio.set()
                return

    @room.on("track_subscribed")
    def on_track(track, _publication, participant) -> None:
        if participant.identity == "voice-worker" and track.name == "patient-voice":
            asyncio.ensure_future(listen(track))

    await room.connect(credential["url"], credential["token"])
    source = rtc.AudioSource(SAMPLE_RATE, 1)
    track = rtc.LocalAudioTrack.create_audio_track("microphone", source)
    options = rtc.TrackPublishOptions(source=rtc.TrackSource.SOURCE_MICROPHONE)
    await room.local_participant.publish_track(track, options)

    # The worker joins on its own and only hears audio published after it subscribes.
    worker_joined = asyncio.Event()
    room.on(
        "participant_connected",
        lambda p: p.identity == "voice-worker" and worker_joined.set(),
    )
    if any(p.identity == "voice-worker" for p in room.remote_participants.values()):
        worker_joined.set()
    try:
        await asyncio.wait_for(worker_joined.wait(), TIMEOUT_S)
    except TimeoutError:
        print(f"probe: voice worker did not join within {TIMEOUT_S}s", file=sys.stderr)
        return 1
    await asyncio.sleep(0.5)  # its subscription to the microphone track settles
    for index in range(150):  # 0.6 s of tone, then 0.9 s of silence
        await source.capture_frame(tone_frame(index, loud=index < 60))

    ok = True
    for name, event in (
        ("learner final transcript", learner_final),
        ("patient reply text", patient_text),
        ("patient reply audio", patient_audio),
        ("patient reply end", patient_done),
    ):
        try:
            await asyncio.wait_for(event.wait(), TIMEOUT_S)
            print(f"probe: {name} ok")
        except TimeoutError:
            print(f"probe: no {name} within {TIMEOUT_S}s", file=sys.stderr)
            ok = False
            break
    print(f"probe: events {kinds}")

    await room.disconnect()
    post(f"/api/stations/active/sessions/{session_id}/discard")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
