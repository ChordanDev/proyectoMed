"""LiveKit Agents worker: streams the learner's microphone to Deepgram (#118).

Joins only `station-session-*` rooms, asks Phoenix whether the session may stream audio,
publishes interim transcripts to the room (topic "transcript") and POSTs each final
transcript to Phoenix, which owns the transcript. Each reply Phoenix approves is published
to the room as patient text and then spoken through ElevenLabs (#120). A refused reply
that Phoenix kept as a learner turn is published as an examiner acknowledgement and
never spoken (#269). Never logs transcript text, reply text or audio.
"""

# pyright: reportMissingImports=false
import asyncio
import json
import logging
import os
import sys

from livekit import rtc
from livekit.agents import AgentServer, AutoSubscribe, JobContext, JobRequest, cli
from livekit.plugins import deepgram, elevenlabs
from speech import SpeechPlayer
from transcripts import (
    PhoenixClient,
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
    phoenix = PhoenixClient(
        os.environ["PHOENIX_URL"], os.environ["VOICE_WORKER_SECRET"], session_id
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
        )
    except (KeyError, ValueError):
        logger.warning(
            "patient speech unavailable for session %s: synthesis_failed", session_id
        )
        return None


class PatientVoice:
    """Delivers each accepted reply to the room: approved text first, then its audio.

    The text event is the only place reply text leaves the worker, and it is published
    before synthesis starts so the learner can read the reply whatever happens to the
    audio. Playback runs in background tasks, so the speech reader keeps hearing the
    learner; a failure there is published content-free and never stops the job. A text
    event the room rejects is reported the same way (`text_delivery_failed`) and the
    reply is still spoken.
    """

    def __init__(self, room, player: SpeechPlayer | None, session_id: str = ""):
        self.room = room
        self.player = player
        self.session_id = player.session_id if player is not None else session_id
        self._tasks: set[asyncio.Task] = set()

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
        try:
            await publish(
                self.room,
                {
                    "session_id": self.session_id,
                    "turn_id": reply.turn_id,
                    "generation_id": reply.generation_id,
                    "role": "patient",
                    "text": reply.reply_text,
                },
            )
        except Exception:
            # Called from the speech reader: a room publish error must not stop the
            # job. Phoenix keeps the approved text, and the reply is still spoken.
            await self._publish_failure(reply, "text_delivery_failed")
        task = asyncio.create_task(self._speak(reply))
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)

    async def _acknowledge(self, reply: VoiceTurnReply) -> None:
        """A refused reply kept the learner turn (#269): the examiner acknowledges it.

        Nothing is spoken and it is not a failure. A room publish error is reported
        content-free and never stops the job.
        """
        try:
            await publish(
                self.room,
                {
                    "session_id": self.session_id,
                    "turn_id": reply.turn_id,
                    "generation_id": reply.generation_id,
                    "role": "examiner",
                    "status": "kept",
                },
            )
        except Exception:
            await self._publish_failure(reply, "text_delivery_failed")

    def cancel_turn(self, turn_id: int) -> None:
        """Stop the playback bound to a cancelled or stale turn (or an earlier one)."""
        if self.player is None:
            return
        try:
            self.player.cancel_turn(turn_id)
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

    async def _speak(self, reply: VoiceTurnReply) -> None:
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
            failure = await self.player.speak(reply)
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
            on_cancel=voice.cancel_turn if voice is not None else None,
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
