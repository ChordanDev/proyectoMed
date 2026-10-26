"""Provider usage of one worker job, reported to Phoenix at the end (#342).

Audio never passes through Phoenix (ADR-013 #209), so the worker meters what it
sends to the audio providers: the seconds of learner audio pushed to Deepgram, the
characters of reply text sent to Cartesia, and the participant minutes in the
LiveKit room (the worker and each learner connection). The report holds counts
only: no transcript, reply text or audio, and nothing here logs any of them.
"""

import logging
import time

from transcripts import VoiceFailure

logger = logging.getLogger("voice-worker")


class UsageMeter:
    """Cumulative counts for one job; `report` can be called at any time."""

    def __init__(self, clock=time.monotonic):
        self._clock = clock
        self._audio_seconds = 0.0
        self._characters = 0
        self._participant_seconds = 0.0
        self._joined: dict[str, float] = {}

    def add_audio(self, frame) -> None:
        """One audio frame pushed to the STT stream."""
        samples = getattr(frame, "samples_per_channel", 0)
        sample_rate = getattr(frame, "sample_rate", 0)
        if isinstance(samples, int) and isinstance(sample_rate, int) and sample_rate > 0:
            self._audio_seconds += samples / sample_rate

    def add_characters(self, text) -> None:
        """One text sent to the TTS provider."""
        if isinstance(text, str):
            self._characters += len(text)

    def join(self, identity: str) -> None:
        self._joined.setdefault(identity, self._clock())

    def leave(self, identity: str) -> None:
        started = self._joined.pop(identity, None)
        if started is not None:
            self._participant_seconds += self._clock() - started

    def report(self, report_id: str) -> dict:
        now = self._clock()
        connected = sum(now - started for started in self._joined.values())
        return {
            "report_id": report_id,
            "deepgram_audio_seconds": round(self._audio_seconds, 3),
            "cartesia_characters": self._characters,
            "livekit_participant_minutes": round(
                (self._participant_seconds + connected) / 60, 4
            ),
        }


async def report_usage(phoenix, meter: UsageMeter, report_id: str, session_id: str) -> None:
    """Send the job's usage to Phoenix; a failure is logged by kind and never raised."""
    try:
        await phoenix.report_usage(meter.report(report_id))
    except VoiceFailure as failure:
        logger.warning(
            "usage report not accepted for session %s: %s", session_id, failure.kind
        )
