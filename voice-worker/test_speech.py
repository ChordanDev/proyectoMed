# pyright: reportMissingImports=false
import asyncio
import base64
import json
import logging
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import aiohttp
from livekit.agents import APIConnectionError, APIStatusError
from livekit.agents.cli.log import ColoredFormatter, JsonFormatter
from livekit.plugins import cartesia

from speech import SYNTHESIS_OPTIONS, SpeechPlayer
from transcripts import TurnTracker, VoiceFailure, VoiceTurnReply

REPLY_TEXT = "Resposta clinica confidencial"
PROVIDER_SECRET = "sk-provider-secret"


def accepted(tracker: TurnTracker, turn_id: int, text: str | None = None):
    """A reply that went through the tracker, as `TurnManager` delivers it."""
    reply = VoiceTurnReply(
        turn_id=turn_id,
        status="committed",
        generation_id=turn_id,
        reply_text=text or f"{REPLY_TEXT} {turn_id}",
    )
    assert tracker.accept_reply(reply) is reply
    return reply


def chunk(name: str):
    return SimpleNamespace(frame=name)


class FakeSource:
    def __init__(self, sample_rate: int, num_channels: int):
        self.sample_rate = sample_rate
        self.num_channels = num_channels
        self.frames: list[str] = []
        self.cleared = 0
        self.closed = 0
        self.capture_error: Exception | None = None
        self.capture_gate: asyncio.Event | None = None
        self.capturing = asyncio.Event()
        self.playout_gate: asyncio.Event | None = None
        self.playing_out = asyncio.Event()

    async def capture_frame(self, frame) -> None:
        self.capturing.set()
        if self.capture_gate is not None:
            await self.capture_gate.wait()
        if self.capture_error is not None:
            raise self.capture_error
        self.frames.append(frame)

    async def wait_for_playout(self) -> None:
        self.playing_out.set()
        if self.playout_gate is not None:
            await self.playout_gate.wait()

    def clear_queue(self) -> None:
        self.cleared += 1

    async def aclose(self) -> None:
        self.closed += 1


class FakeParticipant:
    def __init__(self):
        self.published: list[object] = []
        self.unpublished: list[str] = []
        self.publish_error: Exception | None = None

    async def publish_track(self, track, options=None):
        if self.publish_error is not None:
            raise self.publish_error
        self.published.append(track)
        return SimpleNamespace(sid=f"TR_{len(self.published)}")

    async def unpublish_track(self, track_sid: str) -> None:
        self.unpublished.append(track_sid)


class FakeRoom:
    def __init__(self):
        self.local_participant = FakeParticipant()

    def isconnected(self) -> bool:
        return True


class FakeSynthesis:
    """Provider stream fed by the test: a chunk, an exception to raise, or None to end."""

    def __init__(self):
        self.queue: asyncio.Queue = asyncio.Queue()
        self.closed = 0

    def __aiter__(self):
        return self

    async def __anext__(self):
        item = await self.queue.get()
        if item is None:
            raise StopAsyncIteration
        if isinstance(item, Exception):
            raise item
        return item

    async def aclose(self) -> None:
        self.closed += 1


class FakeTTS:
    sample_rate = 22050
    num_channels = 1

    def __init__(self):
        self.texts: list[str] = []
        self.streams: list[FakeSynthesis] = []
        self.synthesize_error: Exception | None = None
        self.closed = 0

    def synthesize(self, text: str, **_options):
        self.texts.append(text)
        if self.synthesize_error is not None:
            raise self.synthesize_error
        self.streams.append(FakeSynthesis())
        return self.streams[-1]

    async def aclose(self) -> None:
        self.closed += 1


class FakeStreamingSynthesis(FakeSynthesis):
    """A provider input stream: the text pushed into it and whether input ended."""

    def __init__(self):
        super().__init__()
        self.pushed: list[str] = []
        self.input_ended = False

    def push_text(self, text: str) -> None:
        self.pushed.append(text)

    def end_input(self) -> None:
        self.input_ended = True


