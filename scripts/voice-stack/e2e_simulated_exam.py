"""End-to-end run of a full Prova simulada, and of one unchanged training (#427).

Plays the learner against the local voice stack, over Phoenix's real HTTP API and a
real LiveKit room. A Prova simulada refuses typed input, keeps the patient's text away
from the learner, releases an impresso asked for by voice, discards what is said after
the deadline and ends in a scaled total with a certainty level. A training then keeps
typed turns, the patient's text, the examiner's acknowledgement, a patient who answers
past the deadline, and a result with no Prova simulada fields.

The stack must run with `VOICE_STACK_TRANSCRIPT` set to `SPOKEN_LINES` and a short
`E2E_STATION_DURATION_MS`, which is what the single command for this check sets:
  scripts/run-simulated-exam-e2e.sh
"""

# pyright: reportMissingImports=false
import asyncio
import json
import os
import sys
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from datetime import datetime

from livekit import rtc
from probe_spoken_turn import PHOENIX, SAMPLE_RATE, TIMEOUT_S, tone_frame

PATIENT_QUESTION = "Qual é o seu nome?"
IMPRESSO_REQUEST = "Quero o exame físico."
# What the fake transcription hears, one line per utterance.
SPOKEN_LINES = (PATIENT_QUESTION, IMPRESSO_REQUEST, PATIENT_QUESTION)
PATIENT_REPLY = os.environ.get("VOICE_STACK_PATIENT_REPLY", "Meu nome é Carlos.")
IMPRESSO_ID = "exame-fisico-geral"
SESSIONS = "/api/stations/active/sessions"
RESULTS = "/api/v2/stations/active/sessions"
# Past the speech-start tolerance Phoenix allows (500 ms), inside its evidence window.
AFTER_DEADLINE_S = 1.0
FINISH_TIMEOUT_S = 15
# Long enough for a reply nobody should send to reach the learner, were it sent.
LATE_REPLY_SETTLE_S = 1.5


class CheckFailed(Exception):
    pass


def check(passed: bool, what: str) -> None:
    if not passed:
        raise CheckFailed(what)
    print(f"e2e: {what}")


def call(method: str, path: str, body: dict | None = None) -> tuple[int, dict]:
    request = urllib.request.Request(
        PHOENIX + path,
        data=None if body is None else json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return response.status, json.loads(response.read() or b"{}")
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read() or b"{}")


def start_session(body: dict) -> dict:
    status, session = call("POST", SESSIONS, body)
    if status != 200:
        raise CheckFailed(f"session not started: {status} {session.get('error')}")
    return session


def show_session(session_id: str) -> dict:
    status, session = call("GET", f"{SESSIONS}/{session_id}")
    if status != 200:
        raise CheckFailed(f"session not read: {status} {session.get('error')}")
    return session


def show_result(session_id: str) -> dict:
    status, result = call("GET", f"{RESULTS}/{session_id}/result")
    if status != 200:
        raise CheckFailed(f"result not read: {status} {result.get('error')}")
    return result


def typed_turn(session_id: str) -> tuple[int, dict]:
    message = {"role": "learner", "modality": "text", "text": PATIENT_QUESTION}
    return call("POST", f"{SESSIONS}/{session_id}/messages", message)


def seconds_to_deadline(session: dict) -> float:
    deadline = datetime.fromisoformat(session["deadline_at"])
    server_now = datetime.fromisoformat(session["server_now"])
    return (deadline - server_now).total_seconds()


def by_role(session: dict, role: str) -> list[dict]:
    return [message for message in session["messages"] if message["role"] == role]


