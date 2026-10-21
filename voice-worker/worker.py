"""LiveKit Agents worker: streams the learner's microphone to Deepgram (#118).

Joins only `station-session-*` rooms, asks Phoenix whether the session may stream audio,
publishes interim transcripts to the room (topic "transcript") and POSTs each final
transcript to Phoenix, which owns the transcript. Each reply Phoenix approves is published
to the room as patient text and then spoken through ElevenLabs (#120). A learner turn
Phoenix kept without a reply is never spoken: a turn addressed to the examiner is
published as an examiner acknowledgement (`status: acknowledged`, #274) and a refused
patient reply as `status: kept` (#269). Never logs transcript text, reply text or audio.
"""

# pyright: reportMissingImports=false
import asyncio
import json
import logging
import math
import os
import sys

from livekit import rtc
from livekit.agents import AgentServer, AutoSubscribe, JobContext, JobRequest, cli
from livekit.plugins import deepgram, elevenlabs
from speech import SpeechPlayer, TextFeed
from transcripts import (
    DEFAULT_TURN_RETRIES,
    DEFAULT_TURN_TIMEOUT_S,
    PhoenixClient,
    ReplyDelta,
    TurnTracker,
    VoiceFailure,
    VoiceTurnReply,
    classify_provider_error,
    process_speech_stream,
)

ROOM_PREFIX = "station-session-"
# Silence that closes an utterance. Deepgram's plugin default (25 ms) split one sentence
# into several turns in manual testing. ponytail: fixed value, tune from real sessions.
ENDPOINTING_MS = 500
# Lowest-latency ElevenLabs model that covers pt-BR; override with ELEVENLABS_MODEL.
DEFAULT_TTS_MODEL = "eleven_flash_v2_5"
# Raw PCM: frames reach the room as they arrive, with no decoder in between.
TTS_ENCODING = "pcm_24000"
# Token TTS streaming (#313): Phoenix deltas reach ElevenLabs word by word over the
# streaming-input websocket. `auto_mode` would wait for whole sentences (the plugin
# then tokenizes by sentence), so it is off and generation starts once 50
# characters are buffered (the API's minimum); later chunks may be longer for a
# steadier voice. Only `TTS.stream()` uses these; sentence mode's
# `TTS.synthesize()` is unchanged. ponytail: tune from real sessions.
TTS_CHUNK_LENGTH_SCHEDULE = [50, 90, 120, 160]
logger = logging.getLogger("voice-worker")
server = AgentServer()


async def on_request(req: JobRequest) -> None:
    if req.room.name.startswith(ROOM_PREFIX):
        await req.accept(identity="voice-worker")
    else:
        await req.reject()


@server.rtc_session(on_request=on_request)
async def entrypoint(ctx: JobContext) -> None:
    session_id = ctx.room.name.removeprefix(ROOM_PREFIX)
    turn_timeout, turn_retries = phoenix_turn_settings(os.environ)
    phoenix = PhoenixClient(
        os.environ["PHOENIX_URL"],
        os.environ["VOICE_WORKER_SECRET"],
        session_id,
        turn_timeout=turn_timeout,
        turn_retries=turn_retries,
    )
    voice = None
    async with phoenix:
        try:
            # Consent/active check happens before any audio reaches Deepgram.
            context = await phoenix.context()
            await ctx.connect(auto_subscribe=AutoSubscribe.AUDIO_ONLY)
            # Older Phoenix contexts expose only the committed cursor. Deploy the
            # additive server floor before relying on restart-safe allocation.
            tracker = TurnTracker(
                session_id,
                context["last_turn_id"],
                turn_id_floor=context.get("turn_id_floor"),
            )
            tts = build_tts(session_id, context)
            player = SpeechPlayer(ctx.room, tracker, tts) if tts is not None else None
            voice = PatientVoice(ctx.room, player, session_id)
            await voice.start()
            # The job lives as long as the room; a reconnecting learner is a new participant.
            while ctx.room.isconnected():
                learner = await ctx.wait_for_participant(
                    identity=f"learner-{session_id}"
                )
                tracker.segments = []  # never glue a half utterance onto the next connection
                await transcribe(
                    ctx.room, learner, context, tracker, phoenix, voice=voice
                )
        except VoiceFailure as failure:
            logger.warning(
                "voice worker stopped for session %s: %s", session_id, failure.kind
            )
            await publish(ctx.room, {"session_id": session_id, "error": failure.kind})
        finally:
            if voice is not None:
                await voice.aclose()
            ctx.shutdown()


