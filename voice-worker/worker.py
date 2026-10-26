"""LiveKit Agents worker: streams the learner's microphone to Deepgram (#118).

Joins only `station-session-*` rooms, asks Phoenix whether the session may stream audio,
publishes interim transcripts to the room (topic "transcript") and POSTs each final
transcript to Phoenix, which owns the transcript. Each reply Phoenix approves is published
to the room as patient text and then spoken through ElevenLabs (#120). A learner turn
Phoenix kept without a reply is never spoken: a turn addressed to the examiner is
published as an examiner acknowledgement (`status: acknowledged`, #274) and a refused
patient reply as `status: kept` (#269). A turn Phoenix sent to the impresso request
because the learner armed the exam mode (#364) is published as `status:
impresso_requested` with its outcome, and nothing is spoken. Every reply event names its `speaker` (`patient`
or `companion`, #341), and each actor speaks with the ElevenLabs voice its voice key maps
to in `ELEVENLABS_VOICE_IDS`, on the one patient track. When the job ends it reports
its provider usage (Deepgram audio seconds, ElevenLabs characters, LiveKit
participant minutes, #342) to Phoenix. Never logs transcript text, reply text or audio.
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
from speech import SpeechPlayer
from transcripts import (
    DEFAULT_TURN_RETRIES,
    DEFAULT_TURN_TIMEOUT_S,
    PhoenixClient,
    TurnTracker,
    VoiceFailure,
    VoiceTurnReply,
    classify_provider_error,
    process_speech_stream,
)
from usage import UsageMeter, report_usage

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
    turn_timeout, turn_retries = phoenix_turn_settings(os.environ)
    phoenix = PhoenixClient(
        os.environ["PHOENIX_URL"],
        os.environ["VOICE_WORKER_SECRET"],
        session_id,
        turn_timeout=turn_timeout,
        turn_retries=turn_retries,
    )
    voice = None
    # Deepgram seconds, ElevenLabs characters and room minutes of this job (#342).
    meter = UsageMeter()
    connected = False
    async with phoenix:
        try:
            # Consent/active check happens before any audio reaches Deepgram.
            context = await phoenix.context()
            await ctx.connect(auto_subscribe=AutoSubscribe.AUDIO_ONLY)
            connected = True
            meter.join("voice-worker")
            # Older Phoenix contexts expose only the committed cursor. Deploy the
            # additive server floor before relying on restart-safe allocation.
            tracker = TurnTracker(
                session_id,
                context["last_turn_id"],
                turn_id_floor=context.get("turn_id_floor"),
            )
            tts = build_tts(session_id, context)
            player = (
                SpeechPlayer(
                    ctx.room,
                    tracker,
                    tts,
                    voices=build_voice_tts(session_id, context),
                    meter=meter,
                )
                if tts is not None
                else None
            )
            voice = PatientVoice(ctx.room, player, session_id)
            await voice.start()
            # The job lives as long as the room; a reconnecting learner is a new participant.
            while ctx.room.isconnected():
                learner = await ctx.wait_for_participant(
                    identity=f"learner-{session_id}"
                )
                tracker.segments = []  # never glue a half utterance onto the next connection
                meter.join(learner.identity)
                try:
                    await transcribe(
                        ctx.room,
                        learner,
                        context,
                        tracker,
                        phoenix,
                        voice=voice,
                        meter=meter,
                    )
                finally:
                    meter.leave(learner.identity)
        except VoiceFailure as failure:
            logger.warning(
                "voice worker stopped for session %s: %s", session_id, failure.kind
            )
            await publish(ctx.room, {"session_id": session_id, "error": failure.kind})
        finally:
            if voice is not None:
                await voice.aclose()
            if connected:
                meter.leave("voice-worker")
                await report_usage(phoenix, meter, job_id(ctx), session_id)
            ctx.shutdown()


def job_id(ctx) -> str:
    """The LiveKit job id names the usage report, so a retried report replaces itself."""
    job = getattr(ctx, "job", None)
    value = getattr(job, "id", None)
    return value if isinstance(value, str) and value else f"job-{id(ctx)}"


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


def build_voice_tts(session_id: str, context) -> dict:
    """ElevenLabs providers per voice key (#341), from `ELEVENLABS_VOICE_IDS`.

    The variable is a comma-separated list of `voice-key=voice-id` pairs, for example
    `feminina-adulta=<id>,infantil=<id>`; a reply whose voice key is not listed is
    spoken with `ELEVENLABS_VOICE_ID`. Malformed pairs are skipped and only the
    variable name is logged. Without an API key nothing is mapped.
    """
    raw = os.environ.get("ELEVENLABS_VOICE_IDS", "").strip()
    api_key = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if not raw or not api_key:
        return {}
    model = os.environ.get("ELEVENLABS_MODEL", "").strip() or DEFAULT_TTS_MODEL
    voices = {}
    malformed = False
    for pair in raw.split(","):
        key, sep, voice_id = (part.strip() for part in pair.partition("="))
        if not sep or not key or not voice_id:
            malformed = True
            continue
        try:
            voices[key] = elevenlabs.TTS(
                api_key=api_key,
                voice_id=voice_id,
                model=model,
                encoding=TTS_ENCODING,
                language=context["language"],
            )
        except ValueError:
            malformed = True
    if malformed:
        logger.warning(
            "malformed ELEVENLABS_VOICE_IDS entries skipped for session %s", session_id
        )
    return voices


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

    A reply Phoenix streams arrives as one verified sentence at a time (#271): each
    is published with its `segment` index and spoken after the previous sentence of
    the same generation, while later sentences are still being generated.

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
        # Last queued speech as (generation_id, turn_id, task): sentences of one
        # streamed reply (#271) are spoken in order, each after the previous one.
        self._tail: tuple[int | None, int, asyncio.Task] | None = None

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
        if reply.is_impresso_receipt():
            await self._publish_impresso(reply)
            return
        if reply.is_kept_receipt():
            await self._acknowledge(reply)
            return
        event = {
            "session_id": self.session_id,
            "turn_id": reply.turn_id,
            "generation_id": reply.generation_id,
            "role": "patient",
            # Who says it (#341); Phoenix labels only a station with a companion.
            "speaker": reply.speaker if reply.speaker == "companion" else "patient",
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
        previous = None
        if self._tail is not None and self._tail[0] == reply.generation_id:
            previous = self._tail[2]
        task = asyncio.create_task(self._speak(reply, previous))
        self._tail = (reply.generation_id, reply.turn_id, task)
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)

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

    async def _publish_impresso(self, reply: VoiceTurnReply) -> None:
        """Phoenix sent the utterance to the impresso request (exam mode, #364).

        The outcome goes to the learner's screen as an examiner event; nothing is
        spoken. A room publish error is logged content-free and never stops the
        job: the request is recorded, and the client can read it with
        `GET /sessions/:id/impressos`.
        """
        try:
            await publish(
                self.room,
                {
                    "session_id": self.session_id,
                    "turn_id": reply.turn_id,
                    "role": "examiner",
                    "status": "impresso_requested",
                    **reply.impresso,
                },
            )
        except Exception:
            logger.warning(
                "impresso outcome not published for session %s turn %d",
                self.session_id,
                reply.turn_id,
            )

    async def on_turn_end(self, reply: VoiceTurnReply) -> None:
        """Phoenix settled a reply streamed sentence by sentence (#281).

        The end event carries no text: it tells the learner's screen that every
        sentence was published, so the stored reply can be read. A room publish error
        is logged content-free and never stops the job; it is not a failure event,
        since the sentences were delivered.
        """
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
        self, reply: VoiceTurnReply, previous: asyncio.Task | None = None
    ) -> None:
        if previous is not None:
            # The previous sentence of the same reply finishes first; a cancelled
            # generation is then skipped by the player's fence.
            await asyncio.wait({previous})
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
    meter: UsageMeter | None = None,
) -> None:
    if voice is not None and on_reply is None:
        on_reply = voice.on_reply
    on_turn_end = voice.on_turn_end if voice is not None else None
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
            if meter is not None:
                meter.add_audio(frame_event.frame)
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
