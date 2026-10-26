"""One simulated learner of the load test (#401): a real WebRTC participant.

It starts a consented session on Phoenix, joins the session's LiveKit room with
Phoenix's learner credential and publishes a microphone track for the whole run,
silence included, as a browser does. Each turn speaks a tone burst (the fake STT
hears it as one utterance), then times the patient's reply: latency runs from the
moment the last speech sample is due to play out to the first audible frame of the
patient's track. Records outcomes and timings, never transcript or reply text.
"""

# pyright: reportMissingImports=false
import asyncio
import json
import math
import time
import urllib.request
from dataclasses import dataclass

from livekit import rtc

from loadtest.stack import require_loopback

SAMPLE_RATE = 48000
FRAME_MS = 20
FRAME_SAMPLES = SAMPLE_RATE * FRAME_MS // 1000
TONE_HZ = 300  # 6 whole cycles per frame: every loud frame is the same frame
TONE_AMPLITUDE = 8000
AUDIBLE = 1000  # the fake STT's speech threshold (fake_providers.SPEECH_RMS)
QUEUE_MS = 60  # small, so a captured frame plays out within ~60 ms
WORKER_IDENTITY = "voice-worker"


@dataclass(frozen=True)
class Script:
    turns: int = 40
    turn_interval_s: float = 7.5
    speech_s: float = 1.2
    reply_timeout_s: float = 15.0
    join_timeout_s: float = 60.0


def is_audible(samples) -> bool:
    """Whether a 16-bit frame holds sound, checking every 8th sample (cheap at N=200)."""
    return any(abs(s) >= AUDIBLE for s in samples[::8])


def session_offsets(n: int, ramp_s: float) -> list[float]:
    """Start delays that spread n sessions evenly over the ramp."""
    return [ramp_s * i / n for i in range(n)]


def _frame(loud: bool) -> rtc.AudioFrame:
    frame = rtc.AudioFrame.create(SAMPLE_RATE, 1, FRAME_SAMPLES)
    data = frame.data
    for i in range(FRAME_SAMPLES):
        tone = math.sin(2 * math.pi * TONE_HZ * i / SAMPLE_RATE)
        data[i] = round(TONE_AMPLITUDE * tone) if loud else 0
    return frame


def post(base: str, path: str) -> dict:
    body = {"audio_consent": True} if path.endswith("/sessions") else {}
    request = urllib.request.Request(
        require_loopback(base) + path,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read() or b"{}")


class Microphone:
    """Publishes 20 ms frames in real time: silence, or tone while a turn speaks."""

    def __init__(self, source: rtc.AudioSource, on_speech_end):
        self._source = source
        self._loud, self._silent = _frame(True), _frame(False)
        self._loud_left = 0
        self._spoken: asyncio.Future | None = None
        self._on_speech_end = on_speech_end
        self.running = True

    def speak(self, seconds: float) -> asyncio.Future:
        """Resolves to the monotonic time the last speech sample plays out."""
        self._loud_left = max(1, round(seconds * 1000 / FRAME_MS))
        self._spoken = asyncio.get_running_loop().create_future()
        return self._spoken

    async def pump(self) -> None:
        while self.running:
            loud = self._loud_left > 0
            await self._source.capture_frame(self._loud if loud else self._silent)
            if loud:
                self._loud_left -= 1
                if self._loud_left == 0 and self._spoken and not self._spoken.done():
                    end = time.monotonic() + self._source.queued_duration
                    self._on_speech_end(end)
                    self._spoken.set_result(end)