def phoenix_turn_settings(environ) -> tuple[float, int]:
    """Transcript POST timeout (seconds) and retry count, from the environment.

    `PHOENIX_TURN_TIMEOUT_S` must cover the server budget (see
    `transcripts.DEFAULT_TURN_TIMEOUT_S`); `PHOENIX_TURN_RETRIES` is a non-negative
    integer. A missing or invalid value keeps the default; only the variable name
    is logged.
    """
    timeout = DEFAULT_TURN_TIMEOUT_S
    raw_timeout = environ.get("PHOENIX_TURN_TIMEOUT_S", "").strip()
    if raw_timeout:
        try:
            parsed = float(raw_timeout)
        except ValueError:
            parsed = math.nan
        if math.isfinite(parsed) and parsed > 0:
            timeout = parsed
        else:
            logger.warning("invalid PHOENIX_TURN_TIMEOUT_S; using the default")

    retries = DEFAULT_TURN_RETRIES
    raw_retries = environ.get("PHOENIX_TURN_RETRIES")
    if raw_retries is not None:
        stripped = raw_retries.strip()
        # isascii(): str.isdigit() also accepts digits such as "²" that int() rejects.
        if stripped.isascii() and stripped.isdigit():
            retries = int(stripped)
        else:
            logger.warning("invalid PHOENIX_TURN_RETRIES; using the default")
    return timeout, retries