class FakeStreamingTTS(FakeTTS):
    """A streaming provider with a connection pool, like Cartesia's websocket."""

    capabilities = SimpleNamespace(streaming=True)

    def __init__(self):
        super().__init__()
        self.prewarms = 0
        self.prewarm_error: Exception | None = None
        self.stream_options: list[dict] = []

    def prewarm(self) -> None:
        self.prewarms += 1
        if self.prewarm_error is not None:
            raise self.prewarm_error

    def stream(self, **options):
        self.stream_options.append(options)
        self.streams.append(FakeStreamingSynthesis())
        return self.streams[-1]


async def settle() -> None:
    # Let the playback task run up to its next provider or source await.
    for _ in range(10):
        await asyncio.sleep(0)


class SpeechPlayerTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.tracker = TurnTracker("s1", last_turn_id=0)
        self.room = FakeRoom()
        self.tts = FakeTTS()
        self.sources: list[FakeSource] = []

        def source_factory(sample_rate: int, num_channels: int) -> FakeSource:
            self.sources.append(FakeSource(sample_rate, num_channels))
            return self.sources[-1]

        self.player = SpeechPlayer(
            self.room,
            self.tracker,
            self.tts,
            source_factory=source_factory,
            track_factory=lambda source: SimpleNamespace(source=source),
        )

    async def start(self, reply: VoiceTurnReply) -> asyncio.Task:
        task = asyncio.create_task(self.player.speak(reply))
        await settle()
        return task

    async def test_first_frame_is_pushed_before_synthesis_completes(self):
        reply = accepted(self.tracker, 1)
        task = await self.start(reply)

        self.tts.streams[0].queue.put_nowait(chunk("a1"))
        await settle()

        self.assertEqual(self.sources[0].frames, ["a1"])
        self.assertFalse(task.done())
        self.assertEqual(self.tts.texts, [reply.reply_text])

        self.tts.streams[0].queue.put_nowait(chunk("a2"))
        self.tts.streams[0].queue.put_nowait(None)
        self.assertIsNone(await task)
        self.assertEqual(self.sources[0].frames, ["a1", "a2"])
        self.assertEqual(self.tts.streams[0].closed, 1)

    # Issue #341: each actor speaks with its own voice on the one track.
    async def test_a_reply_with_a_mapped_voice_is_spoken_by_that_voice(self):
        companion_tts = FakeTTS()
        self.player.voices = {"feminina-adulta": companion_tts}

        reply = accepted(self.tracker, 1)
        reply.voice = "feminina-adulta"
        task = await self.start(reply)
        companion_tts.streams[0].queue.put_nowait(chunk("c1"))
        companion_tts.streams[0].queue.put_nowait(None)
        self.assertIsNone(await task)

        self.assertEqual(companion_tts.texts, [reply.reply_text])
        self.assertEqual(self.tts.texts, [])
        self.assertEqual(self.sources[0].frames, ["c1"])
        self.assertEqual(len(self.room.local_participant.published), 1)

        other = accepted(self.tracker, 2)
        other.voice = "masculina-idosa"  # not mapped: the default voice
        task = await self.start(other)
        self.tts.streams[0].queue.put_nowait(None)
        await task
        self.assertEqual(self.tts.texts, [other.reply_text])

        await self.player.aclose()
        self.assertEqual((self.tts.closed, companion_tts.closed), (1, 1))

    async def test_playback_is_correlated_to_session_turn_and_generation(self):
        reply = accepted(self.tracker, 3)
        self.assertIsNone(self.player.speaking)
        task = await self.start(reply)

        self.assertIs(self.player.speaking, reply)
        self.assertEqual(self.player.speaking.turn_id, 3)
        self.assertEqual(self.player.speaking.generation_id, 3)
        self.assertEqual(self.player.session_id, "s1")

        self.tts.streams[0].queue.put_nowait(None)
        await task
        self.assertIsNone(self.player.speaking)

    async def test_one_source_and_track_are_published_per_room(self):
        for turn_id in (1, 2):
            task = await self.start(accepted(self.tracker, turn_id))
            self.tts.streams[-1].queue.put_nowait(None)
            await task

        self.assertEqual(len(self.sources), 1)
        self.assertEqual(
            (self.sources[0].sample_rate, self.sources[0].num_channels), (22050, 1)
        )
        self.assertEqual(len(self.room.local_participant.published), 1)
        self.assertIs(self.room.local_participant.published[0].source, self.sources[0])

    async def test_only_an_accepted_non_stale_reply_reaches_the_provider(self):
        never_accepted = VoiceTurnReply(
            turn_id=1, status="committed", generation_id=1, reply_text=REPLY_TEXT
        )
        duplicate = VoiceTurnReply(turn_id=1, status="duplicate")
        self.assertIsNone(await self.player.speak(never_accepted))
        self.assertIsNone(await self.player.speak(duplicate))
        self.assertIsNone(await self.player.speak("texto solto"))

        older = accepted(self.tracker, 1)
        accepted(self.tracker, 2)
        self.assertIsNone(await self.player.speak(older))

        cancelled = accepted(self.tracker, 3)
        self.tracker.cancel(generation_id=3)
        self.assertIsNone(await self.player.speak(cancelled))

        self.assertEqual(self.tts.texts, [])
        self.assertEqual(self.room.local_participant.published, [])

    async def test_cancel_is_idempotent_and_stops_stream_and_buffer(self):
        reply = accepted(self.tracker, 1)
        task = await self.start(reply)
        stream = self.tts.streams[0]
        stream.queue.put_nowait(chunk("a1"))
        await settle()

        self.player.cancel(99)  # unknown generation
        self.assertEqual(self.sources[0].cleared, 0)
        self.assertNotIn(99, self.tracker.cancelled_generations)
        self.assertFalse(task.done())

        self.player.cancel(1)
        self.player.cancel(1)
        self.assertIsNone(await task)
        self.assertEqual(stream.closed, 1)
        self.assertEqual(self.sources[0].cleared, 1)
        self.assertIn(1, self.tracker.cancelled_generations)
        self.assertIsNone(self.player.speaking)

        stream.queue.put_nowait(chunk("late"))
        await settle()
        self.player.cancel(1)  # already cancelled
        self.assertEqual(self.sources[0].frames, ["a1"])
        self.assertEqual(self.sources[0].cleared, 1)

    async def test_cancelling_a_finished_generation_is_a_no_op(self):
        task = await self.start(accepted(self.tracker, 1))
        self.tts.streams[0].queue.put_nowait(chunk("a1"))
        self.tts.streams[0].queue.put_nowait(None)
        await task

        self.player.cancel(1)

        self.assertEqual(self.sources[0].cleared, 0)
        self.assertNotIn(1, self.tracker.cancelled_generations)

    async def test_cancel_turn_only_stops_playback_of_that_turn_or_older(self):
        task = await self.start(accepted(self.tracker, 2))

        self.player.cancel_turn(1)  # a late result of an older turn
        await settle()
        self.assertFalse(task.done())

        self.player.cancel_turn(3)  # barge-in on the next pending turn
        self.assertIsNone(await task)
        self.assertEqual(self.tts.streams[0].closed, 1)
        self.assertEqual(self.sources[0].cleared, 1)

    async def test_frame_in_flight_when_cancelled_is_not_followed_by_another(self):
        task = await self.start(accepted(self.tracker, 1))
        source = self.sources[0]
        source.capture_gate = asyncio.Event()
        stream = self.tts.streams[0]
        stream.queue.put_nowait(chunk("in-flight"))
        stream.queue.put_nowait(chunk("buffered"))
        await source.capturing.wait()

        self.player.cancel(1)
        source.capture_gate.set()
        self.assertIsNone(await task)

        self.assertEqual(source.frames, [])
        self.assertEqual(source.cleared, 1)
        self.assertEqual(stream.closed, 1)

    async def test_generation_stays_cancellable_until_buffered_audio_played_out(self):
        task = await self.start(accepted(self.tracker, 1))
        source = self.sources[0]
        source.playout_gate = asyncio.Event()
        self.tts.streams[0].queue.put_nowait(chunk("a1"))
        self.tts.streams[0].queue.put_nowait(None)
        await source.playing_out.wait()

        # Synthesis is complete, but the learner has not heard the buffered tail yet.
        self.assertFalse(task.done())
        self.assertIsNotNone(self.player.speaking)
        self.player.cancel(1)

        self.assertIsNone(await task)
        self.assertEqual(source.cleared, 1)

    async def test_stale_generation_drops_late_chunks_on_the_per_frame_fence(self):
        task = await self.start(accepted(self.tracker, 1))
        stream = self.tts.streams[0]
        stream.queue.put_nowait(chunk("a1"))
        await settle()

        # The tracker learns about the cancellation without going through the player.
        self.tracker.cancel(generation_id=1)
        stream.queue.put_nowait(chunk("late-1"))
        stream.queue.put_nowait(chunk("late-2"))

        self.assertIsNone(await task)
        self.assertEqual(self.sources[0].frames, ["a1"])
        self.assertEqual(self.sources[0].cleared, 1)
        self.assertEqual(stream.closed, 1)

    async def test_newer_generation_supersedes_the_one_being_spoken(self):
        first = await self.start(accepted(self.tracker, 1))
        old_stream = self.tts.streams[0]
        old_stream.queue.put_nowait(chunk("old-1"))
        await settle()

        second = await self.start(accepted(self.tracker, 2))
        old_stream.queue.put_nowait(chunk("old-late"))
        new_stream = self.tts.streams[1]
        new_stream.queue.put_nowait(chunk("new-1"))
        new_stream.queue.put_nowait(None)

        self.assertIsNone(await first)
        self.assertIsNone(await second)
        self.assertEqual(self.sources[0].frames, ["old-1", "new-1"])
        self.assertEqual(self.sources[0].cleared, 1)
        self.assertEqual(old_stream.closed, 1)
        self.assertEqual(self.tts.texts, [f"{REPLY_TEXT} 1", f"{REPLY_TEXT} 2"])

    async def _assert_synthesis_failed(self, task, logs):
        failure = await task
        self.assertIsInstance(failure, VoiceFailure)
        self.assertEqual(failure.kind, "synthesis_failed")
        self.assertEqual(str(failure), "synthesis_failed")
        output = "\n".join(logs.output)
        self.assertIn("synthesis_failed", output)
        self.assertIn("session s1 turn 1 generation 1", output)
        self.assertNotIn(REPLY_TEXT, output)
        self.assertNotIn(PROVIDER_SECRET, output)
        self.assertIsNone(self.player.speaking)

    async def test_provider_failure_is_typed_and_content_free(self):
        self.tts.synthesize_error = APIStatusError(
            f"invalid key {PROVIDER_SECRET} for text {REPLY_TEXT}", status_code=401
        )
        with self.assertLogs("voice-worker.speech", level="WARNING") as logs:
            task = await self.start(accepted(self.tracker, 1))
            await self._assert_synthesis_failed(task, logs)
        self.assertEqual(self.sources[0].frames, [])

    async def test_provider_disconnect_mid_stream_is_synthesis_failed(self):
        with self.assertLogs("voice-worker.speech", level="WARNING") as logs:
            task = await self.start(accepted(self.tracker, 1))
            stream = self.tts.streams[0]
            stream.queue.put_nowait(chunk("a1"))
            stream.queue.put_nowait(
                APIConnectionError(f"socket closed {PROVIDER_SECRET} {REPLY_TEXT}")
            )
            await self._assert_synthesis_failed(task, logs)
        self.assertEqual(self.sources[0].frames, ["a1"])
        self.assertEqual(stream.closed, 1)

    async def test_track_publication_failure_never_reaches_the_provider(self):
        self.room.local_participant.publish_error = RuntimeError(PROVIDER_SECRET)
        with self.assertLogs("voice-worker.speech", level="WARNING") as logs:
            task = await self.start(accepted(self.tracker, 1))
            await self._assert_synthesis_failed(task, logs)
        self.assertEqual(self.tts.texts, [])

        # The next generation retries the publication instead of staying broken.
        self.room.local_participant.publish_error = None
        task = await self.start(accepted(self.tracker, 2))
        self.tts.streams[0].queue.put_nowait(None)
        self.assertIsNone(await task)
        self.assertEqual(len(self.room.local_participant.published), 1)

    async def test_frame_publication_failure_is_synthesis_failed(self):
        with self.assertLogs("voice-worker.speech", level="WARNING") as logs:
            task = await self.start(accepted(self.tracker, 1))
            self.sources[0].capture_error = RuntimeError(PROVIDER_SECRET)
            self.tts.streams[0].queue.put_nowait(chunk("a1"))
            await self._assert_synthesis_failed(task, logs)
        self.assertEqual(self.tts.streams[0].closed, 1)

    async def test_failure_does_not_block_the_next_generation(self):
        self.tts.synthesize_error = APIConnectionError("down")
        with self.assertLogs("voice-worker.speech", level="WARNING"):
            self.assertIsNotNone(await self.player.speak(accepted(self.tracker, 1)))

        self.tts.synthesize_error = None
        task = await self.start(accepted(self.tracker, 2))
        self.tts.streams[0].queue.put_nowait(chunk("b1"))
        self.tts.streams[0].queue.put_nowait(None)
        self.assertIsNone(await task)
        self.assertEqual(self.sources[0].frames, ["b1"])

    async def test_cancelling_the_caller_stops_playback(self):
        task = await self.start(accepted(self.tracker, 1))
        task.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await task

        self.assertEqual(self.tts.streams[0].closed, 1)
        self.assertEqual(self.sources[0].cleared, 1)
        self.assertIsNone(self.player.speaking)

    async def test_aclose_releases_resources_and_is_safe_to_call_twice(self):
        task = await self.start(accepted(self.tracker, 1))
        stream = self.tts.streams[0]
        stream.queue.put_nowait(chunk("a1"))
        await settle()

        await self.player.aclose()
        await self.player.aclose()

        self.assertIsNone(await task)
        self.assertEqual(stream.closed, 1)
        self.assertEqual(self.room.local_participant.unpublished, ["TR_1"])
        self.assertEqual(self.sources[0].closed, 1)
        self.assertEqual(self.tts.closed, 1)

        # A closed player never calls the provider again.
        self.assertIsNone(await self.player.speak(accepted(self.tracker, 2)))
        self.assertEqual(len(self.tts.texts), 1)

    async def test_aclose_before_any_speech_only_closes_the_provider(self):
        await self.player.aclose()

        self.assertEqual(self.sources, [])
        self.assertEqual(self.room.local_participant.unpublished, [])
        self.assertEqual(self.tts.closed, 1)

    async def test_aclose_failures_are_typed_and_do_not_stop_the_release(self):
        await self.player.start()

        async def failing_unpublish(_sid):
            raise RuntimeError(PROVIDER_SECRET)

        self.room.local_participant.unpublish_track = failing_unpublish
        with self.assertLogs("voice-worker.speech", level="WARNING") as logs:
            await self.player.aclose()

        self.assertNotIn(PROVIDER_SECRET, "\n".join(logs.output))
        self.assertEqual(self.sources[0].closed, 1)
        self.assertEqual(self.tts.closed, 1)

    async def test_first_audio_of_a_turn_logs_its_latency_once(self):
        first = accepted(self.tracker, 1)
        first.speech_ended_at = asyncio.get_running_loop().time() - 0.25
        with self.assertLogs("voice-worker.speech", level="INFO") as logs:
            task = await self.start(first)
            self.tts.streams[0].queue.put_nowait(chunk("a1"))
            self.tts.streams[0].queue.put_nowait(chunk("a2"))
            self.tts.streams[0].queue.put_nowait(None)
            await task
            # A later sentence of the same turn is not a first audio.
            again = VoiceTurnReply(1, "committed", 1, "Ainda dói.")
            again.speech_ended_at = first.speech_ended_at
            task = await self.start(again)
            self.tts.streams[1].queue.put_nowait(chunk("b1"))
            self.tts.streams[1].queue.put_nowait(None)
            await task

        lines = [line for line in logs.output if "first patient audio" in line]
        self.assertEqual(len(lines), 1)
        ms = int(lines[0].rsplit("after ", 1)[1].split(" ms")[0])
        self.assertGreaterEqual(ms, 250)
        self.assertNotIn(REPLY_TEXT, "\n".join(logs.output))

    async def test_reply_text_never_appears_in_logs_or_repr(self):
        with self.assertLogs("voice-worker", level="DEBUG") as logs:
            reply = accepted(self.tracker, 1)
            task = await self.start(reply)
            self.assertNotIn(REPLY_TEXT, repr(self.player))
            self.assertIn("generation_id=1", repr(self.player))
            self.tts.streams[0].queue.put_nowait(chunk("a1"))
            self.tts.streams[0].queue.put_nowait(APIConnectionError(reply.reply_text))
            await task
            await self.player.aclose()

        self.assertNotIn(REPLY_TEXT, "\n".join(logs.output))
        self.assertNotIn(REPLY_TEXT, repr(self.player))