class Learner:
    def __init__(self, index: int, phoenix: str, script: Script):
        self.index = index
        self.phoenix = phoenix
        self.script = script
        self.turns: list[dict] = []
        self.failed: str | None = None
        self._awaiting_since: float | None = None
        self._reply_audio = asyncio.Event()
        self._reply_done = asyncio.Event()
        self._first_audio = 0.0
        self._error: str | None = None
        self._tasks: set[asyncio.Task] = set()

    def _on_speech_end(self, end: float) -> None:
        self._awaiting_since = end

    async def _listen(self, track: rtc.Track) -> None:
        async for event in rtc.AudioStream(track, sample_rate=16000, frame_size_ms=20):
            since = self._awaiting_since
            if since is not None and is_audible(event.frame.data):
                now = time.monotonic()
                if now >= since:
                    self._first_audio = now
                    self._awaiting_since = None
                    self._reply_audio.set()

    def _on_data(self, packet: rtc.DataPacket, session_id: str) -> None:
        if packet.topic != "transcript" or packet.participant is None:
            return
        if packet.participant.identity != WORKER_IDENTITY:
            return
        try:
            event = json.loads(packet.data)
        except ValueError:
            return
        if event.get("session_id") != session_id:
            return
        if event.get("error") or event.get("failure"):
            self._error = str(event.get("error") or event.get("failure"))
        elif (
            event.get("role") in ("patient", "companion")
            and event.get("status") == "complete"
        ):
            self._reply_done.set()

    async def run(self, delay_s: float) -> None:
        await asyncio.sleep(delay_s)
        try:
            await self._session()
        except Exception as error:  # every failure is a measured outcome
            self.failed = self.failed or type(error).__name__
        if self.failed:
            done = len(self.turns)
            self.turns += [
                {
                    "session": self.index,
                    "outcome": f"session_{self.failed}",
                    "latency_ms": None,
                    "started_at": time.time(),
                    "ended_at": time.time(),
                }
                for _ in range(self.script.turns - done)
            ]

    async def _session(self) -> None:
        session = await asyncio.to_thread(
            post, self.phoenix, "/api/stations/active/sessions"
        )
        session_id = session["session_id"]
        path = f"/api/stations/active/sessions/{session_id}"
        room = rtc.Room()
        mic = None
        try:
            credential = await asyncio.to_thread(post, self.phoenix, path + "/voice")
            joined = asyncio.Event()
            room.on("data_received", lambda p: self._on_data(p, session_id))
            room.on(
                "participant_connected",
                lambda p: p.identity == WORKER_IDENTITY and joined.set(),
            )

            def on_track(track, _publication, participant):
                if (
                    participant.identity == WORKER_IDENTITY
                    and track.kind == rtc.TrackKind.KIND_AUDIO
                ):
                    task = asyncio.ensure_future(self._listen(track))
                    self._tasks.add(task)

            room.on("track_subscribed", on_track)
            await room.connect(require_loopback(credential["url"]), credential["token"])
            source = rtc.AudioSource(SAMPLE_RATE, 1, queue_size_ms=QUEUE_MS)
            track = rtc.LocalAudioTrack.create_audio_track("microphone", source)
            options = rtc.TrackPublishOptions(source=rtc.TrackSource.SOURCE_MICROPHONE)
            await room.local_participant.publish_track(track, options)
            mic = Microphone(source, self._on_speech_end)
            pump = asyncio.ensure_future(mic.pump())
            self._tasks.add(pump)
            if any(
                p.identity == WORKER_IDENTITY for p in room.remote_participants.values()
            ):
                joined.set()
            try:
                await asyncio.wait_for(joined.wait(), self.script.join_timeout_s)
            except TimeoutError:
                self.failed = "worker_not_joined"
                return
            await asyncio.sleep(
                1.0
            )  # the worker's subscription to the microphone settles
            for _ in range(self.script.turns):
                await self._turn(mic)
        finally:
            if mic is not None:
                mic.running = False
            for task in self._tasks:
                task.cancel()
            await room.disconnect()
            try:
                await asyncio.to_thread(post, self.phoenix, path + "/discard")
            except OSError:
                pass

    async def _turn(self, mic: Microphone) -> None:
        script = self.script
        started_at, t0 = time.time(), time.monotonic()
        self._reply_audio.clear()
        self._reply_done.clear()
        self._error = None
        end_of_speech = await mic.speak(script.speech_s)
        outcome, latency = "ok", None
        try:
            await asyncio.wait_for(self._reply_audio.wait(), script.reply_timeout_s)
            latency = (self._first_audio - end_of_speech) * 1000
            await asyncio.wait_for(self._reply_done.wait(), script.reply_timeout_s)
        except TimeoutError:
            outcome = self._error or (
                "no_reply_end" if latency is not None else "no_audio"
            )
        self._awaiting_since = None
        self.turns.append(
            {
                "session": self.index,
                "outcome": outcome,
                "latency_ms": latency if outcome == "ok" else None,
                "started_at": started_at,
                "ended_at": time.time(),
            }
        )
        await asyncio.sleep(max(0.0, script.turn_interval_s - (time.monotonic() - t0)))


async def run_learners(indexes, offsets, phoenix: str, script: Script) -> list[dict]:
    learners = [Learner(i, phoenix, script) for i in indexes]
    await asyncio.gather(*(lr.run(d) for lr, d in zip(learners, offsets, strict=True)))
    return [
        {"index": lr.index, "failed": lr.failed, "turns": lr.turns} for lr in learners
    ]
