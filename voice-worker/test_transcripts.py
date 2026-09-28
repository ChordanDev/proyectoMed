import asyncio
import json
import unittest

import httpx
from livekit.agents import APIConnectionError, APIStatusError, APITimeoutError
from livekit.agents.stt import SpeechData, SpeechEvent, SpeechEventType

from transcripts import PhoenixClient, TurnTracker, VoiceFailure, classify_provider_error


def event(kind, text=None):
    alternatives = [] if text is None else [SpeechData(language="pt-BR", text=text)]
    return SpeechEvent(type=kind, alternatives=alternatives)


INTERIM = SpeechEventType.INTERIM_TRANSCRIPT
FINAL = SpeechEventType.FINAL_TRANSCRIPT
END = SpeechEventType.END_OF_SPEECH


class TurnTrackerTest(unittest.TestCase):
    def test_interims_are_turn_scoped_and_one_final_turn_per_utterance(self):
        tracker = TurnTracker("s1", last_turn_id=0)

        self.assertEqual(
            tracker.handle(event(INTERIM, "onde")),
            {"session_id": "s1", "turn_id": 1, "final": False, "text": "onde"},
        )
        self.assertEqual(
            tracker.handle(event(FINAL, "Onde dói?")),
            {"session_id": "s1", "turn_id": 1, "final": False, "text": "Onde dói?"},
        )
        self.assertEqual(
            tracker.handle(event(INTERIM, "desde")),
            {"session_id": "s1", "turn_id": 1, "final": False, "text": "Onde dói? desde"},
        )
        tracker.handle(event(FINAL, "Desde quando?"))

        self.assertEqual(
            tracker.handle(event(END)),
            {"session_id": "s1", "turn_id": 1, "final": True, "text": "Onde dói? Desde quando?"},
        )
        self.assertEqual(tracker.handle(event(INTERIM, "e"))["turn_id"], 2)

    def test_turn_ids_continue_after_phoenix_last_turn(self):
        tracker = TurnTracker("s1", last_turn_id=7)
        tracker.handle(event(FINAL, "oi"))
        self.assertEqual(tracker.handle(event(END))["turn_id"], 8)

    def test_end_of_speech_without_text_does_not_consume_a_turn(self):
        tracker = TurnTracker("s1", last_turn_id=0)
        self.assertIsNone(tracker.handle(event(END)))
        tracker.handle(event(FINAL, "   "))
        self.assertIsNone(tracker.handle(event(END)))
        tracker.handle(event(FINAL, "oi"))
        self.assertEqual(tracker.handle(event(END))["turn_id"], 1)

    def test_ignores_other_events_and_rejects_malformed_transcripts(self):
        tracker = TurnTracker("s1", last_turn_id=0)
        self.assertIsNone(tracker.handle(event(SpeechEventType.START_OF_SPEECH)))
        with self.assertRaises(VoiceFailure) as ctx:
            tracker.handle(event(FINAL))
        self.assertEqual(ctx.exception.kind, "malformed")


class ProviderErrorTest(unittest.TestCase):
    def test_maps_provider_errors_to_typed_failures(self):
        self.assertEqual(classify_provider_error(APIStatusError("x", status_code=401)).kind, "auth")
        self.assertEqual(classify_provider_error(APIStatusError("x", status_code=500)).kind, "disconnected")
        self.assertEqual(classify_provider_error(APITimeoutError()).kind, "timeout")
        self.assertEqual(classify_provider_error(APIConnectionError()).kind, "disconnected")
        self.assertEqual(classify_provider_error(ValueError("secret-key audio")).kind, "malformed")

    def test_failure_message_never_carries_provider_details(self):
        failure = classify_provider_error(APIStatusError("token=dg_secret", status_code=401))
        self.assertNotIn("dg_secret", str(failure))


def phoenix(handler):
    return PhoenixClient("http://phoenix", "secret", "s1", transport=httpx.MockTransport(handler))


class PhoenixClientTest(unittest.IsolatedAsyncioTestCase):
    async def test_context_sends_bearer_secret(self):
        def handler(request):
            self.assertEqual(request.url.path, "/api/internal/voice/sessions/s1")
            self.assertEqual(request.headers["authorization"], "Bearer secret")
            return httpx.Response(200, json={"language": "pt-BR", "keyterms": ["angina"], "last_turn_id": 3})

        async with phoenix(handler) as client:
            self.assertEqual((await client.context())["last_turn_id"], 3)

    async def test_commit_posts_turn_and_reports_duplicates(self):
        def handler(request):
            body = json.loads(request.content)
            self.assertEqual(body, {"turn_id": 2, "text": "oi"})
            return httpx.Response(200, json={"turn_id": 2, "status": "duplicate"})

        async with phoenix(handler) as client:
            self.assertEqual(await client.commit(2, "oi"), "duplicate")

    async def test_commit_retries_once_on_disconnect(self):
        calls = []

        def handler(request):
            calls.append(1)
            if len(calls) == 1:
                raise httpx.ConnectError("boom")
            return httpx.Response(201, json={"turn_id": 1, "status": "committed"})

        async with phoenix(handler) as client:
            self.assertEqual(await client.commit(1, "oi"), "committed")
        self.assertEqual(len(calls), 2)

    async def test_maps_phoenix_responses_to_typed_failures(self):
        cases = {
            401: "auth",
            403: "session_inactive",
            404: "session_inactive",
            410: "session_inactive",
            422: "session_inactive",
            400: "malformed",
            500: "disconnected",
        }
        for status, kind in cases.items():
            async with phoenix(lambda request, s=status: httpx.Response(s, json={})) as client:
                with self.assertRaises(VoiceFailure) as ctx:
                    await client.context()
                self.assertEqual(ctx.exception.kind, kind, status)

    async def test_timeouts_and_malformed_bodies_are_typed(self):
        def timeout(request):
            raise httpx.ReadTimeout("slow")

        async with phoenix(timeout) as client:
            with self.assertRaises(VoiceFailure) as ctx:
                await client.context()
            self.assertEqual(ctx.exception.kind, "timeout")

        async with phoenix(lambda request: httpx.Response(200, text="not json")) as client:
            with self.assertRaises(VoiceFailure) as ctx:
                await client.context()
            self.assertEqual(ctx.exception.kind, "malformed")


if __name__ == "__main__":
    unittest.main()