class Learner:
    """One learner in the session's LiveKit room, as a client sees it."""

    def __init__(self, session_id: str):
        self.session_id = session_id
        self.room = rtc.Room()
        self.source = rtc.AudioSource(SAMPLE_RATE, 1)
        self.events: list[dict] = []
        self.packets: list[bytes] = []
        self.audio_frames = 0
        self.frames_sent = 0
        self._listeners: set[asyncio.Task] = set()  # the loop holds tasks weakly
        self._changed = asyncio.Event()
        self.room.on("data_received", self._on_data)
        self.room.on("track_subscribed", self._on_track)

    def _on_data(self, packet: rtc.DataPacket) -> None:
        self.packets.append(packet.data)
        if (
            packet.topic == "transcript"
            and packet.participant is not None
            and packet.participant.identity == "voice-worker"
        ):
            event = json.loads(packet.data)
            if event.get("session_id") == self.session_id:
                self.events.append(event)
        self._changed.set()

    def _on_track(self, track, _publication, participant) -> None:
        if participant.identity == "voice-worker" and track.name == "patient-voice":
            listener = asyncio.ensure_future(self._listen(track))
            self._listeners.add(listener)
            listener.add_done_callback(self._listeners.discard)

    async def _listen(self, track: rtc.Track) -> None:
        async for frame_event in rtc.AudioStream(track):
            if any(frame_event.frame.data):
                self.audio_frames += 1
                self._changed.set()

    async def join(self) -> None:
        path = f"{SESSIONS}/{self.session_id}/voice"
        status, credential = call("POST", path, {})
        if status != 201:
            raise CheckFailed(f"no voice credential: {status}")
        await self.room.connect(credential["url"], credential["token"])
        track = rtc.LocalAudioTrack.create_audio_track("microphone", self.source)
        options = rtc.TrackPublishOptions(source=rtc.TrackSource.SOURCE_MICROPHONE)
        await self.room.local_participant.publish_track(track, options)
        await self.wait_for(
            lambda: any(
                participant.identity == "voice-worker"
                for participant in self.room.remote_participants.values()
            ),
            "the voice worker joined",
        )
        await asyncio.sleep(0.5)  # its subscription to the microphone track settles

    async def speak(self) -> None:
        for index in range(150):  # 0.6 s of tone, then 0.9 s of silence
            frame = tone_frame(self.frames_sent, loud=index < 60)
            self.frames_sent += 1
            await self.source.capture_frame(frame)

    async def wait_for(self, reached: Callable[[], bool], what: str) -> None:
        deadline = time.monotonic() + TIMEOUT_S
        while not reached():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise CheckFailed(f"timed out waiting: {what}; saw {self.kinds()}")
            self._changed.clear()
            try:
                # Short, as the room's participants change with no event here.
                await asyncio.wait_for(self._changed.wait(), min(remaining, 0.2))
            except TimeoutError:
                pass
        print(f"e2e: {what}")

    def count(self, **fields) -> int:
        return sum(
            all(event.get(key) == value for key, value in fields.items())
            for event in self.events
        )

    def kinds(self) -> list[str]:
        """Each event's shape, never its text."""
        return [
            "/".join(
                str(event[key])
                for key in ("role", "status", "final", "failure", "error")
                if key in event
            )
            for event in self.events
        ]

    def saw_text(self, text: str) -> bool:
        return any(text.encode() in packet for packet in self.packets)

    async def spoken_turn(self, role: str) -> None:
        """Says the next line and waits for the end of the reply and for its audio."""
        audio_frames = self.audio_frames
        ended = self.count(role=role, status="complete")
        await self.speak()
        await self.wait_for(
            lambda: self.count(role=role, status="complete") > ended,
            f"{role} reply ended",
        )
        await self.wait_for(
            lambda: self.audio_frames > audio_frames, "the patient was heard"
        )

    async def leave(self) -> None:
        await self.room.disconnect()


async def wait_until_completed(session_id: str) -> dict:
    deadline = time.monotonic() + FINISH_TIMEOUT_S
    while time.monotonic() < deadline:
        session = show_session(session_id)
        if session["status"] == "completed":
            return session
        await asyncio.sleep(0.2)
    raise CheckFailed("the session did not end")


