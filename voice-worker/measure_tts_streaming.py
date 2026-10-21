"""Scripted latency comparison of sentence and token TTS streaming (#313).

Drives the real worker pipeline (TurnManager, PatientVoice, SpeechPlayer and the
ElevenLabs plugin) against a running Phoenix, with an in-memory room instead of
LiveKit and no Deepgram: each scripted learner utterance is committed as a final
transcript, so "speech end" is the moment the commit starts. The first audio
frame is the first frame the provider returned and the player pushed to the
(fake) room source.

Phoenix decides the mode (`VOICE_TTS_STREAMING`); run this once per mode against
a Phoenix started with that mode. Needs PHOENIX_URL, VOICE_WORKER_SECRET,
ELEVENLABS_API_KEY and ELEVENLABS_VOICE_ID in the environment. Prints only
identifiers and milliseconds, never transcript, reply text or keys:

    uv run python measure_tts_streaming.py --label sentence
"""

# pyright: reportMissingImports=false
import argparse
import asyncio
import json
import logging
import os
import re
import statistics
from types import SimpleNamespace

import httpx
from livekit.agents.utils import http_context

from speech import SpeechPlayer
from transcripts import PhoenixClient, TurnManager, TurnTracker
from worker import PatientVoice, build_tts

# The 10-turn #290 replay (acute-appendicitis).
TURNS = [
    "Qual é seu nome?",
    "Onde começou a dor?",
    "Há quanto tempo começou?",
    "A dor mudou de lugar?",
    "Ela piorou com o tempo?",
    "A dor vai para outro lugar?",
    "Teve febre?",
    "Teve náusea ou vômito?",
    "Toma algum remédio?",
    "Tem alergia a algum medicamento?",
]

FIRST_AUDIO = re.compile(
    r"turn (\d+) generation \d+ after (\d+) ms "
    r"\(mode=(\w+) first_text=(\w+) ms first_tts_push=(\w+) ms\)"
)


class Source:
    """Room audio source stand-in: accepts frames at once."""

    def __init__(self, *_args):
        self.frames = 0

    async def capture_frame(self, _frame) -> None:
        self.frames += 1

    async def wait_for_playout(self) -> None:
        return None

    def clear_queue(self) -> None:
        return None

    async def aclose(self) -> None:
        return None


class Room:
    def __init__(self):
        self.local_participant = SimpleNamespace(
            publish_data=self._publish_data,
            publish_track=self._publish_track,
            unpublish_track=self._unpublish_track,
        )

    def isconnected(self) -> bool:
        return True

    async def _publish_data(self, *_args, **_kwargs) -> None:
        return None

    async def _publish_track(self, *_args, **_kwargs):
        return SimpleNamespace(sid="TR_bench")

    async def _unpublish_track(self, *_args) -> None:
        return None


class Marks(logging.Handler):
    def __init__(self):
        super().__init__()
        self.rows: dict[int, dict] = {}

    def emit(self, record: logging.LogRecord) -> None:
        match = FIRST_AUDIO.search(record.getMessage())
        if match:
            turn, audio, mode, text, push = match.groups()
            self.rows[int(turn)] = {
                "mode": mode,
                "first_text": int(text) if text.isdigit() else None,
                "first_tts_push": int(push) if push.isdigit() else None,
                "first_audio": int(audio),
            }


async def main(label: str) -> None:
    base = os.environ["PHOENIX_URL"]
    async with httpx.AsyncClient(base_url=base) as http:
        response = await http.post("/api/stations/active/sessions", json={"audio_consent": True})
        response.raise_for_status()
        session_id = response.json()["session_id"]

    marks = Marks()
    logging.getLogger("voice-worker.speech").addHandler(marks)
    logging.getLogger("voice-worker.speech").setLevel(logging.INFO)

    phoenix = PhoenixClient(base, os.environ["VOICE_WORKER_SECRET"], session_id)
    async with phoenix:
        context = await phoenix.context()
        tracker = TurnTracker(session_id, context["last_turn_id"])
        tts = build_tts(session_id, context)
        room = Room()
        player = SpeechPlayer(
            room, tracker, tts, source_factory=Source, track_factory=lambda _source: None
        )
        voice = PatientVoice(room, player, session_id)
        await voice.start()
        manager = TurnManager(
            tracker,
            phoenix,
            on_reply=voice.on_reply,
            on_turn_end=voice.on_turn_end,
            on_delta=voice.on_delta,
        )
        for turn_id, text in enumerate(TURNS, start=context["last_turn_id"] + 1):
            task = manager.commit_turn(turn_id, text)
            await task
            # Let the reply finish speaking before the next utterance.
            while voice._tasks:
                await asyncio.gather(*tuple(voice._tasks), return_exceptions=True)
            await asyncio.sleep(0.5)
        await voice.aclose()

    rows = [marks.rows.get(turn) for turn in range(1, len(TURNS) + 1)]
    print(json.dumps({"label": label, "session": session_id, "turns": rows}))
    for stage in ("first_text", "first_tts_push", "first_audio"):
        values = [r[stage] for r in rows if r and r[stage] is not None]
        if values:
            print(
                f"{label} {stage}: median {statistics.median(values):.0f} ms "
                f"(min {min(values)}, max {max(values)}, n={len(values)})"
            )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--label", default="run")
    label = parser.parse_args().label

    async def run() -> None:
        # The plugin's HTTP session normally comes from the agent job context.
        async with http_context.open():
            await main(label)

    asyncio.run(run())
