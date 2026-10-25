"""Provider usage the worker meters and reports to Phoenix (#342)."""

import asyncio
import json
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import httpx

import worker
from speech import SpeechPlayer
from test_speech import FakeRoom, FakeSource, FakeTTS, accepted, chunk, settle
from test_transcripts import MockRoom, MockSTT
from transcripts import PhoenixClient, TurnTracker, VoiceFailure
from usage import UsageMeter, report_usage
from worker import transcribe


class FakeClock:
    def __init__(self):
        self.now = 0.0

    def __call__(self) -> float:
        return self.now


def audio_frame(samples: int, sample_rate: int = 16000):
    return SimpleNamespace(samples_per_channel=samples, sample_rate=sample_rate)


class UsageMeterTest(unittest.TestCase):
    def test_counts_audio_seconds_characters_and_participant_minutes(self):
        clock = FakeClock()
        meter = UsageMeter(clock=clock)

        meter.join("voice-worker")
        for _ in range(10):
            meter.add_audio(audio_frame(1600))  # 0.1 s each at 16 kHz
        meter.add_audio(audio_frame(24000, sample_rate=48000))  # 0.5 s
        meter.add_characters("Começou ontem.")
        meter.add_characters("Dói aqui.")

        clock.now = 60.0
        meter.join("learner-s1")
        clock.now = 180.0
        meter.leave("learner-s1")
        clock.now = 300.0
        meter.leave("voice-worker")

        self.assertEqual(
            meter.report("AJ_1"),
            {
                "report_id": "AJ_1",
                "deepgram_audio_seconds": 1.5,
                "elevenlabs_characters": 23,
                "livekit_participant_minutes": 7.0,
            },
        )

    def test_a_participant_still_connected_counts_up_to_the_report(self):
        clock = FakeClock()
        meter = UsageMeter(clock=clock)
        meter.join("voice-worker")
        meter.join("voice-worker")  # joining twice does not double the time
        meter.leave("never-joined")
        clock.now = 30.0
        self.assertEqual(meter.report("AJ_1")["livekit_participant_minutes"], 0.5)
        clock.now = 90.0
        self.assertEqual(meter.report("AJ_1")["livekit_participant_minutes"], 1.5)

    def test_a_frame_without_a_sample_rate_adds_nothing(self):
        meter = UsageMeter()
        meter.add_audio(SimpleNamespace(samples_per_channel=1600, sample_rate=0))
        meter.add_audio(object())
        meter.add_characters(None)
        self.assertEqual(meter.report("AJ_1")["deepgram_audio_seconds"], 0.0)
        self.assertEqual(meter.report("AJ_1")["elevenlabs_characters"], 0)


class PhoenixUsageReportTest(unittest.IsolatedAsyncioTestCase):
    async def test_posts_the_report_to_the_session_usage_endpoint_with_the_secret(self):
        seen = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["method"] = request.method
            seen["path"] = request.url.path
            seen["auth"] = request.headers["authorization"]
            seen["body"] = json.loads(request.content)
            return httpx.Response(202, json={"status": "recorded"})

        report = {
            "report_id": "AJ_1",
            "deepgram_audio_seconds": 1.5,
            "elevenlabs_characters": 23,
            "livekit_participant_minutes": 7.0,
        }
        async with PhoenixClient(
            "http://phoenix", "secret", "s1", transport=httpx.MockTransport(handler)
        ) as phoenix:
            self.assertEqual(await phoenix.report_usage(report), {"status": "recorded"})

        self.assertEqual(seen["method"], "POST")
        self.assertEqual(seen["path"], "/api/internal/voice/sessions/s1/usage")
        self.assertEqual(seen["auth"], "Bearer secret")
        self.assertEqual(seen["body"], report)

    async def test_a_rejected_report_is_a_typed_failure(self):
        def handler(_request):
            return httpx.Response(400, json={"error": "invalid_usage"})

        async with PhoenixClient(
            "http://phoenix", "secret", "s1", transport=httpx.MockTransport(handler)
        ) as phoenix:
            with self.assertRaises(VoiceFailure) as raised:
                await phoenix.report_usage({"report_id": "AJ_1"})
        self.assertEqual(raised.exception.kind, "malformed")

    async def test_report_usage_never_raises_and_logs_only_the_failure_kind(self):
        class FailingPhoenix:
            async def report_usage(self, _report):
                raise VoiceFailure("disconnected")

        meter = UsageMeter()
        meter.add_characters("Resposta clinica confidencial")
        with self.assertLogs("voice-worker", level="WARNING") as logs:
            await report_usage(FailingPhoenix(), meter, "AJ_1", "s1")
        self.assertIn("disconnected", logs.output[0])
        self.assertNotIn("confidencial", "".join(logs.output))

    async def test_report_usage_sends_the_meter_report(self):
        sent = []

        class RecordingPhoenix:
            async def report_usage(self, report):
                sent.append(report)
                return {"status": "recorded"}

        meter = UsageMeter()
        meter.add_characters("abc")
        await report_usage(RecordingPhoenix(), meter, "AJ_1", "s1")
        self.assertEqual(sent, [meter.report("AJ_1")])