class StreamingProviderTest(unittest.IsolatedAsyncioTestCase):
    """A streaming provider is warmed ahead of each reply, so none waits for a connection."""

    def setUp(self):
        self.tracker = TurnTracker("s1", last_turn_id=0)
        self.room = FakeRoom()
        self.tts = FakeStreamingTTS()
        self.sources: list[FakeSource] = []

        def source_factory(sample_rate: int, num_channels: int) -> FakeSource:
            self.sources.append(FakeSource(sample_rate, num_channels))
            return self.sources[-1]

        self.player = SpeechPlayer(
            self.room,
            self.tracker,
            self.tts,
            source_factory=source_factory,
            track_factory=lambda source: SimpleNamespace(source=source),
        )

    async def start(self, reply: VoiceTurnReply) -> asyncio.Task:
        task = asyncio.create_task(self.player.speak(reply))
        await settle()
        return task

    async def test_start_prewarms_the_provider_connection(self):
        await self.player.start()

        self.assertEqual(self.tts.prewarms, 1)
        self.assertEqual(len(self.room.local_participant.published), 1)

    async def test_reply_is_spoken_through_one_provider_stream_with_one_attempt(self):
        reply = accepted(self.tracker, 1)
        task = await self.start(reply)
        stream = self.tts.streams[0]

        self.assertEqual(stream.pushed, [reply.reply_text])
        self.assertTrue(stream.input_ended)
        self.assertEqual(self.tts.stream_options, [{"conn_options": SYNTHESIS_OPTIONS}])
        self.assertEqual(self.tts.texts, [])

        stream.queue.put_nowait(chunk("a1"))
        stream.queue.put_nowait(None)
        self.assertIsNone(await task)
        self.assertEqual(self.sources[0].frames, ["a1"])
        self.assertEqual(stream.closed, 1)

    async def test_provider_is_prewarmed_again_after_a_finished_reply(self):
        task = await self.start(accepted(self.tracker, 1))
        warmed_before_reply_ended = self.tts.prewarms
        self.tts.streams[0].queue.put_nowait(None)
        await task

        self.assertEqual(self.tts.prewarms, warmed_before_reply_ended + 1)

    async def test_provider_is_prewarmed_again_after_a_cancelled_reply(self):
        reply = accepted(self.tracker, 1)
        task = await self.start(reply)
        warmed_before_cancel = self.tts.prewarms
        self.player.cancel(reply.generation_id)
        self.assertIsNone(await task)

        self.assertEqual(self.tts.prewarms, warmed_before_cancel + 1)

    async def test_each_voice_is_prewarmed_and_speaks_through_its_own_stream(self):
        companion_tts = FakeStreamingTTS()
        self.player.voices = {"feminina-adulta": companion_tts}
        await self.player.start()
        self.assertEqual((self.tts.prewarms, companion_tts.prewarms), (1, 1))

        reply = accepted(self.tracker, 1)
        reply.voice = "feminina-adulta"
        task = await self.start(reply)
        stream = companion_tts.streams[0]
        stream.queue.put_nowait(chunk("c1"))
        stream.queue.put_nowait(None)
        self.assertIsNone(await task)

        self.assertEqual(stream.pushed, [reply.reply_text])
        self.assertEqual(self.tts.streams, [])
        self.assertEqual(self.sources[0].frames, ["c1"])
        self.assertEqual((self.tts.prewarms, companion_tts.prewarms), (2, 2))

    async def test_prewarm_failure_never_stops_the_reply(self):
        self.tts.prewarm_error = RuntimeError(PROVIDER_SECRET)
        with self.assertLogs("voice-worker.speech", level="WARNING") as logs:
            await self.player.start()
            task = await self.start(accepted(self.tracker, 1))
            self.tts.streams[0].queue.put_nowait(chunk("a1"))
            self.tts.streams[0].queue.put_nowait(None)
            self.assertIsNone(await task)

        self.assertEqual(self.sources[0].frames, ["a1"])
        self.assertNotIn(PROVIDER_SECRET, "\n".join(logs.output))


