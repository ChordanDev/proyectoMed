# pyright: reportMissingImports=false
import asyncio
import json
import unittest

import httpx
from livekit.agents import APIConnectionError, APIStatusError, APITimeoutError
from livekit.agents.language import LanguageCode
from livekit.agents.stt import SpeechData, SpeechEvent, SpeechEventType

from transcripts import (
    PhoenixClient,
    TurnManager,
    TurnTracker,
    VoiceFailure,
    VoiceTurnReply,
    classify_provider_error,
    process_speech_stream,
)
from worker import transcribe


def event(kind, text=None):
    alternatives = (
        [] if text is None else [SpeechData(language=LanguageCode("pt-BR"), text=text)]
    )
    return SpeechEvent(type=kind, alternatives=alternatives)


INTERIM = SpeechEventType.INTERIM_TRANSCRIPT
FINAL = SpeechEventType.FINAL_TRANSCRIPT
END = SpeechEventType.END_OF_SPEECH


class VoiceTurnReplyTest(unittest.TestCase):
    def test_equality_with_reply_instances(self):
        reply = VoiceTurnReply(
            turn_id=1, status="committed", generation_id=1, reply_text="Olá"
        )
        self.assertEqual(
            reply,
            VoiceTurnReply(
                turn_id=1, status="committed", generation_id=1, reply_text="Olá"
            ),
        )
        # Speculative string equality removed; non-reply types must not compare equal
        self.assertNotEqual(reply, "committed")
        self.assertNotEqual(reply, "duplicate")
        self.assertNotEqual(
            reply,
            VoiceTurnReply(
                turn_id=2, status="committed", generation_id=1, reply_text="Olá"
            ),
        )

        dup = VoiceTurnReply(turn_id=1, status="duplicate")
        self.assertEqual(dup, VoiceTurnReply(turn_id=1, status="duplicate"))
        self.assertNotEqual(dup, "duplicate")
        self.assertNotEqual(dup, reply)

    def test_repr_and_str_never_contain_reply_text(self):
        clinical_content = "paciente com dor precordial aguda"
        reply = VoiceTurnReply(
            turn_id=1, status="committed", generation_id=1, reply_text=clinical_content
        )
        self.assertNotIn(clinical_content, repr(reply))
        self.assertNotIn(clinical_content, str(reply))


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
            {
                "session_id": "s1",
                "turn_id": 1,
                "final": False,
                "text": "Onde dói? desde",
            },
        )
        tracker.handle(event(FINAL, "Desde quando?"))

        self.assertEqual(
            tracker.handle(event(END)),
            {
                "session_id": "s1",
                "turn_id": 1,
                "final": True,
                "text": "Onde dói? Desde quando?",
            },
        )
        next_event = tracker.handle(event(INTERIM, "e"))
        assert next_event is not None
        self.assertEqual(next_event["turn_id"], 2)

    def test_turn_ids_continue_after_phoenix_last_turn(self):
        tracker = TurnTracker("s1", last_turn_id=7)
        tracker.handle(event(FINAL, "oi"))
        end_event = tracker.handle(event(END))
        assert end_event is not None
        self.assertEqual(end_event["turn_id"], 8)

    def test_end_of_speech_without_text_does_not_consume_a_turn(self):
        tracker = TurnTracker("s1", last_turn_id=0)
        self.assertIsNone(tracker.handle(event(END)))
        tracker.handle(event(FINAL, "   "))
        self.assertIsNone(tracker.handle(event(END)))
        tracker.handle(event(FINAL, "oi"))
        end_event = tracker.handle(event(END))
        assert end_event is not None
        self.assertEqual(end_event["turn_id"], 1)

    def test_ignores_other_events_and_rejects_malformed_transcripts(self):
        tracker = TurnTracker("s1", last_turn_id=0)
        self.assertIsNone(tracker.handle(event(SpeechEventType.START_OF_SPEECH)))
        with self.assertRaises(VoiceFailure) as ctx:
            tracker.handle(event(FINAL))
        self.assertEqual(ctx.exception.kind, "malformed")

    def test_accept_reply_validates_generation_bound_reply(self):
        tracker = TurnTracker("s1", last_turn_id=0)
        reply = VoiceTurnReply(
            turn_id=1, status="committed", generation_id=1, reply_text="Dói no peito."
        )

        accepted = tracker.accept_reply(reply)
        self.assertIsNotNone(accepted)
        assert accepted is not None
        self.assertEqual(accepted.generation_id, 1)
        self.assertEqual(tracker.active_generation_id, 1)
        self.assertEqual(tracker.last_accepted_turn_id, 1)

    def test_accept_reply_rejects_duplicates(self):
        tracker = TurnTracker("s1", last_turn_id=0)
        dup = VoiceTurnReply(turn_id=1, status="duplicate")
        self.assertIsNone(tracker.accept_reply(dup))

    def test_accept_reply_rejects_cancelled_generations(self):
        tracker = TurnTracker("s1", last_turn_id=0)
        tracker.cancel(generation_id=1)

        reply = VoiceTurnReply(
            turn_id=1, status="committed", generation_id=1, reply_text="Dói no peito."
        )
        self.assertIsNone(tracker.accept_reply(reply))

    def test_accept_reply_rejects_cancelled_turn_id(self):
        tracker = TurnTracker("s1", last_turn_id=0)
        tracker.cancel(turn_id=1)

        reply = VoiceTurnReply(
            turn_id=1, status="committed", generation_id=1, reply_text="Dói no peito."
        )
        self.assertIsNone(tracker.accept_reply(reply))

    def test_mark_turn_stale_and_is_turn_stale(self):
        tracker = TurnTracker("s1", last_turn_id=0)
        self.assertFalse(tracker.is_turn_stale(1))
        tracker.mark_turn_stale(1)
        self.assertTrue(tracker.is_turn_stale(1))

        reply = VoiceTurnReply(
            turn_id=1, status="committed", generation_id=1, reply_text="Dói no peito."
        )
        self.assertIsNone(tracker.accept_reply(reply))

    def test_accept_reply_rejects_superseded_generations_and_turns(self):
        tracker = TurnTracker("s1", last_turn_id=0)
        reply2 = VoiceTurnReply(
            turn_id=2,
            status="committed",
            generation_id=2,
            reply_text="Segunda resposta",
        )
        self.assertIsNotNone(tracker.accept_reply(reply2))

        # Stale turn 1 / generation 1 arriving after turn 2 is rejected
        stale_reply = VoiceTurnReply(
            turn_id=1, status="committed", generation_id=1, reply_text="Primeira tardia"
        )
        self.assertIsNone(tracker.accept_reply(stale_reply))

    def test_accept_reply_rejects_empty_or_missing_text_or_generation_id(self):
        tracker = TurnTracker("s1", last_turn_id=0)

        # Missing generation_id
        no_gen = VoiceTurnReply(
            turn_id=1, status="committed", generation_id=None, reply_text="Texto"
        )
        self.assertIsNone(tracker.accept_reply(no_gen))

        # Missing or empty reply_text
        empty_text = VoiceTurnReply(
            turn_id=1, status="committed", generation_id=1, reply_text=""
        )
        self.assertIsNone(tracker.accept_reply(empty_text))


