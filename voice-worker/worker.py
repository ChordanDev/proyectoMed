"""LiveKit Agents worker: streams the learner's microphone to Deepgram (#118).

Joins only `station-session-*` rooms, asks Phoenix whether the session may stream audio,
publishes interim transcripts to the room (topic "transcript") and POSTs each final
transcript to Phoenix, which owns the transcript. Never logs transcript text or audio.
"""

import asyncio
import json
import logging
import os

from livekit import rtc
from livekit.agents import AgentServer, AutoSubscribe, JobContext, JobRequest, cli
from livekit.plugins import deepgram

from transcripts import PhoenixClient, TurnTracker, VoiceFailure, classify_provider_error

ROOM_PREFIX = "station-session-"
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
    phoenix = PhoenixClient(os.environ["PHOENIX_URL"], os.environ["VOICE_WORKER_SECRET"], session_id)
    async with phoenix:
        try:
            # Consent/active check happens before any audio reaches Deepgram.
            context = await phoenix.context()
            await ctx.connect(auto_subscribe=AutoSubscribe.AUDIO_ONLY)
            tracker = TurnTracker(session_id, context["last_turn_id"])
            # The job lives as long as the room; a reconnecting learner is a new participant.
            while ctx.room.isconnected():
                learner = await ctx.wait_for_participant(identity=f"learner-{session_id}")
                tracker.segments = []  # never glue a half utterance onto the next connection
                await transcribe(ctx.room, learner, context, tracker, phoenix)
        except VoiceFailure as failure:
            logger.warning("voice worker stopped for session %s: %s", session_id, failure.kind)
            await publish(ctx.room, {"session_id": session_id, "error": failure.kind})
        finally:
            ctx.shutdown()


async def transcribe(room, learner, context, tracker: TurnTracker, phoenix: PhoenixClient) -> None:
    stt = deepgram.STT(
        model="nova-3",
        language=context["language"],
        interim_results=True,
        keyterm=context["keyterms"],
    )
    audio = rtc.AudioStream.from_participant(
        participant=learner, track_source=rtc.TrackSource.SOURCE_MICROPHONE, sample_rate=16000
    )
    stream = stt.stream()

    async def pump() -> None:
        async for frame_event in audio:
            stream.push_frame(frame_event.frame)
        stream.end_input()

    pump_task = asyncio.create_task(pump())
    try:
        async for speech_event in stream:
            event = tracker.handle(speech_event)
            if event is None:
                continue
            if event["final"]:
                event["status"] = await phoenix.commit(event["turn_id"], event["text"])
            await publish(room, event)
    except VoiceFailure:
        raise
    except Exception as exc:
        raise classify_provider_error(exc) from None
    finally:
        pump_task.cancel()
        await audio.aclose()
        await stream.aclose()


async def publish(room: rtc.Room, payload: dict) -> None:
    if room.isconnected():
        await room.local_participant.publish_data(json.dumps(payload), topic="transcript", reliable=True)


if __name__ == "__main__":
    cli.run_app(server)