def _required_setting(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise KeyError(name)
    return value


def build_tts(session_id: str, context):
    """Build the ElevenLabs provider from the worker environment, or None when unset.

    Missing configuration disables patient audio only: replies still reach the room as
    text, each followed by a `synthesis_failed` event. A blank value counts as missing:
    the provider would accept it and then fail every reply at request time.
    """
    try:
        return elevenlabs.TTS(
            api_key=_required_setting("ELEVENLABS_API_KEY"),
            voice_id=_required_setting("ELEVENLABS_VOICE_ID"),
            model=os.environ.get("ELEVENLABS_MODEL", "").strip() or DEFAULT_TTS_MODEL,
            encoding=TTS_ENCODING,
            language=context["language"],
            auto_mode=False,
            chunk_length_schedule=TTS_CHUNK_LENGTH_SCHEDULE,
        )
    except (KeyError, ValueError):
        logger.warning(
            "patient speech unavailable for session %s: synthesis_failed", session_id
        )
        return None


class PatientVoice:
    """Delivers each accepted reply to the room: approved text first, then its audio.

    A reply Phoenix streams arrives as one verified sentence at a time (#271): each
    is published with its `segment` index and spoken after the previous sentence of
    the same generation, while later sentences are still being generated.

    The text event is the only place reply text leaves the worker, and it is published
    before synthesis starts so the learner can read the reply whatever happens to the
    audio. Playback runs in background tasks, so the speech reader keeps hearing the
    learner; a failure there is published content-free and never stops the job. A text
    event the room rejects is reported the same way (`text_delivery_failed`) and the
    reply is still spoken.

    Token TTS streaming (#313): Phoenix may stream a reply's text as deltas before
    its sentences. The first delta of a generation opens one provider stream fed
    with every delta (`SpeechPlayer.speak` with a `TextFeed`); that generation's
    sentences are then published as text only, and the settled turn ends the
    feed. An abort stops the audio at once and closes the feed: what follows it
    (a regenerated reply) is spoken sentence by sentence.
    """

    def __init__(self, room, player: SpeechPlayer | None, session_id: str = ""):
        self.room = room
        self.player = player
        self.session_id = player.session_id if player is not None else session_id
        self._tasks: set[asyncio.Task] = set()
        # Last queued speech as (generation_id, turn_id, task): sentences of one
        # streamed reply (#271) are spoken in order, each after the previous one.
        self._tail: tuple[int | None, int, asyncio.Task] | None = None
        # Open token-mode feeds by generation (#313).
        self._feeds: dict[int, TextFeed] = {}
        self._aborted: set[int] = set()

    async def start(self) -> None:
        """Publish the patient track ahead of the first reply; a failure is retried then."""
        if self.player is None:
            return
        try:
            await self.player.start()
        except Exception:
            logger.warning(
                "patient track not published for session %s: synthesis_failed",
                self.session_id,
            )

    async def on_reply(self, reply: VoiceTurnReply) -> None:
        if reply.is_kept_receipt():
            await self._acknowledge(reply)
            return
        event = {
            "session_id": self.session_id,
            "turn_id": reply.turn_id,
            "generation_id": reply.generation_id,
            "role": "patient",
            "text": reply.reply_text,
        }
        if reply.index is not None:
            event["segment"] = reply.index  # one verified sentence of the reply (#271)
        try:
            await publish(self.room, event)
        except Exception:
            # Called from the speech reader: a room publish error must not stop the
            # job. Phoenix keeps the approved text, and the reply is still spoken.
            await self._publish_failure(reply, "text_delivery_failed")
        if reply.generation_id in self._feeds:
            return  # its words are already being spoken from the deltas (#313)
        self._queue_speech(reply, None)

    def _queue_speech(self, reply: VoiceTurnReply, feed: TextFeed | None) -> None:
        previous = None
        if self._tail is not None and self._tail[0] == reply.generation_id:
            previous = self._tail[2]
        task = asyncio.create_task(self._speak(reply, previous, feed))
        self._tail = (reply.generation_id, reply.turn_id, task)
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)

    async def on_delta(self, delta: ReplyDelta) -> None:
        """Speak a token-mode delta of the reply being generated, or abort it (#313)."""
        if self.player is None:
            return  # the sentences report `synthesis_failed`, as without deltas
        generation_id = delta.generation_id
        if delta.is_abort():
            self._abort(generation_id)
            return
        feed = self._feeds.get(generation_id)
        if feed is None:
            if generation_id in self._aborted:
                return
            for older in [g for g in self._feeds if g < generation_id]:
                self._feeds.pop(older).end()
            self._aborted = {g for g in self._aborted if g >= generation_id}
            feed = self._feeds[generation_id] = TextFeed()
            reply = VoiceTurnReply(
                delta.turn_id, "committed", generation_id, delta.text
            )
            reply.speech_ended_at = delta.speech_ended_at
            reply.received_at = delta.received_at
            self._queue_speech(reply, feed)
        feed.push(delta.text)

    def _abort(self, generation_id: int) -> None:
        feed = self._feeds.pop(generation_id, None)
        self._aborted.add(generation_id)
        if feed is not None:
            feed.abort()
        try:
            self.player.interrupt(generation_id)
        except Exception:
            logger.warning(
                "playback interrupt failed for session %s generation %d",
                self.session_id,
                generation_id,
            )

    async def _acknowledge(self, reply: VoiceTurnReply) -> None:
        """Phoenix kept the learner turn without a patient reply.

        A turn addressed to the examiner (#274) is published as `acknowledged`; a
        refused patient reply (#269) as `kept`, so the learner sees that the patient
        did not answer. Nothing is spoken and it is not a failure. A room publish
        error is reported content-free and never stops the job.
        """
        status = "acknowledged" if reply.is_examiner_acknowledgement() else "kept"
        try:
            await publish(
                self.room,
                {
                    "session_id": self.session_id,
                    "turn_id": reply.turn_id,
                    "generation_id": reply.generation_id,
                    "role": "examiner",
                    "status": status,
                },
            )
        except Exception:
            await self._publish_failure(reply, "text_delivery_failed")

    async def on_turn_end(self, reply: VoiceTurnReply) -> None:
        """Phoenix settled a reply streamed sentence by sentence (#281).

        The end event carries no text: it tells the learner's screen that every
        sentence was published, so the stored reply can be read. A room publish error
        is logged content-free and never stops the job; it is not a failure event,
        since the sentences were delivered.
        """
        feed = self._feeds.pop(reply.generation_id, None)
        if feed is not None:
            feed.end()  # every delta was handed over (#313)
        try:
            await publish(
                self.room,
                {
                    "session_id": self.session_id,
                    "turn_id": reply.turn_id,
                    "generation_id": reply.generation_id,
                    "role": "patient",
                    "status": "complete",
                },
            )
        except Exception:
            logger.warning(
                "turn end not published for session %s turn %d generation %d",
                self.session_id,
                reply.turn_id,
                reply.generation_id,
            )

    def cancel_turn(self, turn_id: int) -> None:
        """Stop the playback bound to a cancelled or stale turn (or an earlier one)."""
        if self.player is None:
            return
        try:
            self.player.cancel_turn(turn_id)
            # Sentences of that turn still waiting for their turn to speak (#271).
            if self._tail is not None and self._tail[1] <= turn_id:
                generation_id = self._tail[0]
                if generation_id is not None:
                    self.player.tracker.cancel(generation_id=generation_id)
        except Exception:
            # Called from the speech reader: a playback error must not stop the job.
            logger.warning(
                "playback cancel failed for session %s turn %d",
                self.session_id,
                turn_id,
            )

    async def stop(self) -> None:
        """Cancel playback, e.g. when the learner disconnects; the track stays published."""
        tasks = tuple(self._tasks)
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)

    async def aclose(self) -> None:
        await self.stop()
        if self.player is not None:
            await self.player.aclose()

    async def _speak(
        self,
        reply: VoiceTurnReply,
        previous: asyncio.Task | None = None,
        feed: TextFeed | None = None,
    ) -> None:
        if previous is not None:
            # The previous sentence of the same reply finishes first; a cancelled
            # generation is then skipped by the player's fence.
            await asyncio.wait({previous})
        if feed is not None and feed.aborted:
            return  # Phoenix withdrew these deltas before they were spoken (#313)
        if self.player is None:
            failure = VoiceFailure("synthesis_failed")
            logger.warning(
                "speech stopped for session %s turn %d generation %d: %s",
                self.session_id,
                reply.turn_id,
                reply.generation_id,
                failure.kind,
            )
        else:
            failure = await self.player.speak(reply, feed=feed)
        if failure is not None:
            await self._publish_failure(reply, failure.kind)

    async def _publish_failure(self, reply: VoiceTurnReply, kind: str) -> None:
        if kind == "text_delivery_failed":
            logger.warning(
                "patient text not published for session %s turn %d generation %d: %s",
                self.session_id,
                reply.turn_id,
                reply.generation_id,
                kind,
            )
        try:
            # Not the fatal `error` event: the job goes on.
            await publish(
                self.room,
                {
                    "session_id": self.session_id,
                    "turn_id": reply.turn_id,
                    "generation_id": reply.generation_id,
                    "failure": kind,
                },
            )
        except Exception:
            logger.warning(
                "failure event not published for session %s turn %d generation %d: %s",
                self.session_id,
                reply.turn_id,
                reply.generation_id,
                kind,
            )