class ProviderErrorTest(unittest.TestCase):
    def test_maps_provider_errors_to_typed_failures(self):
        self.assertEqual(
            classify_provider_error(APIStatusError("x", status_code=401)).kind, "auth"
        )
        self.assertEqual(
            classify_provider_error(APIStatusError("x", status_code=500)).kind,
            "disconnected",
        )
        self.assertEqual(classify_provider_error(APITimeoutError()).kind, "timeout")
        self.assertEqual(
            classify_provider_error(APIConnectionError()).kind, "disconnected"
        )
        self.assertEqual(
            classify_provider_error(ValueError("secret-key audio")).kind, "malformed"
        )

    def test_failure_message_never_carries_provider_details(self):
        failure = classify_provider_error(
            APIStatusError("token=dg_secret", status_code=401)
        )
        self.assertNotIn("dg_secret", str(failure))


def phoenix(handler):
    return PhoenixClient(
        "http://phoenix", "secret", "s1", transport=httpx.MockTransport(handler)
    )


class PhoenixClientTest(unittest.IsolatedAsyncioTestCase):
    async def test_context_sends_bearer_secret(self):
        def handler(request):
            self.assertEqual(request.url.path, "/api/internal/voice/sessions/s1")
            self.assertEqual(request.headers["authorization"], "Bearer secret")
            return httpx.Response(
                200,
                json={"language": "pt-BR", "keyterms": ["angina"], "last_turn_id": 3},
            )

        async with phoenix(handler) as client:
            self.assertEqual((await client.context())["last_turn_id"], 3)

    async def test_commit_posts_turn_and_returns_typed_reply(self):
        def handler(request):
            body = json.loads(request.content)
            self.assertEqual(body, {"turn_id": 1, "text": "Onde dói?"})
            return httpx.Response(
                201,
                json={
                    "status": "committed",
                    "turn_id": 1,
                    "generation_id": 1,
                    "reply_text": "Estou sentindo uma forte dor no peito.",
                },
            )

        async with phoenix(handler) as client:
            reply = await client.commit(1, "Onde dói?")
            self.assertEqual(reply.status, "committed")
            self.assertEqual(reply.turn_id, 1)
            self.assertEqual(reply.generation_id, 1)
            self.assertEqual(reply.reply_text, "Estou sentindo uma forte dor no peito.")

    async def test_commit_posts_turn_and_reports_duplicates(self):
        def handler(request):
            body = json.loads(request.content)
            self.assertEqual(body, {"turn_id": 2, "text": "oi"})
            return httpx.Response(200, json={"turn_id": 2, "status": "duplicate"})

        async with phoenix(handler) as client:
            reply = await client.commit(2, "oi")
            self.assertEqual(reply.status, "duplicate")
            self.assertIsNone(reply.generation_id)
            self.assertIsNone(reply.reply_text)

    async def test_commit_retries_once_on_disconnect(self):
        calls = []

        def handler(request):
            calls.append(1)
            if len(calls) == 1:
                raise httpx.ConnectError("boom")
            return httpx.Response(
                201,
                json={
                    "turn_id": 1,
                    "status": "committed",
                    "generation_id": 1,
                    "reply_text": "ok",
                },
            )

        async with phoenix(handler) as client:
            reply = await client.commit(1, "oi")
            self.assertEqual(reply.status, "committed")
        self.assertEqual(len(calls), 2)

    async def test_cancel_posts_to_cancel_endpoint(self):
        calls = []

        def handler(request):
            self.assertEqual(request.url.path, "/api/internal/voice/sessions/s1/cancel")
            body = json.loads(request.content)
            calls.append(body)
            return httpx.Response(200, json={"status": "cancelled", "session_id": "s1"})

        async with phoenix(handler) as client:
            res1 = await client.cancel()
            self.assertEqual(res1["status"], "cancelled")

            res2 = await client.cancel(generation_id=2)
            self.assertEqual(res2["status"], "cancelled")

            res3 = await client.cancel(turn_id=1)
            self.assertEqual(res3["status"], "cancelled")

            res4 = await client.cancel(generation_id=3, turn_id=2)
            self.assertEqual(res4["status"], "cancelled")

        self.assertEqual(
            calls,
            [
                {},
                {"generation_id": 2},
                {"turn_id": 1},
                {"generation_id": 3, "turn_id": 2},
            ],
        )

    async def _assert_cancel_retries_once(self, exc: Exception):
        calls = []

        def handler(request):
            calls.append(1)
            if len(calls) == 1:
                raise exc
            return httpx.Response(
                200, json={"status": "cancelled", "session_id": "s1"}
            )

        async with phoenix(handler) as client:
            res = await client.cancel(turn_id=1)
            self.assertEqual(res["status"], "cancelled")
        self.assertEqual(len(calls), 2)

    async def test_cancel_retries_once_on_disconnect(self):
        await self._assert_cancel_retries_once(httpx.ConnectError("boom"))

    async def test_cancel_retries_once_on_timeout(self):
        await self._assert_cancel_retries_once(httpx.ReadTimeout("slow"))

    async def test_cancel_does_not_retry_on_auth_failure(self):
        calls = []

        def handler(request):
            calls.append(1)
            return httpx.Response(401, json={"error": "unauthorized"})

        async with phoenix(handler) as client:
            with self.assertRaises(VoiceFailure) as ctx:
                await client.cancel(turn_id=1)
            self.assertEqual(ctx.exception.kind, "auth")
        self.assertEqual(len(calls), 1)

    async def test_maps_phoenix_responses_to_typed_failures(self):
        cases = {
            401: "auth",
            403: "session_inactive",
            404: "session_inactive",
            409: "stale_generation",
            410: "session_inactive",
            422: "session_inactive",
            400: "malformed",
            500: "disconnected",
        }
        for status, kind in cases.items():
            async with phoenix(
                lambda request, s=status: httpx.Response(s, json={})
            ) as client:
                with self.assertRaises(VoiceFailure) as ctx:
                    await client.context()
                self.assertEqual(
                    ctx.exception.kind, kind, f"status {status} should map to {kind}"
                )

    async def test_timeouts_and_malformed_bodies_are_typed(self):
        def timeout(request):
            raise httpx.ReadTimeout("slow")

        async with phoenix(timeout) as client:
            with self.assertRaises(VoiceFailure) as ctx:
                await client.context()
            self.assertEqual(ctx.exception.kind, "timeout")

        async with phoenix(
            lambda request: httpx.Response(200, text="not json")
        ) as client:
            with self.assertRaises(VoiceFailure) as ctx:
                await client.context()
            self.assertEqual(ctx.exception.kind, "malformed")