class SpeechCharactersTest(unittest.IsolatedAsyncioTestCase):
    async def test_every_synthesized_reply_adds_its_characters(self):
        tracker = TurnTracker("s1", last_turn_id=0)
        tts = FakeTTS()
        companion = FakeTTS()
        meter = UsageMeter()
        player = SpeechPlayer(
            FakeRoom(),
            tracker,
            tts,
            source_factory=FakeSource,
            track_factory=lambda source: SimpleNamespace(source=source),
            voices={"infantil": companion},
            meter=meter,
        )

        first = accepted(tracker, 1, "Começou ontem.")
        task = asyncio.create_task(player.speak(first))
        await settle()
        tts.streams[0].queue.put_nowait(chunk("a1"))
        tts.streams[0].queue.put_nowait(None)
        await task

        second = accepted(tracker, 2, "Dói aqui.")
        second.voice = "infantil"
        task = asyncio.create_task(player.speak(second))
        await settle()
        companion.streams[0].queue.put_nowait(None)
        await task

        self.assertEqual(meter.report("AJ_1")["elevenlabs_characters"], 23)


class PushStream:
    """STT stream that records what the pump pushes."""

    def __init__(self):
        self.frames = []
        self.ended = asyncio.Event()

    def push_frame(self, frame) -> None:
        self.frames.append(frame)

    def end_input(self) -> None:
        self.ended.set()

    async def aclose(self) -> None:
        pass


class FrameAudio:
    def __init__(self, frames):
        self._frames = list(frames)

    def __aiter__(self):
        return self

    async def __anext__(self):
        if not self._frames:
            raise StopAsyncIteration
        return SimpleNamespace(frame=self._frames.pop(0))

    async def aclose(self) -> None:
        pass


class TranscribeAudioSecondsTest(unittest.IsolatedAsyncioTestCase):
    async def test_every_frame_sent_to_deepgram_adds_its_duration(self):
        stream = PushStream()
        meter = UsageMeter()

        async def fake_process(*_args, **_kwargs):
            await asyncio.wait_for(stream.ended.wait(), timeout=1)

        with patch.object(worker, "process_speech_stream", fake_process):
            await transcribe(
                MockRoom(),
                learner=None,
                context={"language": "pt-BR", "keyterms": []},
                tracker=TurnTracker("s1", last_turn_id=0),
                phoenix=SimpleNamespace(eof_timeout=1.0),
                stt=MockSTT(stream),
                audio=FrameAudio([audio_frame(8000), audio_frame(8000), audio_frame(16000)]),
                meter=meter,
            )

        self.assertEqual(len(stream.frames), 3)
        self.assertEqual(meter.report("AJ_1")["deepgram_audio_seconds"], 2.0)


if __name__ == "__main__":
    unittest.main()
