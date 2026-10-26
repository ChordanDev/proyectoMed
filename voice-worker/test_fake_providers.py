# pyright: reportMissingImports=false
import array
import os
import unittest
from types import SimpleNamespace
from typing import ClassVar
from unittest.mock import AsyncMock, Mock, patch

import httpx

from livekit import rtc
from livekit.agents.stt import SpeechEventType

import worker
from fake_providers import (
    DEFAULT_FAKE_TRANSCRIPT,
    FakeSTT,
    FakeTTS,
    fake_providers_from_env,
)

CONTEXT = {"language": "pt-BR", "keyterms": []}


def frame(amplitude: int, ms: int = 10, sample_rate: int = 16000) -> rtc.AudioFrame:
    samples = sample_rate * ms // 1000
    # A square wave: loud enough for any amplitude, with no maths to get wrong.
    data = array.array(
        "h", [amplitude if i % 2 else -amplitude for i in range(samples)]
    )
    return rtc.AudioFrame(data.tobytes(), sample_rate, 1, samples)


async def events_of(stream) -> list:
    return [event async for event in stream]


class FakeProvidersFromEnvTest(unittest.TestCase):
    def test_off_unless_the_switch_is_on(self):
        self.assertIsNone(
            fake_providers_from_env({"LIVEKIT_URL": "ws://127.0.0.1:7880"})
        )
        self.assertIsNone(
            fake_providers_from_env(
                {
                    "VOICE_WORKER_FAKE_PROVIDERS": "false",
                    "LIVEKIT_URL": "ws://127.0.0.1:7880",
                }
            )
        )

    def test_on_with_a_loopback_livekit_returns_the_transcript(self):
        for url in ("ws://127.0.0.1:7880", "ws://localhost:7880", "ws://[::1]:7880"):
            with self.subTest(url=url):
                self.assertEqual(
                    fake_providers_from_env(
                        {"VOICE_WORKER_FAKE_PROVIDERS": "true", "LIVEKIT_URL": url}
                    ),
                    DEFAULT_FAKE_TRANSCRIPT,
                )

    def test_the_transcript_can_be_set(self):
        env = {
            "VOICE_WORKER_FAKE_PROVIDERS": "true",
            "LIVEKIT_URL": "ws://127.0.0.1:7880",
            "VOICE_WORKER_FAKE_TRANSCRIPT": "Qual é a sua profissão?",
        }
        self.assertEqual(fake_providers_from_env(env), "Qual é a sua profissão?")

    def test_refused_when_livekit_is_not_on_loopback(self):
        for url in (
            "wss://station.livekit.cloud",
            "ws://10.0.0.5:7880",
            "",
            "ws://evil.com\\@localhost:7880",
            "ws://local host:7880",
            "ws://evil.com@localhost:7880",
        ):
            with self.subTest(url=url), self.assertRaises(ValueError):
                fake_providers_from_env(
                    {"VOICE_WORKER_FAKE_PROVIDERS": "true", "LIVEKIT_URL": url}
                )


class FakeSTTTest(unittest.IsolatedAsyncioTestCase):
    async def test_one_utterance_is_one_final_transcript_closed_by_end_of_speech(self):
        stream = FakeSTT("Qual é o seu nome?").stream()
        for _ in range(30):
            stream.push_frame(frame(6000))
        for _ in range(60):
            stream.push_frame(frame(0))
        stream.end_input()

        events = await events_of(stream)

        self.assertEqual(
            [event.type for event in events],
            [
                SpeechEventType.START_OF_SPEECH,
                SpeechEventType.FINAL_TRANSCRIPT,
                SpeechEventType.END_OF_SPEECH,
            ],
        )
        self.assertEqual(events[1].alternatives[0].text, "Qual é o seu nome?")

    async def test_a_pause_shorter_than_the_endpoint_keeps_one_utterance(self):
        stream = FakeSTT("Oi").stream()
        for amplitude, count in ((6000, 20), (0, 30), (6000, 20), (0, 60)):
            for _ in range(count):
                stream.push_frame(frame(amplitude))
        stream.end_input()

        types = [event.type for event in await events_of(stream)]

        self.assertEqual(types.count(SpeechEventType.FINAL_TRANSCRIPT), 1)

    async def test_two_utterances_are_two_turns(self):
        stream = FakeSTT("Oi").stream()
        for amplitude, count in ((6000, 20), (0, 60), (6000, 20), (0, 60)):
            for _ in range(count):
                stream.push_frame(frame(amplitude))
        stream.end_input()

        types = [event.type for event in await events_of(stream)]

        self.assertEqual(types.count(SpeechEventType.END_OF_SPEECH), 2)

    async def test_silence_and_quiet_noise_produce_nothing(self):
        stream = FakeSTT("Oi").stream()
        for _ in range(100):
            stream.push_frame(frame(100))
        stream.end_input()

        self.assertEqual(await events_of(stream), [])

    async def test_speech_cut_by_the_end_of_input_is_still_committed(self):
        stream = FakeSTT("Oi").stream()
        for _ in range(20):
            stream.push_frame(frame(6000))
        stream.end_input()

        types = [event.type for event in await events_of(stream)]

        self.assertEqual(types[-1], SpeechEventType.END_OF_SPEECH)

    async def test_aclose_ends_the_stream(self):
        stream = FakeSTT("Oi").stream()
        await stream.aclose()

        self.assertEqual(await events_of(stream), [])