class ControllablePhoenixClient(PhoenixClient):
    def __init__(self):
        super().__init__("http://phoenix", "secret", "s1")
        self.commit_calls: list[tuple[int, str]] = []
        self.cancel_calls: list[dict] = []
        self.commit_events: dict[int, asyncio.Event] = {}
        self.commit_delays: dict[int, asyncio.Event] = {}
        self.cancel_events: dict[int, asyncio.Event] = {}
        self.cancel_delays: dict[int, asyncio.Event] = {}
        self.replies: dict[int, VoiceTurnReply] = {}
        self.cancel_results: dict[int, dict] = {}
        self.commit_errors: dict[int, Exception] = {}
        self.cancel_errors: dict[int, Exception] = {}
        self.call_log: list[tuple] = []

    async def commit(self, turn_id: int, text: str) -> VoiceTurnReply:
        self.call_log.append(("commit_start", turn_id, text))
        self.commit_calls.append((turn_id, text))
        if turn_id in self.commit_events:
            self.commit_events[turn_id].set()
        if turn_id in self.commit_delays:
            await self.commit_delays[turn_id].wait()
        if turn_id in self.commit_errors:
            self.call_log.append(("commit_error", turn_id))
            raise self.commit_errors[turn_id]

        reply = self.replies.get(
            turn_id,
            VoiceTurnReply(
                turn_id=turn_id,
                status="committed",
                generation_id=turn_id,
                reply_text=f"Resposta clinica confidencial {turn_id}",
            ),
        )
        self.call_log.append(("commit_end", turn_id, reply.status))
        return reply

    async def cancel(
        self, generation_id: int | None = None, turn_id: int | None = None
    ) -> dict:
        self.call_log.append(("cancel_start", turn_id, generation_id))
        self.cancel_calls.append({"generation_id": generation_id, "turn_id": turn_id})
        if turn_id is not None and turn_id in self.cancel_events:
            self.cancel_events[turn_id].set()
        if turn_id is not None and turn_id in self.cancel_delays:
            await self.cancel_delays[turn_id].wait()
        if turn_id is not None and turn_id in self.cancel_errors:
            self.call_log.append(("cancel_error", turn_id))
            raise self.cancel_errors[turn_id]

        res = (
            self.cancel_results.get(turn_id, {"status": "cancelled", "turn_id": turn_id})
            if turn_id is not None
            else {"status": "cancelled"}
        )
        self.call_log.append(("cancel_end", turn_id))
        return res