async def transcribe(
    room,
    learner,
    context,
    tracker: TurnTracker,
    phoenix: PhoenixClient,
    stt=None,
    audio=None,
    on_reply=None,
    cleanup_timeout: float = 1.0,
    voice: PatientVoice | None = None,
) -> None:
    if voice is not None and on_reply is None:
        on_reply = voice.on_reply
    on_turn_end = voice.on_turn_end if voice is not None else None
    on_delta = voice.on_delta if voice is not None else None
    if stt is None:
        stt = deepgram.STT(
            model="nova-3",
            language=context["language"],
            interim_results=True,
            endpointing_ms=ENDPOINTING_MS,
            keyterm=context["keyterms"],
        )
    if audio is None:
        audio = rtc.AudioStream.from_participant(
            participant=learner,
            track_source=rtc.TrackSource.SOURCE_MICROPHONE,
            sample_rate=16000,
        )
    stream = stt.stream()

    async def pump() -> None:
        async for frame_event in audio:
            stream.push_frame(frame_event.frame)
        stream.end_input()

    pump_task = asyncio.create_task(pump())
    close_task = None

    async def close_owned_resources() -> VoiceFailure | None:
        pump_task.cancel()
        await asyncio.gather(pump_task, return_exceptions=True)
        failure = None
        if voice is not None:
            # The learner left: nobody is listening to the reply being spoken.
            await voice.stop()
        for resource in (audio, stream):
            try:
                if hasattr(resource, "aclose"):
                    await resource.aclose()
            except Exception as exc:
                failure = classify_provider_error(exc)
                logger.warning("local resource close failed: %s", failure.kind)
        return failure

    async def close_resources() -> None:
        nonlocal close_task
        if close_task is None:
            close_task = asyncio.create_task(close_owned_resources())
        cancelled = False
        # Own and join one close attempt, even under repeated caller cancellation.
        # Local provider close is cooperative; the remote drain budget is separate.
        while not close_task.done():
            try:
                await asyncio.shield(close_task)
            except asyncio.CancelledError:
                cancelled = True
        failure = close_task.result()
        if cancelled:
            raise asyncio.CancelledError
        if failure is not None:
            raise failure from None

    try:
        await process_speech_stream(
            stream,
            tracker,
            phoenix,
            on_publish=lambda event: publish(room, event),
            on_reply=on_reply,
            on_close=close_resources,
            cleanup_timeout=cleanup_timeout,
            eof_timeout=phoenix.eof_timeout,
            on_cancel=voice.cancel_turn if voice is not None else None,
            on_turn_end=on_turn_end,
            on_delta=on_delta,
        )
    finally:
        primary = sys.exception()
        try:
            await close_resources()
        except (Exception, asyncio.CancelledError):
            if primary is None:
                raise


async def publish(room: rtc.Room, payload: dict) -> None:
    if room.isconnected():
        await room.local_participant.publish_data(
            json.dumps(payload), topic="transcript", reliable=True
        )


if __name__ == "__main__":
    cli.run_app(server)