def provider_text(payload):
    return lambda context_id: SimpleNamespace(
        type=aiohttp.WSMsgType.TEXT, data=json.dumps(payload(context_id))
    )


def socket_closed():
    return lambda _context_id: SimpleNamespace(
        type=aiohttp.WSMsgType.CLOSED, data=None, extra=None
    )


def provider_audio(milliseconds: int = 200):
    pcm = bytes(24000 * milliseconds // 1000 * 2)
    return [
        provider_text(
            lambda c: {"context_id": c, "data": base64.b64encode(pcm).decode()}
        ),
        provider_text(lambda c: {"context_id": c, "done": True}),
    ]


class FakeCartesiaSocket:
    """A Cartesia websocket that answers the first request with its `script`, in order.

    Each script item takes the request's context id and returns the message.
    """

    def __init__(self, script):
        self.script = list(script)
        self.sent: list[dict] = []
        self._context = asyncio.Event()
        self.closed = False
        self.close_code = None

    async def send_str(self, data: str) -> None:
        self.sent.append(json.loads(data))
        self._context.set()

    async def receive(self, timeout=None):
        await self._context.wait()
        if not self.script:
            await asyncio.Event().wait()  # nothing more from the provider
        return self.script.pop(0)(self.sent[0]["context_id"])

    async def close(self) -> None:
        self.closed = True


class CartesiaProviderTest(unittest.IsolatedAsyncioTestCase):
    """The real Cartesia plugin behind the player, over a fake websocket."""

    def setUp(self):
        self.tracker = TurnTracker("s1", last_turn_id=0)
        self.room = FakeRoom()
        self.sockets: list[FakeCartesiaSocket] = []
        self.answers: list = []

        async def connect(_tts, _timeout):
            script = self.answers.pop(0) if self.answers else []
            self.sockets.append(FakeCartesiaSocket(script))
            return self.sockets[-1]

        async def close(_tts, ws):
            await ws.close()

        patches = (
            patch.object(cartesia.TTS, "_connect_ws", connect),
            patch.object(cartesia.TTS, "_close_ws", close),
        )
        for p in patches:
            p.start()
            self.addCleanup(p.stop)
        self.tts = cartesia.TTS(
            api_key="test-key",
            voice="test-voice",
            model="sonic-3",
            encoding="pcm_s16le",
            sample_rate=24000,
            word_timestamps=False,
            language="pt",
        )
        self.player = SpeechPlayer(
            self.room,
            self.tracker,
            self.tts,
            source_factory=FakeSource,
            track_factory=lambda source: SimpleNamespace(source=source),
        )

    def capture_logs(self) -> list[str]:
        """Every log line, as both livekit console formatters would print it."""
        lines: list[str] = []
        formatters = (
            ColoredFormatter(
                "%(asctime)s - %(esc_levelcolor)s%(levelname)-4s%(esc_reset)s"
                " %(name)s - %(message)s %(esc_gray)s%(extra)s"
            ),
            JsonFormatter(),
        )

        class Capture(logging.Handler):
            def emit(self, record):
                lines.extend(f.format(record) for f in formatters)

        handler = Capture(level=logging.DEBUG)
        root = logging.getLogger()
        previous_level = root.level
        root.addHandler(handler)
        root.setLevel(logging.DEBUG)

        def restore():
            root.removeHandler(handler)
            root.setLevel(previous_level)

        self.addCleanup(restore)
        return lines

    async def test_a_provider_error_reaches_the_logs_without_its_payload(self):
        self.answers.append(
            [
                provider_text(
                    lambda c: {
                        "type": "error",
                        "context_id": c,
                        "error": f"PROVIDER_MARKER {REPLY_TEXT}",
                    }
                )
            ]
        )
        lines = self.capture_logs()
        await self.player.start()

        failure = await self.player.speak(accepted(self.tracker, 1, REPLY_TEXT))

        self.assertEqual(failure.kind, "synthesis_failed")
        output = "\n".join(lines)
        self.assertIn("Cartesia returned error", output)
        self.assertNotIn("PROVIDER_MARKER", output)
        self.assertNotIn(REPLY_TEXT, output)
        await self.player.aclose()

    async def test_a_dead_prewarmed_socket_is_replaced_and_the_reply_is_heard(self):
        # The socket opened ahead of the reply died while it waited (#400, J400-2).
        self.answers.extend([[socket_closed()], provider_audio()])
        await self.player.start()

        failure = await self.player.speak(accepted(self.tracker, 1))

        self.assertIsNone(failure)
        heard = sum(f.samples_per_channel for f in self.player._source.frames)
        self.assertEqual(heard, 24000 * 200 // 1000)  # the whole 200 ms reply
        self.assertEqual(len(self.sockets[1].sent), 2)  # the reply, then its end
        await self.player.aclose()

    async def test_a_provider_cut_after_audio_is_not_retried(self):
        self.answers.extend([[*provider_audio()[:1], socket_closed()], provider_audio()])
        await self.player.start()

        failure = await self.player.speak(accepted(self.tracker, 1))

        self.assertEqual(failure.kind, "synthesis_failed")
        self.assertEqual(len(self.sockets[1].sent), 0)  # only prewarmed, never asked
        await self.player.aclose()

    async def test_a_provider_error_is_not_retried(self):
        self.answers.extend(
            [
                [provider_text(lambda c: {"type": "error", "context_id": c})],
                provider_audio(),
            ]
        )
        await self.player.start()

        failure = await self.player.speak(accepted(self.tracker, 1))

        self.assertEqual(failure.kind, "synthesis_failed")
        self.assertEqual(len(self.sockets[1].sent), 0)
        await self.player.aclose()

    async def test_an_unexpected_provider_message_is_logged_without_its_payload(self):
        lines = self.capture_logs()
        # The plugin's own call for a message type it does not know.
        logging.getLogger("livekit.plugins.cartesia").warning(
            "unexpected message", extra={"lk.pii.data": {"transcript": REPLY_TEXT}}
        )

        output = "\n".join(lines)
        self.assertIn("unexpected message", output)
        self.assertNotIn(REPLY_TEXT, output)


if __name__ == "__main__":
    unittest.main()
