"""Provider-neutral patient speech player (#120).

Streams the audio of one Phoenix-approved reply at a time into a single published room
track, fenced by the reply's generation identity. Nothing in this module logs or stores
reply text, audio or provider payloads.
"""

# pyright: reportMissingImports=false
import asyncio
import logging

from livekit import rtc
from livekit.agents import (
    APIConnectionError,
    APIConnectOptions,
    APIStatusError,
    APITimeoutError,
)

from transcripts import TurnTracker, VoiceFailure, VoiceTurnReply

TRACK_NAME = "patient-voice"
# No framework retries: a retried reply would be late, and the framework's retry
# warning echoes the provider error, which can carry the reply text. The player itself
# replaces a dead pooled websocket once, before any audio (`_synthesize`).
SYNTHESIS_OPTIONS = APIConnectOptions(max_retry=0)
logger = logging.getLogger("voice-worker.speech")
# Log fields where the Cartesia plugin puts a provider message, which can echo the
# reply text: kept as a field, never printed.
PROVIDER_PAYLOAD_FIELDS = ("error", "lk.pii.data")
REDACTED = "[redacted]"


def _redact_provider_payload(record: logging.LogRecord) -> bool:
    for field in PROVIDER_PAYLOAD_FIELDS:
        if field in record.__dict__:
            record.__dict__[field] = REDACTED
    return True


logging.getLogger("livekit.plugins.cartesia").addFilter(_redact_provider_payload)


def _audio_track(source):
    return rtc.LocalAudioTrack.create_audio_track(TRACK_NAME, source)


