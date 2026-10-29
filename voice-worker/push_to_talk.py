"""The learner's microphone as push-to-talk (#419).

The Unreal client publishes its microphone muted, unmutes it while the learner
holds the talk key and mutes it again on release. `PushToTalk` sits between the
transcription stream and `process_speech_stream` and turns those mutes into the
speech events the turn handling already knows:

- a press (unmute) is a START_OF_SPEECH, so it interrupts the patient at once (#193);
- Deepgram's END_OF_SPEECH no longer ends a turn while the key is held;
- a release (mute) asks Deepgram to finalize, then ends the turn with an
  END_OF_SPEECH once the transcript has been quiet for `RELEASE_QUIET_S`, at most
  `RELEASE_MAX_SETTLE_S` after the release. Deepgram does not promise an answer to
  a finalize, so a last interim that never became final stands in for it;
- transcript that arrives after that end, and before the next press, belongs to the
  ended turn and is dropped. Pressing again before the end continues the turn.

A microphone that is never muted (the web client) keeps Deepgram's end of speech:
every event passes through unchanged.
"""

import asyncio
import collections
import time
from enum import Enum

from livekit.agents.stt import SpeechEvent, SpeechEventType

RELEASE_QUIET_S = 0.3
RELEASE_MAX_SETTLE_S = 1.5

_TRANSCRIPTS = (SpeechEventType.INTERIM_TRANSCRIPT, SpeechEventType.FINAL_TRANSCRIPT)
# Queued after the transcription stream's last event.
_STREAM_END = object()


class _State(Enum):
    # Never muted: Deepgram's end of speech ends turns.
    OPEN = "open"
    # Released, and the turn of the last press has ended.
    IDLE = "idle"
    HELD = "held"
    # Released; the turn ends once the transcript settles.
    SETTLING = "settling"


class PushToTalk:
    def __init__(
        self,
        stream,
        quiet_s: float | None = None,
        max_settle_s: float | None = None,
    ):
        self._stream = stream
        self._quiet_s = RELEASE_QUIET_S if quiet_s is None else quiet_s
        self._max_settle_s = (
            RELEASE_MAX_SETTLE_S if max_settle_s is None else max_settle_s
        )
        self._state = _State.OPEN
        self._items: asyncio.Queue = asyncio.Queue()
        self._ready: collections.deque[SpeechEvent] = collections.deque()
        self._pump: asyncio.Task | None = None
        self._ended = False
        # Words heard in the current turn, and its newest interim not yet final.
        self._heard = False
        self._pending_interim: SpeechEvent | None = None
        self._released_at = 0.0
        self._last_heard_at = 0.0

    def press(self) -> None:
        """The learner pressed the talk key: the microphone was unmuted."""
        if self._state not in (_State.IDLE, _State.SETTLING):
            return
        if self._state is _State.IDLE:
            self._heard = False
            self._pending_interim = None
        self._state = _State.HELD
        self._ready.append(SpeechEvent(type=SpeechEventType.START_OF_SPEECH))
        self._wake()

    def release(self) -> None:
        """The learner released the talk key: the microphone was muted."""
        if self._state is _State.HELD or (self._state is _State.OPEN and self._heard):
            self._stream.flush()
            self._state = _State.SETTLING
            self._released_at = time.monotonic()
            self._wake()
        elif self._state is _State.OPEN:
            self._state = _State.IDLE

    async def aclose(self) -> None:
        if self._pump is not None:
            self._pump.cancel()
            await asyncio.gather(self._pump, return_exceptions=True)

    def __aiter__(self):
        return self

    async def __anext__(self) -> SpeechEvent:
        if self._pump is None:
            self._pump = asyncio.create_task(self._read_stream())
        while not self._ready:
            if self._ended:
                raise StopAsyncIteration
            wait = self._settle_in()
            try:
                item = await asyncio.wait_for(self._items.get(), wait)
            except TimeoutError:
                self._settle()
                continue
            if item is _STREAM_END:
                self._ended = True
            elif isinstance(item, BaseException):
                raise item
            elif isinstance(item, SpeechEvent):
                self._hear(item)
        return self._ready.popleft()

    async def _read_stream(self) -> None:
        try:
            async for speech_event in self._stream:
                self._items.put_nowait(speech_event)
        except Exception as exc:
            self._items.put_nowait(exc)
        else:
            self._items.put_nowait(_STREAM_END)

    def _wake(self) -> None:
        self._items.put_nowait(None)

    def _hear(self, speech_event: SpeechEvent) -> None:
        if self._state is _State.IDLE:
            return
        if speech_event.type == SpeechEventType.END_OF_SPEECH:
            if self._state is _State.OPEN:
                self._heard = False
                self._pending_interim = None
                self._ready.append(speech_event)
            return
        if speech_event.type in _TRANSCRIPTS and _text(speech_event):
            self._heard = True
            self._last_heard_at = time.monotonic()
            final = speech_event.type == SpeechEventType.FINAL_TRANSCRIPT
            self._pending_interim = None if final else speech_event
        self._ready.append(speech_event)

    def _settle_in(self) -> float | None:
        """Seconds until the released turn ends; None while no turn is settling."""
        if self._state is not _State.SETTLING:
            return None
        deadline = self._released_at + self._max_settle_s
        if self._heard and self._pending_interim is None:
            quiet_since = max(self._released_at, self._last_heard_at)
            deadline = min(deadline, quiet_since + self._quiet_s)
        return max(0.0, deadline - time.monotonic())

    def _settle(self) -> None:
        if self._pending_interim is not None:
            self._ready.append(
                SpeechEvent(
                    type=SpeechEventType.FINAL_TRANSCRIPT,
                    alternatives=self._pending_interim.alternatives,
                )
            )
        if self._heard:
            self._ready.append(SpeechEvent(type=SpeechEventType.END_OF_SPEECH))
        self._state = _State.IDLE
        self._heard = False
        self._pending_interim = None


def _text(speech_event: SpeechEvent) -> str:
    alternatives = speech_event.alternatives
    return alternatives[0].text.strip() if alternatives else ""
