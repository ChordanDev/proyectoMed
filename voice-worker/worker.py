"""LiveKit Agents worker: streams the learner's microphone to Deepgram (#118).

Joins only `station-session-*` rooms, asks Phoenix whether the session may stream audio,
publishes interim transcripts to the room (topic "transcript") and POSTs each final
transcript to Phoenix, which owns the transcript. Never logs transcript text or audio.
"""

# pyright: reportMissingImports=false
import asyncio
import json
import logging
import os
import sys

from livekit import rtc
from livekit.agents import AgentServer, AutoSubscribe, JobContext, JobRequest, cli
from livekit.plugins import deepgram
from transcripts import (
    PhoenixClient,
    TurnTracker,
    VoiceFailure,
    classify_provider_error,
    process_speech_stream,
)

ROOM_PREFIX = "station-session-"
# Silence that closes an utterance. Deepgram's plugin default (25 ms) split one sentence
# into several turns in manual testing. ponytail: fixed value, tune from real sessions.
ENDPOINTING_MS = 500
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
    async with phoenix:
        try:
            # Consent/active check happens before any audio reaches Deepgram.
            context = await phoenix.context()
            await ctx.connect(auto_subscribe=AutoSubscribe.AUDIO_ONLY)
            tracker = TurnTracker(session_id, context["last_turn_id"])
            # The job lives as long as the room; a reconnecting learner is a new participant.
            while ctx.room.isconnected():
                learner = await ctx.wait_for_participant(
                    identity=f"learner-{session_id}"
                )
                tracker.segments = []  # never glue a half utterance onto the next connection
                await transcribe(ctx.room, learner, context, tracker, phoenix)
        except VoiceFailure as failure:
            logger.warning(
                "voice worker stopped for session %s: %s", session_id, failure.kind
            )
            await publish(ctx.room, {"session_id": session_id, "error": failure.kind})
        finally:
            ctx.shutdown()


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
) -> None:
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