class SpeechPlayer:
    """Speaks accepted replies through an injected TTS provider, one generation at a time.

    Owns one audio source and one published local audio track per room, and closes the
    providers it was given. `voices` maps a voice key (`voz=`, #341) to its own
    provider: a reply whose `voice` is mapped is spoken by it on the same track, any
    other reply by `tts`. Every provider must share `tts`'s sample rate and channels. The tracker stays the authority on which generation is
    current: a reply is spoken only while it is the tracker's active, non-cancelled
    generation, and that fence is checked again before every frame is pushed.
    """

    def __init__(
        self,
        room,
        tracker: TurnTracker,
        tts,
        source_factory=None,
        track_factory=None,
        voices: dict | None = None,
        meter=None,
    ):
        self.room = room
        # Counts the characters sent to Cartesia (#342); optional.
        self.meter = meter
        self.tracker = tracker
        self.session_id = tracker.session_id
        self.tts = tts
        self.voices = dict(voices or {})
        self._source_factory = source_factory or rtc.AudioSource
        self._track_factory = track_factory or _audio_track
        self._source = None
        self._publication = None
        self._publish_task: asyncio.Task | None = None
        self._speaking: VoiceTurnReply | None = None
        self._task: asyncio.Task | None = None
        self._closed = False
        # Highest turn whose first audio frame was logged (#271).
        self._first_audio_turn = 0

    @property
    def speaking(self) -> VoiceTurnReply | None:
        """The reply being spoken, for session/turn/generation correlation."""
        return self._speaking

    def __repr__(self) -> str:
        return (
            f"SpeechPlayer(session_id={self.session_id!r}, speaking={self._speaking!r})"
        )

    async def start(self) -> None:
        """Publish the patient track once; a failed publication is retried by the next call."""
        if self._publication is not None:
            return
        if self._publish_task is None or self._publish_task.done():
            self._publish_task = asyncio.create_task(self._publish())
            # Retrieve the result even when every waiter was cancelled, so asyncio never
            # reports (and logs) an unretrieved provider exception.
            self._publish_task.add_done_callback(
                lambda task: task.cancelled() or task.exception()
            )
        # Shielded: a superseded generation must not abort a publication in progress.
        await asyncio.shield(self._publish_task)

    async def _publish(self) -> None:
        if self._source is None:
            self._source = self._source_factory(
                self.tts.sample_rate, self.tts.num_channels
            )
        self._publication = await self.room.local_participant.publish_track(
            self._track_factory(self._source),
            rtc.TrackPublishOptions(source=rtc.TrackSource.SOURCE_MICROPHONE),
        )
        self._prewarm()

    def _prewarm(self) -> None:
        """Open each provider's connection ahead of the next reply, without waiting.

        A cold Cartesia connection delayed the first audio of a reply by 0.5-1 s in
        local tests; a reply that ends early (cancelled or failed) drops its connection,
        so this runs again after every reply. A provider that already holds a connection
        keeps it. Best effort: a failure only costs the next reply time.
        """
        for tts in (self.tts, *self.voices.values()):
            prewarm = getattr(tts, "prewarm", None)
            if prewarm is None:
                continue
            try:
                prewarm()
            except Exception:
                logger.warning("speech prewarm failed for session %s", self.session_id)

    @staticmethod
    def _streams(tts) -> bool:
        return getattr(getattr(tts, "capabilities", None), "streaming", False)

    @classmethod
    def _open_stream(cls, tts, text: str):
        """One `tts` stream for `text`: the streaming input when the provider has one."""
        if not cls._streams(tts):
            return tts.synthesize(text, conn_options=SYNTHESIS_OPTIONS)
        stream = tts.stream(conn_options=SYNTHESIS_OPTIONS)
        stream.push_text(text)
        stream.end_input()
        return stream

    async def speak(self, reply: VoiceTurnReply) -> VoiceFailure | None:
        """Stream one accepted reply into the room; frames are pushed as they arrive.

        Returns when the generation finished, was cancelled or was superseded. A
        provider or publication error is returned as `synthesis_failed`, never raised.
        """
        if self._closed or not self._is_current(reply):
            return None
        self._stop()  # a newer generation supersedes the one being spoken
        self._speaking = reply
        task = self._task = asyncio.create_task(self._synthesize(reply))
        try:
            await asyncio.wait({task})
        except asyncio.CancelledError:
            self.cancel(reply.generation_id)
            await asyncio.gather(task, return_exceptions=True)
            raise
        finally:
            if self._speaking is reply:
                self._speaking = None
                self._task = None
        return None if task.cancelled() else task.result()

    def cancel(self, generation_id: int | None) -> None:
        """Stop speaking `generation_id`. Idempotent.

        An unknown, finished or already cancelled generation is a no-op. Buffered
        playback is cleared at once; the provider stream closes as the playback task
        unwinds, which `speak` waits for.
        """
        reply = self._speaking
        if reply is None or reply.generation_id != generation_id:
            return
        self.tracker.cancel(generation_id=generation_id)
        self._stop()

    def cancel_turn(self, turn_id: int) -> None:
        """Stop the playback bound to `turn_id` or an earlier turn; newer turns keep playing."""
        reply = self._speaking
        if reply is not None and reply.turn_id <= turn_id:
            self.cancel(reply.generation_id)

    async def aclose(self) -> None:
        """Close the provider stream, unpublish the track and close the source and provider."""
        if self._closed:
            return
        self._closed = True
        tasks = [task for task in (self._task, self._publish_task) if task is not None]
        self._stop()
        if self._publish_task is not None:
            self._publish_task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        publication, self._publication = self._publication, None
        source, self._source = self._source, None
        if publication is not None and self.room.isconnected():
            await self._release(
                self.room.local_participant.unpublish_track(publication.sid)
            )
        if source is not None:
            await self._release(source.aclose())
        await self._release(self.tts.aclose())
        for voice in self.voices.values():
            await self._release(voice.aclose())

    async def _release(self, closing) -> None:
        try:
            await closing
        except Exception:
            logger.warning(
                "speech resource close failed for session %s", self.session_id
            )

    def _is_current(self, reply) -> bool:
        """Whether `reply` is the tracker's accepted, active and non-cancelled generation."""
        return (
            isinstance(reply, VoiceTurnReply)
            and reply.is_committed_receipt()
            and reply.generation_id == self.tracker.active_generation_id
            and reply.generation_id not in self.tracker.cancelled_generations
        )

    def _log_first_audio(self, reply: VoiceTurnReply) -> None:
        """Log, once per turn, the time from end of learner speech to first audio (#271).

        Content-free: only identifiers and milliseconds.
        """
        ended_at = getattr(reply, "speech_ended_at", None)
        if ended_at is None or reply.turn_id <= self._first_audio_turn:
            return
        self._first_audio_turn = reply.turn_id
        elapsed_ms = round((asyncio.get_running_loop().time() - ended_at) * 1000)
        logger.info(
            "first patient audio for session %s turn %d generation %d after %d ms",
            self.session_id,
            reply.turn_id,
            reply.generation_id,
            elapsed_ms,
        )

    def _stop(self) -> None:
        task, self._task, self._speaking = self._task, None, None
        if task is not None:
            task.cancel()
            if self._source is not None:
                self._source.clear_queue()

    async def _synthesize(self, reply: VoiceTurnReply) -> VoiceFailure | None:
        stream = None
        try:
            await self.start()
            if self._speaking is not reply or not self._is_current(reply):
                return None
            tts = self.voices.get(getattr(reply, "voice", None), self.tts)
            text = reply.reply_text
            assert text is not None  # a current reply is committed, so it has text
            stream = self._open_stream(tts, text)
            if self.meter is not None:
                self.meter.add_characters(text)
            source = self._source
            assert source is not None  # start() published the track
            heard = retried = False
            while True:
                try:
                    async for audio in stream:
                        if self._speaking is not reply:
                            return None
                        if not self._is_current(reply):
                            # Fenced by the tracker alone: drop this frame and every
                            # later one.
                            source.clear_queue()
                            return None
                        heard = True
                        self._log_first_audio(reply)
                        await source.capture_frame(audio.frame)
                    break
                except (APIStatusError, APIConnectionError) as error:
                    # A pooled websocket can die while it waits for the reply (J400-2):
                    # one fresh stream, only before any audio, never after a timeout,
                    # which would make the reply late, and never when the provider
                    # refused the request (a bad key, an unpaid account, a rate
                    # limit), which a second try only repeats.
                    if (
                        heard
                        or retried
                        or isinstance(error, APITimeoutError)
                        or not error.retryable
                        or getattr(error, "status_code", None) == 429
                        or not self._streams(tts)
                    ):
                        raise
                    retried = True
                    closing, stream = stream, None
                    await self._release(closing.aclose())
                    if self._speaking is not reply or not self._is_current(reply):
                        return None
                    stream = self._open_stream(tts, text)
            # Still this generation until the buffered tail is heard, so a cancel in
            # that window clears it instead of being a finished-generation no-op.
            await source.wait_for_playout()
            return None
        except Exception:
            if self._speaking is not reply:
                return None  # a superseded generation has nothing left to report
            # Provider and publication errors can echo credentials or the reply text.
            failure = VoiceFailure("synthesis_failed")
            logger.warning(
                "speech stopped for session %s turn %d generation %d: %s",
                self.session_id,
                reply.turn_id,
                reply.generation_id,
                failure.kind,
            )
            return failure
        finally:
            if stream is not None:
                await self._release(stream.aclose())
                if not self._closed:
                    self._prewarm()