class FakeTTSTest(unittest.IsolatedAsyncioTestCase):
    async def test_speaks_a_tone_whose_length_follows_the_text(self):
        tts = FakeTTS()
        short = [audio.frame async for audio in tts.synthesize("Sim.")]
        long = [audio.frame async for audio in tts.synthesize("Sim. " * 20)]

        def seconds(frames):
            return sum(f.samples_per_channel for f in frames) / tts.sample_rate

        self.assertEqual({f.sample_rate for f in short}, {tts.sample_rate})
        self.assertEqual({f.num_channels for f in short}, {1})
        self.assertGreater(max(abs(s) for s in short[0].data), 0)
        self.assertGreaterEqual(seconds(short), 0.4)
        self.assertGreater(seconds(long), seconds(short))
        self.assertLessEqual(seconds(long), 3.0)
        await tts.aclose()


class WorkerFakeModeTest(unittest.TestCase):
    FAKE_ENV: ClassVar[dict[str, str]] = {
        "VOICE_WORKER_FAKE_PROVIDERS": "true",
        "LIVEKIT_URL": "ws://127.0.0.1:7880",
    }

    def test_fake_mode_uses_the_fake_speech_without_cartesia_settings(self):
        with (
            patch.dict(os.environ, self.FAKE_ENV, clear=True),
            patch.object(worker.cartesia, "TTS") as tts,
        ):
            self.assertIsInstance(worker.build_tts("s1", CONTEXT), FakeTTS)
        tts.assert_not_called()

    def test_fake_mode_uses_the_fake_transcription_without_deepgram(self):
        with (
            patch.dict(os.environ, self.FAKE_ENV, clear=True),
            patch.object(worker.deepgram, "STT") as stt,
        ):
            self.assertIsInstance(worker.build_stt(CONTEXT), FakeSTT)
        stt.assert_not_called()

    def test_without_the_switch_the_real_providers_are_built(self):
        with (
            patch.dict(os.environ, {"LIVEKIT_URL": "ws://127.0.0.1:7880"}, clear=True),
            patch.object(worker.deepgram, "STT") as stt,
        ):
            self.assertIs(worker.build_stt(CONTEXT), stt.return_value)
        stt.assert_called_once_with(
            model="nova-3",
            language="pt-BR",
            interim_results=True,
            endpointing_ms=worker.ENDPOINTING_MS,
            keyterm=[],
            vad_events=False,
        )

    def test_voice_activity_without_words_starts_no_utterance(self):
        # Deepgram's SpeechStarted fires on noise and breath too; as a barge-in it
        # cancelled the turn the learner had just finished (#193). Without it the
        # plugin starts an utterance on its first transcribed words.
        with (
            patch.dict(os.environ, {"LIVEKIT_URL": "ws://127.0.0.1:7880"}, clear=True),
            patch.object(worker.deepgram, "STT") as stt,
        ):
            worker.build_stt(CONTEXT)
        self.assertIs(stt.call_args.kwargs.get("vad_events"), False)


class WorkerFakeModeJobTest(unittest.IsolatedAsyncioTestCase):
    async def test_a_non_loopback_livekit_url_fails_the_job_with_an_error_event(self):
        # `--url` can point the worker elsewhere than LIVEKIT_URL, so each job re-checks.
        def handler(request):
            return httpx.Response(
                200, json={"last_turn_id": 0, "language": "pt-BR", "keyterms": []}
            )

        room = SimpleNamespace(name="station-session-s1", isconnected=lambda: True)
        ctx = SimpleNamespace(
            room=room,
            connect=AsyncMock(),
            wait_for_participant=AsyncMock(),
            shutdown=Mock(),
        )
        env = {
            "VOICE_WORKER_FAKE_PROVIDERS": "true",
            "LIVEKIT_URL": "wss://livekit.example.com",
            "PHOENIX_URL": "http://phoenix",
            "VOICE_WORKER_SECRET": "secret",
        }
        client = worker.PhoenixClient(
            "http://phoenix", "secret", "s1", transport=httpx.MockTransport(handler)
        )
        with (
            patch.dict(os.environ, env, clear=True),
            patch.object(worker, "PhoenixClient", return_value=client),
            patch.object(worker, "publish", new=AsyncMock()) as publish,
            patch.object(worker, "FakeTTS") as fake_tts,
            patch.object(worker, "FakeSTT") as fake_stt,
            self.assertLogs("voice-worker", level="WARNING"),
        ):
            await worker.entrypoint(ctx)

        publish.assert_awaited_once_with(
            room, {"session_id": "s1", "error": "fake_providers_refused"}
        )
        fake_tts.assert_not_called()
        fake_stt.assert_not_called()
        ctx.wait_for_participant.assert_not_awaited()
        ctx.shutdown.assert_called_once()


if __name__ == "__main__":
    unittest.main()