class MockParticipant:
    def __init__(self, identity: str = "voice-worker"):
        self.identity = identity
        self.published_data: list[tuple[str, str, bool]] = []

    async def publish_data(
        self, data: str, topic: str = "transcript", reliable: bool = True
    ) -> None:
        self.published_data.append((data, topic, reliable))


class MockRoom:
    def __init__(self, connected: bool = True):
        self._connected = connected
        self.local_participant = MockParticipant("voice-worker")

    def isconnected(self) -> bool:
        return self._connected


class MockStream:
    def __init__(self, queue: asyncio.Queue[SpeechEvent | None]):
        self.queue = queue
        self.closed = False

    def __aiter__(self):
        return self

    async def __anext__(self) -> SpeechEvent:
        item = await self.queue.get()
        if item is None:
            raise StopAsyncIteration
        return item

    async def aclose(self) -> None:
        self.closed = True


class MockAudioStream:
    def __init__(self):
        self.closed = False

    def __aiter__(self):
        return self

    async def __anext__(self):
        raise StopAsyncIteration

    async def aclose(self) -> None:
        self.closed = True


class MockSTT:
    def __init__(self, stream: MockStream):
        self._stream = stream

    def stream(self):
        return self._stream


class StreamingTurnOrchestrationTest(unittest.IsolatedAsyncioTestCase):
    async def test_delayed_commit_with_new_speech_event_and_cancellation_order(self):
        client = ControllablePhoenixClient()
        client.commit_delays[1] = asyncio.Event()
        client.commit_events[1] = asyncio.Event()
        client.commit_events[2] = asyncio.Event()
        client.cancel_delays[1] = asyncio.Event()
        client.cancel_events[1] = asyncio.Event()

        tracker = TurnTracker("s1", last_turn_id=0)
        published: list[dict] = []
        queue: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()
        stream = MockStream(queue)

        stream_task = asyncio.create_task(
            process_speech_stream(
                stream, tracker, client, on_publish=lambda ev: published.append(ev)
            )
        )

        # Utterance 1
        queue.put_nowait(event(INTERIM, "onde"))
        queue.put_nowait(event(FINAL, "onde dói"))
        queue.put_nowait(event(END))

        # Wait until commit for turn 1 starts and suspends
        await client.commit_events[1].wait()
        self.assertEqual(len(client.commit_calls), 1)
        self.assertEqual(client.commit_calls[0][0], 1)
        self.assertFalse(tracker.is_turn_stale(1))

        # First new speech event for Utterance 2 arrives while turn 1 is still in-flight
        queue.put_nowait(event(INTERIM, "desde"))

        # Wait until cancel for turn 1 starts
        await client.cancel_events[1].wait()
        self.assertTrue(tracker.is_turn_stale(1))
        self.assertEqual(len(client.cancel_calls), 1)
        self.assertEqual(client.cancel_calls[0]["turn_id"], 1)

        # Utterance 2 finishes speaking
        queue.put_nowait(event(FINAL, "desde quando"))
        queue.put_nowait(event(END))

        # Yield to let event loop run - turn 2 commit should NOT start yet because cancel 1 is awaiting
        await asyncio.sleep(0.01)
        commit_starts = [log for log in client.call_log if log[0] == "commit_start"]
        self.assertEqual(len(commit_starts), 1)  # only turn 1 commit started so far

        # Release cancel 1
        client.cancel_delays[1].set()

        # Turn 2 commit can now start
        await client.commit_events[2].wait()
        commit_starts = [log for log in client.call_log if log[0] == "commit_start"]
        self.assertEqual(len(commit_starts), 2)
        self.assertEqual(commit_starts[1][1], 2)

        # Call log must confirm cancel(1) completed before commit(2) started
        log_order = [log[0] for log in client.call_log]
        idx_cancel_end = log_order.index("cancel_end")
        idx_commit_2_start = [
            i for i, log in enumerate(client.call_log) if log[:2] == ("commit_start", 2)
        ][0]
        self.assertLess(
            idx_cancel_end,
            idx_commit_2_start,
            "cancellation must complete before newer final is committed",
        )

        # Release delayed commit for turn 1: late reply arrives
        client.commit_delays[1].set()

        # End stream
        queue.put_nowait(None)
        await stream_task

        # Old result was suppressed!
        # tracker accepts turn 2, but turn 1 reply was rejected/suppressed
        self.assertEqual(tracker.last_accepted_turn_id, 2)
        self.assertEqual(tracker.active_generation_id, 2)

        # Verify patient text was NEVER published in transcript data channel
        for p in published:
            self.assertNotIn("reply_text", p)
            self.assertNotIn("Resposta clinica", json.dumps(p))

    async def test_start_of_speech_event_dispatches_cancellation_of_prior_turn(self):
        client = ControllablePhoenixClient()
        client.commit_delays[1] = asyncio.Event()
        client.commit_events[1] = asyncio.Event()
        client.cancel_events[1] = asyncio.Event()

        tracker = TurnTracker("s1", last_turn_id=0)
        queue: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()
        stream = MockStream(queue)

        stream_task = asyncio.create_task(
            process_speech_stream(stream, tracker, client)
        )

        # Turn 1 completes
        queue.put_nowait(event(FINAL, "primeira"))
        queue.put_nowait(event(END))
        await client.commit_events[1].wait()

        # START_OF_SPEECH arrives for turn 2
        queue.put_nowait(event(SpeechEventType.START_OF_SPEECH))
        await client.cancel_events[1].wait()

        self.assertTrue(tracker.is_turn_stale(1))
        self.assertEqual(client.cancel_calls[0]["turn_id"], 1)

        # Release commit 1 and end stream
        client.commit_delays[1].set()
        queue.put_nowait(None)
        await stream_task

        # Turn 1 result was suppressed
        self.assertEqual(tracker.last_accepted_turn_id, 0)

    async def test_duplicate_final_handled_without_corrupting_tracker(self):
        client = ControllablePhoenixClient()
        client.replies[1] = VoiceTurnReply(turn_id=1, status="duplicate")

        tracker = TurnTracker("s1", last_turn_id=0)
        queue: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()
        stream = MockStream(queue)

        stream_task = asyncio.create_task(
            process_speech_stream(stream, tracker, client)
        )

        queue.put_nowait(event(FINAL, "repetida"))
        queue.put_nowait(event(END))
        queue.put_nowait(None)
        await stream_task

        # Duplicate reply was not accepted into tracker
        self.assertEqual(tracker.last_accepted_turn_id, 0)
        self.assertIsNone(tracker.active_generation_id)

    async def test_cleanup_on_disconnect_cancels_in_flight_tasks(self):
        client = ControllablePhoenixClient()
        client.commit_delays[1] = asyncio.Event()
        client.commit_events[1] = asyncio.Event()

        tracker = TurnTracker("s1", last_turn_id=0)
        manager = TurnManager(tracker, client)

        manager.commit_turn(1, "pergunta lenta")
        await client.commit_events[1].wait()

        self.assertEqual(len(manager._all_tasks), 1)

        # Disconnect triggers cleanup
        await manager.cleanup()

        self.assertEqual(len(manager._all_tasks), 0)
        self.assertIsNone(manager.pending_turn_id)
        # Phoenix.cancel must be called to avoid orphaned model generation (#119 issue 2)
        self.assertEqual(len(client.cancel_calls), 1)
        self.assertEqual(client.cancel_calls[0]["turn_id"], 1)
        self.assertTrue(tracker.is_turn_stale(1))

        # Releasing event afterwards does not fail
        client.commit_delays[1].set()

    async def test_reconnect_preserves_monotonic_turn_tracker(self):
        client = ControllablePhoenixClient()
        tracker = TurnTracker("s1", last_turn_id=0)

        # Connection 1: Turn 1
        queue1: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()
        stream1 = MockStream(queue1)
        task1 = asyncio.create_task(process_speech_stream(stream1, tracker, client))

        queue1.put_nowait(event(FINAL, "pergunta um"))
        queue1.put_nowait(event(END))
        queue1.put_nowait(None)
        await task1

        self.assertEqual(tracker.last_accepted_turn_id, 1)

        # Connection 2: Learner reconnects; tracker segments reset
        tracker.segments = []
        queue2: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()
        stream2 = MockStream(queue2)
        task2 = asyncio.create_task(process_speech_stream(stream2, tracker, client))

        queue2.put_nowait(event(FINAL, "pergunta dois"))
        queue2.put_nowait(event(END))
        queue2.put_nowait(None)
        await task2

        self.assertEqual(tracker.last_accepted_turn_id, 2)
        self.assertEqual(len(client.commit_calls), 2)
        self.assertEqual(client.commit_calls[1][0], 2)

    async def test_unexpected_failure_in_commit_is_not_swallowed(self):
        client = ControllablePhoenixClient()
        client.commit_errors[1] = VoiceFailure("auth")

        tracker = TurnTracker("s1", last_turn_id=0)
        queue: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()
        stream = MockStream(queue)

        with self.assertRaises(VoiceFailure) as ctx:
            task = asyncio.create_task(process_speech_stream(stream, tracker, client))
            queue.put_nowait(event(FINAL, "pergunta sem auth"))
            queue.put_nowait(event(END))
            await task
        self.assertEqual(ctx.exception.kind, "auth")

    async def _assert_cancel_fatal_failure(self, error: Exception, expected_kind: str):
        """Harness for fatal/unhandled cancel errors that must abort the stream with typed failure."""
        client = ControllablePhoenixClient()
        client.commit_delays[1] = asyncio.Event()
        client.commit_events[1] = asyncio.Event()
        client.cancel_errors[1] = error

        tracker = TurnTracker("s1", last_turn_id=0)
        queue: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()
        stream = MockStream(queue)

        with self.assertRaises(VoiceFailure) as ctx:
            task = asyncio.create_task(process_speech_stream(stream, tracker, client))
            queue.put_nowait(event(FINAL, "pergunta 1"))
            queue.put_nowait(event(END))
            await client.commit_events[1].wait()

            # First event of turn 2 triggers cancel 1 which fails fatally
            queue.put_nowait(event(INTERIM, "pergunta 2"))
            queue.put_nowait(event(FINAL, "pergunta 2 final"))
            queue.put_nowait(event(END))
            client.commit_delays[1].set()
            await task
        self.assertEqual(ctx.exception.kind, expected_kind)

    async def _assert_cancel_transient_fallback(self, cancel_kind: str):
        """Harness for transient best-effort cancel failures where subsequent turn succeeds and old reply is suppressed."""
        client = ControllablePhoenixClient()
        client.commit_delays[1] = asyncio.Event()
        client.commit_events[1] = asyncio.Event()
        client.commit_events[2] = asyncio.Event()
        client.cancel_errors[1] = VoiceFailure(cancel_kind)

        tracker = TurnTracker("s1", last_turn_id=0)
        published: list[dict] = []
        queue: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()
        stream = MockStream(queue)

        stream_task = asyncio.create_task(
            process_speech_stream(
                stream, tracker, client, on_publish=lambda ev: published.append(ev)
            )
        )

        # Utterance 1 finishes speaking and starts commit
        queue.put_nowait(event(FINAL, "pergunta 1"))
        queue.put_nowait(event(END))
        await client.commit_events[1].wait()
        self.assertFalse(tracker.is_turn_stale(1))

        # Utterance 2 speech starts -> triggers cancel for turn 1 with transient error
        queue.put_nowait(event(INTERIM, "pergunta 2"))
        await asyncio.sleep(0.01)
        self.assertTrue(tracker.is_turn_stale(1))

        # Utterance 2 finishes speaking -> commit for turn 2 succeeds
        queue.put_nowait(event(FINAL, "pergunta 2 final"))
        queue.put_nowait(event(END))
        await client.commit_events[2].wait()

        self.assertEqual(tracker.last_accepted_turn_id, 2)
        self.assertEqual(tracker.active_generation_id, 2)

        # Release delayed commit for turn 1: late reply arrives and is suppressed
        client.commit_delays[1].set()
        await asyncio.sleep(0.01)

        # End stream
        queue.put_nowait(None)
        await stream_task

        # Turn 2 accepted, turn 1 late reply was suppressed
        self.assertEqual(tracker.last_accepted_turn_id, 2)
        self.assertEqual(tracker.active_generation_id, 2)
        self.assertTrue(tracker.is_turn_stale(1))

        # Patient clinical reply was never published in transcript data channel
        for p in published:
            self.assertNotIn("reply_text", p)
            self.assertNotIn("Resposta clinica", json.dumps(p))

    async def test_unexpected_failure_in_cancel_is_not_swallowed(self):
        await self._assert_cancel_fatal_failure(
            VoiceFailure("session_inactive"), "session_inactive"
        )

    async def test_stale_generation_on_cancel_is_handled_cleanly(self):
        await self._assert_cancel_transient_fallback("stale_generation")

    async def test_cancel_timeout_fallback_allows_newer_commit_and_suppresses_old_reply(
        self,
    ):
        await self._assert_cancel_transient_fallback("timeout")

    async def test_cancel_disconnect_fallback_allows_newer_commit_and_suppresses_old_reply(
        self,
    ):
        await self._assert_cancel_transient_fallback("disconnected")

    async def test_cancel_in_flight_timeout_unblocks_commit_and_succeeds(self):
        client = ControllablePhoenixClient()
        client.commit_delays[1] = asyncio.Event()
        client.commit_events[1] = asyncio.Event()
        client.commit_events[2] = asyncio.Event()
        client.cancel_delays[1] = asyncio.Event()
        client.cancel_events[1] = asyncio.Event()
        client.cancel_errors[1] = VoiceFailure("timeout")

        tracker = TurnTracker("s1", last_turn_id=0)
        queue: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()
        stream = MockStream(queue)

        stream_task = asyncio.create_task(
            process_speech_stream(stream, tracker, client)
        )

        queue.put_nowait(event(FINAL, "pergunta 1"))
        queue.put_nowait(event(END))
        await client.commit_events[1].wait()

        # Turn 2 speech starts -> cancel 1 starts and waits at delay
        queue.put_nowait(event(INTERIM, "pergunta 2"))
        await client.cancel_events[1].wait()

        # Turn 2 finishes -> commit 2 is scheduled, which awaits cancel 1
        queue.put_nowait(event(FINAL, "pergunta 2 final"))
        queue.put_nowait(event(END))
        await asyncio.sleep(0.01)

        # Release cancel delay with timeout error
        client.cancel_delays[1].set()

        # Turn 2 commit proceeds and succeeds
        await client.commit_events[2].wait()
        self.assertEqual(tracker.last_accepted_turn_id, 2)

        # Release turn 1 commit delay
        client.commit_delays[1].set()
        queue.put_nowait(None)
        await stream_task

        self.assertEqual(tracker.last_accepted_turn_id, 2)
        self.assertTrue(tracker.is_turn_stale(1))

    async def test_cancel_permanent_auth_failure_is_surfaced_to_stream(self):
        await self._assert_cancel_fatal_failure(VoiceFailure("auth"), "auth")

    async def test_cancel_unexpected_error_is_surfaced_to_stream(self):
        await self._assert_cancel_fatal_failure(
            RuntimeError("database exploded"), "malformed"
        )

    async def test_cancel_malformed_error_is_surfaced_to_stream(self):
        await self._assert_cancel_fatal_failure(VoiceFailure("malformed"), "malformed")

    async def test_transcribe_end_to_end_with_mock_room_and_streams(self):
        client = ControllablePhoenixClient()
        tracker = TurnTracker("s1", last_turn_id=0)
        room = MockRoom()
        queue: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()
        stream = MockStream(queue)
        stt = MockSTT(stream)
        audio = MockAudioStream()

        transcribe_task = asyncio.create_task(
            transcribe(
                room,
                learner=None,
                context={"language": "pt-BR", "keyterms": []},
                tracker=tracker,
                phoenix=client,
                stt=stt,
                audio=audio,
            )
        )

        queue.put_nowait(event(INTERIM, "teste"))
        queue.put_nowait(event(FINAL, "teste de voz"))
        queue.put_nowait(event(END))
        queue.put_nowait(None)

        await transcribe_task

        self.assertEqual(tracker.last_accepted_turn_id, 1)
        self.assertTrue(room.local_participant.published_data)
        # Confirm topic is "transcript" and payload has NO patient text
        for data, topic, reliable in room.local_participant.published_data:
            self.assertEqual(topic, "transcript")
            self.assertTrue(reliable)
            parsed = json.loads(data)
            self.assertNotIn("reply_text", parsed)
            self.assertNotIn("Resposta clinica", data)

    async def test_pending_commit_marked_stale_during_cancel_wait_does_not_call_commit(
        self,
    ):
        client = ControllablePhoenixClient()
        client.commit_delays[1] = asyncio.Event()
        client.commit_events[1] = asyncio.Event()
        client.cancel_delays[1] = asyncio.Event()
        client.cancel_events[1] = asyncio.Event()

        tracker = TurnTracker("s1", last_turn_id=0)
        queue: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()
        stream = MockStream(queue)

        stream_task = asyncio.create_task(
            process_speech_stream(stream, tracker, client)
        )

        # Utterance 1 finishes and starts committing
        queue.put_nowait(event(FINAL, "pergunta 1"))
        queue.put_nowait(event(END))
        await client.commit_events[1].wait()

        # Utterance 2 speech begins, triggering cancel for turn 1
        queue.put_nowait(event(INTERIM, "pergunta 2"))
        await client.cancel_events[1].wait()

        # Utterance 2 finishes, queuing commit for turn 2 (which awaits cancel 1)
        queue.put_nowait(event(FINAL, "pergunta 2 final"))
        queue.put_nowait(event(END))

        # Yield to ensure turn 2 commit task has started and is awaiting cancel 1
        await asyncio.sleep(0.01)

        # While cancel 1 is still in flight, Utterance 3 begins!
        # This triggers on_speech_event, which marks pending turn 2 stale!
        queue.put_nowait(event(INTERIM, "pergunta 3"))
        await asyncio.sleep(0.01)
        self.assertTrue(tracker.is_turn_stale(2))

        # Now let cancel 1 complete
        client.cancel_delays[1].set()
        await asyncio.sleep(0.01)

        # Turn 2 must NOT have sent commit to Phoenix!
        commit_turns = [turn_id for turn_id, _ in client.commit_calls]
        self.assertNotIn(2, commit_turns, "stale turn 2 must not be sent to Phoenix")

        # Release delayed commit 1 and end stream
        client.commit_delays[1].set()
        queue.put_nowait(None)
        await stream_task

    async def test_earlier_background_task_failure_is_not_swallowed_when_later_task_succeeds(
        self,
    ):
        client = ControllablePhoenixClient()
        client.commit_events[1] = asyncio.Event()
        client.commit_delays[1] = asyncio.Event()
        client.commit_errors[1] = VoiceFailure("auth")
        client.commit_events[2] = asyncio.Event()

        tracker = TurnTracker("s1", last_turn_id=0)
        queue: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()
        stream = MockStream(queue)

        with self.assertRaises(VoiceFailure) as ctx:
            stream_task = asyncio.create_task(
                process_speech_stream(stream, tracker, client)
            )

            # Turn 1 starts committing and suspends in Phoenix client
            queue.put_nowait(event(FINAL, "pergunta 1"))
            queue.put_nowait(event(END))
            await client.commit_events[1].wait()

            # Turn 2 commits
            queue.put_nowait(event(FINAL, "pergunta 2"))
            queue.put_nowait(event(END))
            await client.commit_events[2].wait()

            # Now background task 1 fails while task 2 succeeded
            client.commit_delays[1].set()

            # Stream ends immediately
            queue.put_nowait(None)
            await stream_task

        self.assertEqual(ctx.exception.kind, "auth")

    async def test_background_cancel_failure_is_not_swallowed_when_stream_ends(self):
        client = ControllablePhoenixClient()
        client.cancel_errors[1] = VoiceFailure("session_inactive")

        tracker = TurnTracker("s1", last_turn_id=0)
        queue: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()
        stream = MockStream(queue)

        with self.assertRaises(VoiceFailure) as ctx:
            stream_task = asyncio.create_task(
                process_speech_stream(stream, tracker, client)
            )

            # Turn 1 completes successfully
            queue.put_nowait(event(FINAL, "pergunta 1"))
            queue.put_nowait(event(END))

            # New speech triggers cancel 1 which will fail in background
            queue.put_nowait(event(INTERIM, "nova fala"))

            # Stream ends before turn 2 completes
            queue.put_nowait(None)
            await stream_task

        self.assertEqual(ctx.exception.kind, "session_inactive")

    async def test_transcript_data_channel_never_publishes_clinical_patient_reply(
        self,
    ):
        client = ControllablePhoenixClient()
        clinical_reply = "Paciente relata dor precordial em aperto com irradiação"
        client.replies[1] = VoiceTurnReply(
            turn_id=1, status="committed", generation_id=1, reply_text=clinical_reply
        )

        tracker = TurnTracker("s1", last_turn_id=0)
        room = MockRoom()
        queue: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()
        stream = MockStream(queue)
        stt = MockSTT(stream)
        audio = MockAudioStream()

        transcribe_task = asyncio.create_task(
            transcribe(
                room,
                learner=None,
                context={"language": "pt-BR", "keyterms": []},
                tracker=tracker,
                phoenix=client,
                stt=stt,
                audio=audio,
            )
        )

        queue.put_nowait(event(INTERIM, "onde dói"))
        queue.put_nowait(event(FINAL, "onde dói exatamente"))
        queue.put_nowait(event(END))
        queue.put_nowait(None)

        await transcribe_task

        # Verify all published messages on data channel:
        # 1. Topic must be "transcript"
        # 2. No clinical reply text or reply_text key in any payload
        self.assertGreater(len(room.local_participant.published_data), 0)
        for data, topic, reliable in room.local_participant.published_data:
            self.assertEqual(topic, "transcript")
            self.assertTrue(reliable)
            self.assertNotIn("reply_text", data)
            self.assertNotIn(clinical_reply, data)
            self.assertNotIn("dor precordial", data)

    def test_stale_or_duplicate_reply_rejected_for_synthesis(self):
        tracker = TurnTracker("s1", last_turn_id=0)

        # Duplicate without reply_text
        dup = VoiceTurnReply(turn_id=1, status="duplicate")
        self.assertFalse(tracker.is_valid_reply(dup))
        self.assertIsNone(tracker.accept_reply(dup))

        # Duplicate even with text (status != "committed")
        dup_with_text = VoiceTurnReply(
            turn_id=1, status="duplicate", generation_id=1, reply_text="texto"
        )
        self.assertFalse(tracker.is_valid_reply(dup_with_text))
        self.assertIsNone(tracker.accept_reply(dup_with_text))

        # Stale generation
        tracker.active_generation_id = 5
        stale_gen = VoiceTurnReply(
            turn_id=2, status="committed", generation_id=4, reply_text="texto"
        )
        self.assertFalse(tracker.is_valid_reply(stale_gen))
        self.assertIsNone(tracker.accept_reply(stale_gen))

        # Stale turn
        tracker.last_accepted_turn_id = 3
        stale_turn = VoiceTurnReply(
            turn_id=2, status="committed", generation_id=6, reply_text="texto"
        )
        self.assertFalse(tracker.is_valid_reply(stale_turn))
        self.assertIsNone(tracker.accept_reply(stale_turn))


if __name__ == "__main__":
    unittest.main()