async def simulated_exam() -> None:
    session = start_session({"audio_consent": True, "mode": "simulated_exam"})
    session_id = session["session_id"]
    check(session["mode"] == "simulated_exam", "a real test session started")
    started_at = time.monotonic()
    to_deadline = seconds_to_deadline(session)

    status, body = typed_turn(session_id)
    check(
        status == 403 and body["error"] == "typed_input_not_allowed",
        "a typed turn is refused",
    )
    status, body = call(
        "POST",
        f"{SESSIONS}/{session_id}/impressos/request",
        {"text": IMPRESSO_REQUEST},
    )
    check(
        status == 403 and body["error"] == "typed_input_not_allowed",
        "a typed impresso request is refused",
    )

    learner = Learner(session_id)
    await learner.join()
    await learner.spoken_turn("voice")

    path = f"{SESSIONS}/{session_id}/exam-mode"
    status, body = call("POST", path, {})
    check(status == 200 and body["status"] == "armed", "the exam button was pressed")
    await learner.speak()
    await learner.wait_for(
        lambda: learner.count(role="examiner", status="impresso_requested") == 1,
        "the spoken impresso request reached the impresso flow",
    )
    outcome = next(
        event for event in learner.events if event.get("status") == "impresso_requested"
    )
    check(
        outcome["decision"] == "released"
        and [item["id"] for item in outcome["newly_released"]] == [IMPRESSO_ID],
        "the impresso was released by voice",
    )
    status, body = call("GET", f"{SESSIONS}/{session_id}/impressos")
    check(
        status == 200
        and [item["id"] for item in body["released_impressos"]] == [IMPRESSO_ID],
        "the released impresso can be read",
    )

    view = show_session(session_id)
    kept = len(by_role(view, "learner"))
    check(learner.count(final=True) == 2, "both utterances were transcribed")
    check(
        learner.count(role="patient") == 0
        and not by_role(view, "patient")
        and not learner.saw_text(PATIENT_REPLY)
        and PATIENT_REPLY not in json.dumps(view, ensure_ascii=False),
        "no patient text reached the learner",
    )
    check(learner.count(role="examiner", status="acknowledged") == 0, "no 'Anotado.'")

    past_deadline = to_deadline - (time.monotonic() - started_at) + AFTER_DEADLINE_S
    check(past_deadline > 0, f"{past_deadline:.1f} s left to reach the deadline")
    await asyncio.sleep(past_deadline)
    audio_frames = learner.audio_frames
    replies = learner.count(role="voice", status="speaking")
    await learner.speak()
    await learner.wait_for(
        lambda: learner.count(final=True) == 3,
        "the worker heard an utterance after the deadline",
    )

    finished = await wait_until_completed(session_id)
    check(finished["completion_reason"] == "timer", "the deadline ended the run")
    await asyncio.sleep(LATE_REPLY_SETTLE_S)
    finished = show_session(session_id)
    check(
        len(by_role(finished, "learner")) == kept,
        "the utterance after the deadline was discarded",
    )
    check(
        learner.count(role="voice", status="speaking") == replies
        and learner.audio_frames == audio_frames,
        "the patient did not answer after the deadline",
    )
    check(
        [message["text"] for message in by_role(finished, "patient")]
        == [PATIENT_REPLY],
        "the patient's reply was kept for the result",
    )
    failures = [
        event for event in learner.events if "error" in event or "failure" in event
    ]
    check(not failures, "no voice failure in the whole run")
    await learner.leave()

    result = show_result(session_id)
    estimates = result["estimates"]
    check(
        result["scaled_total"] is not None
        and result["scaled_total"] == estimates["total"]
        and result["certainty_level"] == 5
        and result["incomplete"] is False,
        "the result carries a scaled total and a certainty level",
    )
    check("overtime_seconds" not in result, "the result has no training overtime")


async def training() -> None:
    session = start_session({"audio_consent": True})
    session_id = session["session_id"]
    check(session["mode"] == "training", "a session with no mode is a training")
    started_at = time.monotonic()
    to_deadline = seconds_to_deadline(session)

    learner = Learner(session_id)
    await learner.join()

    status, body = typed_turn(session_id)
    check(status == 200 and body["reply_text"] == PATIENT_REPLY, "a typed turn answers")
    await learner.wait_for(
        lambda: learner.audio_frames > 0, "the typed reply was spoken"
    )

    await learner.spoken_turn("patient")
    check(
        learner.count(role="patient", text=PATIENT_REPLY) == 1,
        "the patient's spoken reply is shown as text",
    )
    view = show_session(session_id)
    check(
        [message["text"] for message in by_role(view, "patient")]
        == [PATIENT_REPLY, PATIENT_REPLY],
        "the patient's text can be read during the run",
    )

    await learner.speak()
    await learner.wait_for(
        lambda: learner.count(role="examiner", status="acknowledged") == 1,
        "the examiner acknowledged an exam request",
    )

    past_deadline = to_deadline - (time.monotonic() - started_at) + AFTER_DEADLINE_S
    check(past_deadline > 0, f"{past_deadline:.1f} s left to reach the deadline")
    await asyncio.sleep(past_deadline)
    await learner.spoken_turn("patient")
    check(
        learner.count(role="patient", text=PATIENT_REPLY) == 2,
        "the patient still answers after the deadline",
    )

    path = f"{SESSIONS}/{session_id}/finish"
    status, body = call("POST", path, {"reason": "user"})
    check(status == 200, "the learner finished the training")
    failures = [
        event for event in learner.events if "error" in event or "failure" in event
    ]
    check(not failures, "no voice failure in the whole run")
    await learner.leave()

    result = show_result(session_id)
    check(
        result["overtime_seconds"] > 0 and "training_score" in result,
        "the result shows the overtime",
    )
    check(
        not {"scaled_total", "certainty_level", "incomplete"} & result.keys(),
        "the result has no Prova simulada fields",
    )


async def main() -> int:
    try:
        print("e2e: Prova simulada")
        await simulated_exam()
        print("e2e: training")
        await training()
    except CheckFailed as failure:
        print(f"e2e: FAILED: {failure}", file=sys.stderr)
        return 1
    print("e2e: passed")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
