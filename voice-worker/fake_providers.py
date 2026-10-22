"""Deterministic speech providers for local end-to-end tests (#191).

With `VOICE_WORKER_FAKE_PROVIDERS=true` the worker transcribes and speaks without
Deepgram or ElevenLabs: every learner utterance becomes one fixed transcript
(`VOICE_WORKER_FAKE_TRANSCRIPT`), and every approved reply is spoken as a tone whose
length follows the text. Everything else, from the room and Phoenix to turn tracking,
is the real worker. The switch is refused unless LiveKit runs on this machine, so a
misconfigured deployment cannot answer learners with canned transcripts.
"""

# pyright: reportMissingImports=false
import array
import asyncio
import math
from types import SimpleNamespace
from urllib.parse import urlparse

from livekit import rtc
from livekit.agents.language import LanguageCode
from livekit.agents.stt import SpeechData, SpeechEvent, SpeechEventType

DEFAULT_FAKE_TRANSCRIPT = "Qual é o seu nome?"
LOOPBACK_HOSTS = {"127.0.0.1", "localhost", "::1"}
# Same silence as the Deepgram endpointing in worker.py, so turns split alike.
ENDPOINT_MS = 500
# 16-bit RMS: well above a quiet room, well below normal speech into a microphone.
SPEECH_RMS = 1000
TONE_SAMPLE_RATE = 24000
TONE_HZ = 220
TONE_AMPLITUDE = 8000
TONE_FRAME_MS = 20
TONE_SECONDS_PER_CHAR = 0.08
TONE_MIN_SECONDS = 0.4
TONE_MAX_SECONDS = 3.0


def fake_providers_from_env(environ) -> str | None:
    """The fixed transcript when fake providers are on, None when they are off.

    Raises ValueError when the switch is on and `LIVEKIT_URL` is not a loopback address.
    """
    if environ.get("VOICE_WORKER_FAKE_PROVIDERS", "").strip().lower() != "true":
        return None
    url = environ.get("LIVEKIT_URL", "").strip()
    # Parsers disagree on backslashes, blanks and userinfo; accept none of them.
    crafted = any(
        c == "\\" or c == "@" or c.isspace() or not c.isprintable() for c in url
    )
    if crafted or urlparse(url).hostname not in LOOPBACK_HOSTS:
        raise ValueError(
            "VOICE_WORKER_FAKE_PROVIDERS needs LIVEKIT_URL on a loopback address"
        )
    return (
        environ.get("VOICE_WORKER_FAKE_TRANSCRIPT", "").strip()
        or DEFAULT_FAKE_TRANSCRIPT
    )


def _rms(frame: rtc.AudioFrame) -> float:
    samples = frame.data
    if not samples:
        return 0.0
    return math.sqrt(sum(s * s for s in samples) / len(samples))


class FakeSTT:
    def __init__(self, transcript: str, language: str = "pt-BR"):
        self.transcript = transcript
        self.language = language

    def stream(self) -> "FakeSpeechStream":
        return FakeSpeechStream(self.transcript, self.language)


class FakeSpeechStream:
    """Energy endpointing: speech starts above `SPEECH_RMS` and ends after `ENDPOINT_MS` of quiet."""

    def __init__(self, transcript: str, language: str):
        self._transcript = transcript
        self._language = language
        self._events: asyncio.Queue = asyncio.Queue()
        self._speaking = False
        self._quiet_ms = 0.0
        self._ended = False

    def push_frame(self, frame: rtc.AudioFrame) -> None:
        if self._ended:
            return
        frame_ms = 1000 * frame.samples_per_channel / frame.sample_rate
        if _rms(frame) >= SPEECH_RMS:
            if not self._speaking:
                self._speaking = True
                self._events.put_nowait(
                    SpeechEvent(type=SpeechEventType.START_OF_SPEECH)
                )
            self._quiet_ms = 0.0
        elif self._speaking:
            self._quiet_ms += frame_ms
            if self._quiet_ms >= ENDPOINT_MS:
                self._end_utterance()

    def end_input(self) -> None:
        if self._ended:
            return
        if self._speaking:
            self._end_utterance()
        self._finish()

    async def aclose(self) -> None:
        self._finish()

    def _end_utterance(self) -> None:
        self._speaking = False
        self._quiet_ms = 0.0
        text = SpeechData(language=LanguageCode(self._language), text=self._transcript)
        self._events.put_nowait(
            SpeechEvent(type=SpeechEventType.FINAL_TRANSCRIPT, alternatives=[text])
        )
        self._events.put_nowait(SpeechEvent(type=SpeechEventType.END_OF_SPEECH))

    def _finish(self) -> None:
        if not self._ended:
            self._ended = True
            self._events.put_nowait(None)

    def __aiter__(self):
        return self

    async def __anext__(self) -> SpeechEvent:
        event = await self._events.get()
        if event is None:
            self._events.put_nowait(None)  # keep later reads at the end too
            raise StopAsyncIteration
        return event


class FakeTTS:
    sample_rate = TONE_SAMPLE_RATE
    num_channels = 1

    def synthesize(self, text: str, **_options) -> "FakeSynthesis":
        seconds = len(text.strip()) * TONE_SECONDS_PER_CHAR
        return FakeSynthesis(min(max(seconds, TONE_MIN_SECONDS), TONE_MAX_SECONDS))

    async def aclose(self) -> None:
        pass


class FakeSynthesis:
    def __init__(self, seconds: float):
        self._remaining = round(seconds * TONE_SAMPLE_RATE)
        self._position = 0

    def __aiter__(self):
        return self

    async def __anext__(self):
        if self._remaining <= 0:
            raise StopAsyncIteration
        await asyncio.sleep(0)
        count = min(TONE_SAMPLE_RATE * TONE_FRAME_MS // 1000, self._remaining)
        start = self._position
        data = array.array(
            "h",
            (
                round(
                    TONE_AMPLITUDE
                    * math.sin(2 * math.pi * TONE_HZ * (start + i) / TONE_SAMPLE_RATE)
                )
                for i in range(count)
            ),
        )
        self._position += count
        self._remaining -= count
        frame = rtc.AudioFrame(data.tobytes(), TONE_SAMPLE_RATE, 1, count)
        return SimpleNamespace(frame=frame)

    async def aclose(self) -> None:
        self._remaining = 0
