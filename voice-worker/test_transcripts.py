# pyright: reportMissingImports=false
import asyncio
import json
import unittest
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock, patch

import httpx
from livekit.agents import APIConnectionError, APIStatusError, APITimeoutError
from livekit.agents.language import LanguageCode
from livekit.agents.stt import SpeechData, SpeechEvent, SpeechEventType

import transcripts
import worker
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
    def test_allocation_floor_does_not_claim_acceptance_or_replay_cancelled_reply(self):
        tracker = TurnTracker("s1", last_turn_id=0, turn_id_floor=7)
        self.assertEqual(tracker.last_accepted_turn_id, 0)
        self.assertIsNone(
            tracker.accept_reply(
                VoiceTurnReply(
                    turn_id=7,
                    status="committed",
                    generation_id=1,
                    reply_text="Cancelled reply",
                )
            )
        )
        tracker.handle(event(FINAL, "New question"))
        final = tracker.handle(event(END))
        assert final is not None
        self.assertEqual(final["turn_id"], 8)
        self.assertEqual(tracker.last_accepted_turn_id, 0)

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

    def test_accept_reply_accepts_a_kept_receipt_without_text(self):
        # Issue #269: a refused reply kept the learner turn; nothing is spoken.
        tracker = TurnTracker("s1", last_turn_id=0)
        kept = VoiceTurnReply(turn_id=1, status="kept", generation_id=1)

        self.assertIs(tracker.accept_reply(kept), kept)
        self.assertEqual(tracker.last_accepted_turn_id, 1)
        self.assertEqual(tracker.active_generation_id, 1)
        self.assertIsNone(tracker.accept_reply(kept))

    def test_accept_reply_rejects_malformed_kept_receipts(self):
        tracker = TurnTracker("s1", last_turn_id=0)
        for reply in (
            VoiceTurnReply(turn_id=1, status="kept", generation_id=None),
            VoiceTurnReply(turn_id=1, status="kept", generation_id=1, reply_text="x"),
            VoiceTurnReply(turn_id=0, status="kept", generation_id=1),
        ):
            self.assertIsNone(tracker.accept_reply(reply))
        self.assertEqual(tracker.last_accepted_turn_id, 0)

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

    async def test_commit_returns_a_kept_reply_without_text(self):
        def handler(request):
            return httpx.Response(
                201, json={"turn_id": 1, "status": "kept", "generation_id": 1}
            )

        async with phoenix(handler) as client:
            reply = await client.commit(1, "Abdome flácido, dor à palpação.")
        self.assertEqual(reply.status, "kept")
        self.assertEqual((reply.turn_id, reply.generation_id), (1, 1))
        self.assertIsNone(reply.reply_text)
        self.assertTrue(reply.is_kept_receipt())

    async def test_commit_reads_the_addressee_of_a_kept_reply(self):
        # Issue #274: a turn addressed to the examiner is kept before any
        # generation; a refused patient reply is kept with addressee `patient`.
        for addressee, acknowledged in (("examiner", True), ("patient", False)):

            def handler(request, addressee=addressee):
                return httpx.Response(
                    201,
                    json={
                        "turn_id": 1,
                        "status": "kept",
                        "generation_id": 1,
                        "addressee": addressee,
                    },
                )

            async with phoenix(handler) as client:
                reply = await client.commit(1, "Blumberg positivo.")
            self.assertTrue(reply.is_kept_receipt())
            self.assertEqual(reply.addressee, addressee)
            self.assertIs(reply.is_examiner_acknowledgement(), acknowledged)

    async def test_commit_reads_a_spoken_exam_request_receipt(self):
        # Issue #364: in exam mode Phoenix routes the turn to the impresso
        # request; the receipt has no generation and nothing to speak.
        outcome = {
            "request_id": "voice-exam-1",
            "decision": "released",
            "newly_released": [
                {"id": "lab", "title": "Laboratório", "category": "laboratory"}
            ],
            "feedback_message": "Impresso liberado: Laboratório",
        }

        def handler(request):
            return httpx.Response(
                201, json={"turn_id": 1, "status": "impresso_requested", **outcome}
            )

        async with phoenix(handler) as client:
            reply = await client.commit(1, "Solicito hemograma e PCR")
        self.assertTrue(reply.is_impresso_receipt())
        self.assertTrue(reply.is_settled_receipt())
        self.assertFalse(reply.is_kept_receipt())
        self.assertIsNone(reply.generation_id)
        self.assertIsNone(reply.reply_text)
        self.assertEqual(reply.impresso, outcome)

        tracker = TurnTracker("s1", 0)
        self.assertIs(tracker.accept_reply(reply), reply)
        self.assertEqual(tracker.last_accepted_turn_id, 1)
        # A retry of the same turn is not accepted twice.
        self.assertIsNone(tracker.accept_reply(reply))

    async def test_a_malformed_exam_receipt_is_not_settled(self):
        reply = VoiceTurnReply(turn_id=1, status="impresso_requested")
        self.assertFalse(reply.is_impresso_receipt())
        self.assertIsNone(TurnTracker("s1", 0).accept_reply(reply))

    async def test_a_kept_reply_from_an_older_server_is_not_an_acknowledgement(self):
        def handler(request):
            return httpx.Response(
                201, json={"turn_id": 1, "status": "kept", "generation_id": 1}
            )

        async with phoenix(handler) as client:
            reply = await client.commit(1, "Blumberg positivo.")
        self.assertIsNone(reply.addressee)
        self.assertFalse(reply.is_examiner_acknowledgement())

    async def test_commit_waits_for_the_server_budget_other_calls_stay_short(self):
        # Issue #269: generation + verification + one regeneration, plus headroom.
        self.assertGreaterEqual(
            transcripts.DEFAULT_TURN_TIMEOUT_S,
            2 * transcripts.PATIENT_GENERATION_TIMEOUT_S
            + transcripts.VERIFICATION_DEADLINE_S,
        )
        timeouts = {}

        def handler(request):
            timeouts[request.url.path] = request.extensions["timeout"]["read"]
            if request.url.path.endswith("/transcripts"):
                return httpx.Response(
                    201, json={"turn_id": 1, "status": "kept", "generation_id": 1}
                )
            return httpx.Response(200, json={"status": "cancelled", "last_turn_id": 0})

        async with phoenix(handler) as client:
            await client.context()
            await client.commit(1, "oi")
            await client.cancel(turn_id=1)

        base = "/api/internal/voice/sessions/s1"
        self.assertEqual(
            timeouts,
            {
                base: transcripts.REQUEST_TIMEOUT_S,
                base + "/transcripts": transcripts.DEFAULT_TURN_TIMEOUT_S,
                base + "/cancel": transcripts.REQUEST_TIMEOUT_S,
            },
        )

    async def test_turn_timeout_and_retries_are_configurable(self):
        calls = []

        def handler(request):
            calls.append(request.extensions["timeout"]["read"])
            raise httpx.ConnectError("boom")

        client = PhoenixClient(
            "http://phoenix",
            "secret",
            "s1",
            transport=httpx.MockTransport(handler),
            turn_timeout=12.0,
            turn_retries=2,
        )
        async with client:
            with self.assertRaises(VoiceFailure) as ctx:
                await client.commit(1, "oi")
        self.assertEqual(ctx.exception.kind, "disconnected")
        self.assertEqual(calls, [12.0, 12.0, 12.0])
        # The end-of-stream wait covers every attempt plus drain headroom.
        self.assertGreaterEqual(client.eof_timeout, 3 * 12.0)

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
            return httpx.Response(200, json={"status": "cancelled", "session_id": "s1"})

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

    async def test_station_time_elapsed_conflict_ends_the_session_without_retry(self):
        calls = []

        def handler(request):
            calls.append(request.url.path)
            return httpx.Response(409, json={"error": "station_time_elapsed"})

        async with phoenix(handler) as client:
            with self.assertRaises(VoiceFailure) as ctx:
                await client.commit(1, "Onde dói?")
            self.assertEqual(ctx.exception.kind, "station_time_elapsed")
            self.assertEqual(str(ctx.exception), "station_time_elapsed")
        self.assertEqual(calls, ["/api/internal/voice/sessions/s1/transcripts"])

    async def test_other_conflicts_stay_stale_generation(self):
        responses = {
            "stale code": httpx.Response(409, json={"error": "stale_generation"}),
            "unknown code": httpx.Response(409, json={"error": "something_else"}),
            "missing code": httpx.Response(409, json={}),
            "non-object body": httpx.Response(409, json=["station_time_elapsed"]),
            "unreadable body": httpx.Response(409, text="station_time_elapsed"),
            "empty body": httpx.Response(409),
        }
        for label, response in responses.items():
            with self.subTest(label):
                async with phoenix(lambda request, r=response: r) as client:
                    with self.assertRaises(VoiceFailure) as ctx:
                        await client.commit(1, "Onde dói?")
                    self.assertEqual(ctx.exception.kind, "stale_generation")

    async def test_station_time_elapsed_code_only_counts_on_a_conflict(self):
        async with phoenix(
            lambda request: httpx.Response(422, json={"error": "station_time_elapsed"})
        ) as client:
            with self.assertRaises(VoiceFailure) as ctx:
                await client.commit(1, "Onde dói?")
            self.assertEqual(ctx.exception.kind, "session_inactive")

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


def ndjson(*items) -> bytes:
    return b"".join(json.dumps(item).encode() + b"\n" for item in items)


def sentence_line(index: int, text: str, turn_id: int = 1, generation_id: int = 1):
    return {
        "type": "sentence",
        "turn_id": turn_id,
        "generation_id": generation_id,
        "index": index,
        "text": text,
    }


class PhoenixClientSentenceStreamTest(unittest.IsolatedAsyncioTestCase):
    """The transcript POST as a stream of verified sentences (#271)."""

    def client(self, handler, **options):
        return PhoenixClient(
            "http://phoenix",
            "secret",
            "s1",
            transport=httpx.MockTransport(handler),
            **options,
        )

    async def test_hands_over_each_sentence_in_order_then_returns_the_result(self):
        requests = []

        def handler(request):
            requests.append(request)
            return httpx.Response(
                200,
                headers={"content-type": "application/x-ndjson"},
                content=ndjson(
                    sentence_line(0, "Começou ontem."),
                    sentence_line(1, "Ainda dói."),
                    {
                        "type": "result",
                        "turn_id": 1,
                        "generation_id": 1,
                        "status": "committed",
                        "reply_text": "Começou ontem. Ainda dói.",
                    },
                ),
            )

        sentences = []

        async def on_sentence(sentence):
            sentences.append(sentence)

        async with self.client(handler) as client:
            reply = await client.commit(1, "Quando?", on_sentence=on_sentence)

        self.assertIn("application/x-ndjson", requests[0].headers["accept"])
        self.assertIn("application/json", requests[0].headers["accept"])
        self.assertEqual(requests[0].headers["authorization"], "Bearer secret")
        self.assertEqual(
            [(s.turn_id, s.generation_id, s.index, s.reply_text) for s in sentences],
            [(1, 1, 0, "Começou ontem."), (1, 1, 1, "Ainda dói.")],
        )
        self.assertTrue(all(s.is_committed_receipt() for s in sentences))
        self.assertEqual(
            reply,
            VoiceTurnReply(1, "committed", 1, "Começou ontem. Ainda dói."),
        )

    # Issue #341: a station with a companion labels each sentence.
    async def test_a_sentence_keeps_its_speaker_and_voice(self):
        def handler(request):
            return httpx.Response(
                200,
                headers={"content-type": "application/x-ndjson"},
                content=ndjson(
                    {
                        **sentence_line(0, "Começou ontem."),
                        "speaker": "companion",
                        "voice": "feminina-adulta",
                    },
                    sentence_line(1, "Ainda dói."),
                    {
                        "type": "result",
                        "turn_id": 1,
                        "status": "committed",
                        "generation_id": 1,
                        "reply_text": "Começou ontem. Ainda dói.",
                    },
                ),
            )

        sentences = []

        async def on_sentence(sentence):
            sentences.append(sentence)

        async with self.client(handler) as client:
            await client.commit(1, "Quando?", on_sentence=on_sentence)

        self.assertEqual(
            [(s.speaker, s.voice) for s in sentences],
            [("companion", "feminina-adulta"), (None, None)],
        )

    async def test_a_single_json_reply_is_still_understood(self):
        def handler(request):
            return httpx.Response(
                201, json={"turn_id": 1, "status": "kept", "generation_id": 1}
            )

        on_sentence = AsyncMock()
        async with self.client(handler) as client:
            reply = await client.commit(1, "Quando?", on_sentence=on_sentence)

        on_sentence.assert_not_called()
        self.assertTrue(reply.is_kept_receipt())

    async def test_status_errors_keep_their_kinds(self):
        def handler(request):
            return httpx.Response(409, json={"error": "station_time_elapsed"})

        async with self.client(handler) as client:
            with self.assertRaises(VoiceFailure) as ctx:
                await client.commit(1, "Quando?", on_sentence=AsyncMock())
        self.assertEqual(ctx.exception.kind, "station_time_elapsed")

    async def test_an_error_line_after_a_sentence_is_a_typed_failure(self):
        def handler(request):
            return httpx.Response(
                200,
                headers={"content-type": "application/x-ndjson"},
                content=ndjson(
                    sentence_line(0, "Começou ontem."),
                    {"type": "error", "error": "stale_generation"},
                ),
            )

        on_sentence = AsyncMock()
        async with self.client(handler) as client:
            with self.assertRaises(VoiceFailure) as ctx:
                await client.commit(1, "Quando?", on_sentence=on_sentence)
        self.assertEqual(ctx.exception.kind, "stale_generation")
        on_sentence.assert_awaited_once()

    async def test_an_error_line_with_a_non_string_error_is_malformed(self):
        for error in (["stale_generation"], {"kind": "auth"}, None, 409):
            with self.subTest(error=error):

                def handler(request):
                    return httpx.Response(
                        200,
                        headers={"content-type": "application/x-ndjson"},
                        content=ndjson({"type": "error", "error": error}),
                    )

                async with self.client(handler) as client:
                    with self.assertRaises(VoiceFailure) as ctx:
                        await client.commit(1, "Quando?", on_sentence=AsyncMock())
                self.assertEqual(ctx.exception.kind, "malformed")

    async def test_a_stream_cut_after_a_sentence_is_not_retried(self):
        calls = 0

        def handler(request):
            nonlocal calls
            calls += 1
            return httpx.Response(
                200,
                headers={"content-type": "application/x-ndjson"},
                content=ndjson(sentence_line(0, "Começou ontem.")),
            )

        async with self.client(handler, turn_retries=2) as client:
            with self.assertRaises(VoiceFailure) as ctx:
                await client.commit(1, "Quando?", on_sentence=AsyncMock())
        self.assertEqual(ctx.exception.kind, "disconnected")
        self.assertEqual(calls, 1)

    async def test_a_transport_failure_before_any_sentence_is_retried(self):
        calls = 0

        def handler(request):
            nonlocal calls
            calls += 1
            if calls == 1:
                raise httpx.ConnectError("down")
            return httpx.Response(
                200,
                headers={"content-type": "application/x-ndjson"},
                content=ndjson({"type": "result", "turn_id": 1, "status": "duplicate"}),
            )

        async with self.client(handler, turn_retries=1) as client:
            reply = await client.commit(1, "Quando?", on_sentence=AsyncMock())
        self.assertEqual(reply.status, "duplicate")
        self.assertEqual(calls, 2)

    async def test_a_malformed_line_is_malformed(self):
        def handler(request):
            return httpx.Response(
                200,
                headers={"content-type": "application/x-ndjson"},
                content=b"not json\n",
            )

        async with self.client(handler) as client:
            with self.assertRaises(VoiceFailure) as ctx:
                await client.commit(1, "Quando?", on_sentence=AsyncMock())
        self.assertEqual(ctx.exception.kind, "malformed")


class TurnTrackerSentenceTest(unittest.TestCase):
    def sentence(self, turn_id=1, generation_id=1, text="Começou ontem."):
        return VoiceTurnReply(turn_id, "committed", generation_id, text, index=0)

    def test_sentences_of_the_pending_turn_are_accepted_without_settling_it(self):
        tracker = TurnTracker("s1", last_turn_id=0)
        first = self.sentence()
        self.assertIs(tracker.accept_sentence(first), first)
        self.assertIsNotNone(tracker.accept_sentence(self.sentence(text="Dói.")))
        self.assertEqual(tracker.active_generation_id, 1)
        # The turn is not settled until Phoenix's result: it can still be barged in on.
        self.assertFalse(tracker.is_turn_stale(1))
        final = VoiceTurnReply(1, "committed", 1, "Começou ontem. Dói.")
        self.assertIs(tracker.accept_reply(final), final)
        self.assertTrue(tracker.is_turn_stale(1))

    def test_sentences_of_a_stale_turn_or_cancelled_generation_are_refused(self):
        tracker = TurnTracker("s1", last_turn_id=0)
        tracker.mark_turn_stale(1)
        self.assertIsNone(tracker.accept_sentence(self.sentence()))

        tracker = TurnTracker("s1", last_turn_id=0)
        tracker.cancel(generation_id=1)
        self.assertIsNone(tracker.accept_sentence(self.sentence()))

    def test_a_sentence_without_text_is_refused(self):
        tracker = TurnTracker("s1", last_turn_id=0)
        self.assertIsNone(tracker.accept_sentence(self.sentence(text=" ")))


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
        # Sentence streams (#271): each item is a sentence to hand over or an
        # asyncio.Event the stream waits for before going on.
        self.streams: dict[int, list] = {}

    async def commit(self, turn_id: int, text: str, on_sentence=None) -> VoiceTurnReply:
        self.call_log.append(("commit_start", turn_id, text))
        self.commit_calls.append((turn_id, text))
        if turn_id in self.commit_events:
            self.commit_events[turn_id].set()
        if turn_id in self.commit_delays:
            await self.commit_delays[turn_id].wait()
        if turn_id in self.commit_errors:
            self.call_log.append(("commit_error", turn_id))
            raise self.commit_errors[turn_id]
        if turn_id in self.streams and on_sentence is not None:
            spoken = []
            for item in self.streams[turn_id]:
                if isinstance(item, asyncio.Event):
                    await item.wait()
                    continue
                if isinstance(item, Exception):
                    raise item
                sentence = VoiceTurnReply(
                    turn_id=turn_id,
                    status="committed",
                    generation_id=turn_id,
                    reply_text=item,
                    index=len(spoken),
                )
                spoken.append(item)
                await on_sentence(sentence)
            self.replies.setdefault(
                turn_id,
                VoiceTurnReply(
                    turn_id=turn_id,
                    status="committed",
                    generation_id=turn_id,
                    reply_text=" ".join(spoken),
                ),
            )

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
            self.cancel_results.get(
                turn_id, {"status": "cancelled", "turn_id": turn_id}
            )
            if turn_id is not None
            else {"status": "cancelled"}
        )
        self.call_log.append(("cancel_end", turn_id))
        return res


class MockParticipant:
    def __init__(self, identity: str = "voice-worker"):
        self.identity = identity
        self.published_data: list[tuple[str, str, bool]] = []
        self.track_publications: dict[str, object] = {}

    async def publish_data(
        self, data: str, topic: str = "transcript", reliable: bool = True
    ) -> None:
        self.published_data.append((data, topic, reliable))


class MockRoom:
    def __init__(self, connected: bool = True):
        self._connected = connected
        self.local_participant = MockParticipant("voice-worker")
        self.handlers: dict[str, object] = {}

    def isconnected(self) -> bool:
        return self._connected

    def on(self, event_name: str, handler) -> None:
        self.handlers[event_name] = handler

    def off(self, event_name: str, handler) -> None:
        if self.handlers.get(event_name) is handler:
            del self.handlers[event_name]


class MockStream:
    def __init__(self, queue: asyncio.Queue[SpeechEvent | None]):
        self.queue = queue
        self.closed = False
        self.flushes = 0

    def flush(self) -> None:
        self.flushes += 1

    def __aiter__(self):
        return self

    async def __anext__(self) -> SpeechEvent:
        item = await self.queue.get()
        if item is None:
            raise StopAsyncIteration
        if isinstance(item, Exception):
            raise item
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
    async def test_fresh_job_bootstrap_allocates_above_context_floor(self):
        # Offline wire-contract proof; real Phoenix admission is covered by controller tests.
        for committed, floor, expected in [
            (0, 1, 2),
            (0, 7, 8),
            (9, 3, 10),
            (3, None, 4),
        ]:
            with self.subTest(committed=committed, floor=floor):
                context = {
                    "last_turn_id": committed,
                    "language": "pt-BR",
                    "keyterms": [],
                }
                if floor is not None:
                    context["turn_id_floor"] = floor
                posted = []
                usage = []

                def handler(request):
                    if request.method == "GET":
                        return httpx.Response(200, json=context)
                    if request.url.path.endswith("/usage"):
                        usage.append(json.loads(request.content))
                        return httpx.Response(202, json={"status": "recorded"})
                    body = json.loads(request.content)
                    posted.append(body)
                    if body["turn_id"] < expected:
                        return httpx.Response(409, json={"error": "stale_generation"})
                    return httpx.Response(
                        201,
                        json={
                            "status": "committed",
                            "turn_id": body["turn_id"],
                            "generation_id": 1,
                            "reply_text": "Verified reply",
                        },
                    )

                room = MockRoom()
                room.name = "station-session-s1"
                ctx = SimpleNamespace(
                    room=room,
                    connect=AsyncMock(),
                    wait_for_participant=AsyncMock(
                        return_value=MockParticipant("learner-s1")
                    ),
                    shutdown=Mock(),
                )
                queue = asyncio.Queue()
                for speech_event in [event(FINAL, "New question"), event(END), None]:
                    queue.put_nowait(speech_event)
                stream = MockStream(queue)
                stream.end_input = Mock()
                replies = []

                async def run_transcribe(
                    room, learner, context, tracker, phoenix, voice=None, meter=None
                ):
                    self.assertEqual(tracker.last_accepted_turn_id, committed)
                    self.assertIsInstance(voice, worker.PatientVoice)
                    # Typed replies are heard from the job's start (#325).
                    self.assertIn("data_received", room.handlers)
                    await transcribe(
                        room,
                        learner,
                        context,
                        tracker,
                        phoenix,
                        stt=MockSTT(stream),
                        audio=MockAudioStream(),
                        on_reply=replies.append,
                    )
                    if floor is not None and floor > committed:
                        self.assertTrue(tracker.is_turn_stale(floor))
                    room._connected = False

                with (
                    patch.dict(
                        "os.environ",
                        {
                            "PHOENIX_URL": "http://phoenix",
                            "VOICE_WORKER_SECRET": "secret",
                        },
                    ),
                    patch.object(
                        worker, "PhoenixClient", return_value=phoenix(handler)
                    ),
                    patch.object(worker, "transcribe", side_effect=run_transcribe),
                ):
                    await asyncio.wait_for(worker.entrypoint(ctx), timeout=2)

                self.assertEqual(
                    posted, [{"turn_id": expected, "text": "New question"}]
                )
                # The job's usage is reported once, when it ends (#342).
                self.assertEqual(len(usage), 1)
                self.assertEqual(
                    set(usage[0]),
                    {
                        "report_id",
                        "deepgram_audio_seconds",
                        "cartesia_characters",
                        "livekit_participant_minutes",
                    },
                )
                self.assertEqual(len(replies), 1)
                self.assertEqual(replies[0].turn_id, expected)
                ctx.shutdown.assert_called_once()

    async def test_station_time_elapsed_stops_the_worker_instead_of_marking_the_turn_stale(
        self,
    ):
        posted = []

        usage = []

        def handler(request):
            if request.method == "GET":
                return httpx.Response(
                    200, json={"last_turn_id": 0, "language": "pt-BR", "keyterms": []}
                )
            if request.url.path.endswith("/usage"):
                # The session is over, and the usage of its job is still reported (#342).
                usage.append(json.loads(request.content))
                return httpx.Response(202, json={"status": "recorded"})
            if request.url.path.endswith("/cancel"):
                # The timer already completed the session on the server.
                return httpx.Response(422, json={"error": "session_completed"})
            posted.append(json.loads(request.content))
            return httpx.Response(409, json={"error": "station_time_elapsed"})

        room = MockRoom()
        room.name = "station-session-s1"
        ctx = SimpleNamespace(
            room=room,
            connect=AsyncMock(),
            wait_for_participant=AsyncMock(return_value=MockParticipant("learner-s1")),
            shutdown=Mock(),
        )
        queue = asyncio.Queue()
        for speech_event in [event(FINAL, "Late question"), event(END), None]:
            queue.put_nowait(speech_event)
        stream = MockStream(queue)
        stream.end_input = Mock()
        replies = []
        streams_started = []

        async def run_transcribe(
            room, learner, context, tracker, phoenix, voice=None, meter=None
        ):
            streams_started.append(1)
            await transcribe(
                room,
                learner,
                context,
                tracker,
                phoenix,
                stt=MockSTT(stream),
                audio=MockAudioStream(),
                on_reply=replies.append,
            )

        with (
            patch.dict(
                "os.environ",
                {"PHOENIX_URL": "http://phoenix", "VOICE_WORKER_SECRET": "secret"},
            ),
            patch.object(worker, "PhoenixClient", return_value=phoenix(handler)),
            patch.object(worker, "transcribe", side_effect=run_transcribe),
            patch.object(worker, "publish", new=AsyncMock()) as publish,
            self.assertLogs("voice-worker", level="WARNING") as logs,
        ):
            await asyncio.wait_for(worker.entrypoint(ctx), timeout=2)

        # One attempt, no retry, and the job ends: a turn swallowed as a stale
        # generation would leave the worker waiting for the next utterance.
        self.assertEqual(posted, [{"turn_id": 1, "text": "Late question"}])
        self.assertEqual(replies, [])
        self.assertEqual(len(streams_started), 1)
        self.assertEqual(len(usage), 1)
        publish.assert_awaited_with(
            room, {"session_id": "s1", "error": "station_time_elapsed"}
        )
        ctx.shutdown.assert_called_once()
        self.assertTrue(
            any("s1: station_time_elapsed" in line for line in logs.output), logs.output
        )
        self.assertFalse(any("Late question" in line for line in logs.output))

    async def test_cancel_first_fences_held_http_admission_and_transport_retry(self):
        # Offline protocol model, paired with real GenServer/controller tests.
        # The POST reaches the transport but is held BEFORE server admission.
        posted = asyncio.Event()
        release_post = asyncio.Event()
        cancelled_through = 0
        active_turn = None
        attempts = []
        learner_appends = []
        patient_appends = []
        replies = []
        tasks_before = asyncio.all_tasks()

        async def handler(request):
            nonlocal cancelled_through, active_turn
            turn_id = json.loads(request.content)["turn_id"]
            if request.url.path.endswith("/cancel"):
                cancelled_through = max(cancelled_through, turn_id)
                if active_turn != turn_id:
                    return httpx.Response(409, json={"error": "stale_generation"})
                active_turn = None
                return httpx.Response(200, json={"status": "cancelled"})
            attempts.append(turn_id)
            if turn_id == 1:
                posted.set()
                await release_post.wait()
            if turn_id <= cancelled_through:
                if attempts == [1]:
                    # The rejected POST's response is lost; PhoenixClient retries.
                    raise httpx.ReadTimeout("Lost rejection", request=request)
                return httpx.Response(409, json={"error": "stale_generation"})
            learner_appends.append(turn_id)
            active_turn = turn_id
            patient_appends.append(turn_id)
            active_turn = None
            return httpx.Response(
                201,
                json={
                    "turn_id": turn_id,
                    "generation_id": turn_id,
                    "status": "committed",
                    "reply_text": "Patient reply",
                },
            )

        async with phoenix(handler) as client:
            manager = TurnManager(TurnTracker("s1", 0), client, on_reply=replies.append)
            try:
                async with asyncio.timeout(1):
                    old = manager.commit_turn(1, "Cancelled question")
                    await posted.wait()
                    await manager.on_speech_event(
                        event(SpeechEventType.START_OF_SPEECH)
                    )
                    self.assertEqual(cancelled_through, 1)
                    self.assertEqual(manager._unresolved_cancel_turns, set())
                    release_post.set()
                    self.assertIsNone(await old)
                    self.assertEqual(attempts, [1, 1])
                    self.assertEqual(learner_appends, [])
                    self.assertEqual(patient_appends, [])
                    self.assertEqual(
                        (await manager.commit_turn(2, "Later question")).turn_id, 2
                    )
                    await manager.wait_pending()
                    self.assertEqual(learner_appends, [2])
                    self.assertEqual(patient_appends, [2])
                    self.assertEqual([reply.turn_id for reply in replies], [2])
            finally:
                release_post.set()
                await asyncio.wait_for(manager.cleanup(), 1)
        self.assertEqual(asyncio.all_tasks(), tasks_before)

    async def test_eof_with_full_ambiguous_ownership_reaches_close_and_cleanup(self):
        tasks_before = asyncio.all_tasks()
        closed = False
        cleanup_calls = []

        async with ControllablePhoenixClient() as client:
            for turn_id in range(1, 17):
                client.replies[turn_id] = VoiceTurnReply(turn_id, "duplicate")
                client.commit_events[turn_id] = asyncio.Event()
                client.cancel_errors[turn_id] = VoiceFailure("timeout")
            client.cancel_events[16] = asyncio.Event()

            async def stream():
                for turn_id in range(1, 18):
                    yield event(FINAL, "Question")
                    yield event(END)
                    if turn_id <= 16:
                        await client.commit_events[turn_id].wait()
                    else:
                        await client.cancel_events[16].wait()
                # All failed cancel attempts have finished; capacity has no producer.
                await asyncio.sleep(0)

            async def close():
                nonlocal closed
                closed = True
                cleanup_calls.append(len(client.cancel_calls))

            task = asyncio.create_task(
                process_speech_stream(
                    stream(),
                    TurnTracker("s1", 0),
                    client,
                    on_close=close,
                    eof_timeout=0.03,
                    cleanup_timeout=0.03,
                )
            )
            try:
                done, _ = await asyncio.wait({task}, timeout=1)
                self.assertEqual(
                    done, {task}, "EOF must terminate without external cancellation"
                )
                with self.assertRaises(VoiceFailure) as ctx:
                    await task
                self.assertEqual(ctx.exception.kind, "timeout")
                self.assertTrue(closed)
                self.assertEqual(
                    [turn for turn, _ in client.commit_calls], list(range(1, 17))
                )
                self.assertEqual(
                    [
                        call["turn_id"]
                        for call in client.cancel_calls[cleanup_calls[0] :]
                    ],
                    list(range(1, 18)),
                )
            finally:
                if not task.done():
                    task.cancel()
                await asyncio.wait_for(asyncio.gather(task, return_exceptions=True), 1)
        self.assertEqual(asyncio.all_tasks(), tasks_before)

    async def test_recoverable_eof_delivers_latest_eligible_final_within_budget(self):
        replies = []
        closed = asyncio.Event()
        async with ControllablePhoenixClient() as client:
            client.commit_events[1] = asyncio.Event()
            client.commit_delays[1] = asyncio.Event()

            async def stream():
                yield event(FINAL, "Old question")
                yield event(END)
                await client.commit_events[1].wait()
                yield event(FINAL, "Latest question")
                yield event(END)
                client.commit_delays[1].set()

            async def close():
                closed.set()

            await asyncio.wait_for(
                process_speech_stream(
                    stream(),
                    TurnTracker("s1", 0),
                    client,
                    on_reply=replies.append,
                    on_close=close,
                    eof_timeout=0.3,
                ),
                1,
            )
            self.assertEqual([reply.turn_id for reply in replies], [2])
            self.assertTrue(closed.is_set())

    async def test_eof_budget_expiry_never_releases_ambiguous_ownership(self):
        tasks_before = asyncio.all_tasks()
        async with ControllablePhoenixClient() as client:
            manager = TurnManager(TurnTracker("s1", 0), client, cleanup_timeout=0.03)
            try:
                async with asyncio.timeout(1):
                    for turn_id in range(1, 17):
                        client.replies[turn_id] = VoiceTurnReply(turn_id, "duplicate")
                        client.cancel_errors[turn_id] = VoiceFailure("timeout")
                        await manager.commit_turn(turn_id, "Ambiguous question")
                        await manager.on_speech_event(event(INTERIM, "Next question"))
                    queued = manager.commit_turn(17, "Latest question")
                    with self.assertRaises(VoiceFailure) as ctx:
                        await manager.wait_pending(timeout=0.01)
                    self.assertEqual(ctx.exception.kind, "timeout")
                    self.assertEqual(
                        manager._unresolved_cancel_turns, set(range(1, 17))
                    )
                    self.assertFalse(queued.done())
                    self.assertEqual(len(client.commit_calls), 16)
                    await manager.cleanup()
                    self.assertTrue(queued.cancelled())
                    self.assertEqual(
                        manager._unresolved_cancel_turns, set(range(1, 17))
                    )
            finally:
                await asyncio.wait_for(manager.cleanup(), 1)
        self.assertEqual(asyncio.all_tasks(), tasks_before)

    async def test_ambiguous_ownership_capacity_blocks_dispatch_without_blocking_barge_in(
        self,
    ):
        tracker = TurnTracker("s1", 0)
        async with ControllablePhoenixClient() as client:
            manager = TurnManager(tracker, client)
            latest = None
            peak = 0
            try:
                async with asyncio.timeout(3):
                    for turn_id in range(1, manager.MAX_DISPATCHED_TURNS + 1):
                        client.replies[turn_id] = VoiceTurnReply(turn_id, "duplicate")
                        client.cancel_errors[turn_id] = VoiceFailure("timeout")
                        self.assertIsNone(
                            await manager.commit_turn(turn_id, "Ambiguous question")
                        )
                        await manager.on_speech_event(
                            event(SpeechEventType.START_OF_SPEECH)
                        )
                    owned = set(range(1, manager.MAX_DISPATCHED_TURNS + 1))
                    self.assertEqual(manager._unresolved_cancel_turns, owned)
                    hold = asyncio.Event()
                    client.cancel_errors.clear()
                    for turn_id in owned:
                        client.cancel_delays[turn_id] = hold
                    for turn_id in range(manager.MAX_DISPATCHED_TURNS + 1, 129):
                        manager.on_speech_event(event(FINAL, "Latest question"))
                        latest = manager.commit_turn(turn_id, "Latest question")
                        await asyncio.sleep(0)
                        peak = max(peak, len(manager._all_tasks))
                        self.assertEqual(manager._unresolved_cancel_turns, owned)
                        self.assertEqual(
                            len(client.commit_calls), manager.MAX_DISPATCHED_TURNS
                        )
                        self.assertEqual(
                            manager._queued_commit, (turn_id, "Latest question")
                        )
                    self.assertEqual(peak, 2)
                    hold.set()
                    self.assertEqual((await latest).turn_id, 128)
                    await manager.wait_pending()
                    self.assertEqual(manager._unresolved_cancel_turns, set())
                    self.assertEqual(client.commit_calls[-1], (128, "Latest question"))
            finally:
                for delayed in client.cancel_delays.values():
                    delayed.set()
                await manager.cleanup()

    async def test_running_http_capacity_keeps_a_single_latest_queued_final(self):
        tracker = TurnTracker("s1", 0)
        async with ControllablePhoenixClient() as client:
            manager = TurnManager(tracker, client)
            old_tasks = []
            latest = None
            try:
                async with asyncio.timeout(3):
                    for turn_id in range(1, manager.MAX_DISPATCHED_TURNS + 1):
                        client.commit_events[turn_id] = asyncio.Event()
                        client.commit_delays[turn_id] = asyncio.Event()
                        old_tasks.append(manager.commit_turn(turn_id, "Held question"))
                        await client.commit_events[turn_id].wait()
                        await manager.on_speech_event(event(INTERIM, "Next question"))
                    for turn_id in range(manager.MAX_DISPATCHED_TURNS + 1, 129):
                        manager.on_speech_event(event(FINAL, "Latest question"))
                        latest = manager.commit_turn(turn_id, "Latest question")
                        await asyncio.sleep(0)
                        self.assertLessEqual(
                            len(manager._all_tasks), manager.MAX_DISPATCHED_TURNS + 2
                        )
                        self.assertEqual(
                            len(client.commit_calls), manager.MAX_DISPATCHED_TURNS
                        )
                        self.assertEqual(
                            manager._queued_commit, (turn_id, "Latest question")
                        )
                    for delayed in client.commit_delays.values():
                        delayed.set()
                    self.assertEqual(
                        await asyncio.gather(*old_tasks),
                        [None] * manager.MAX_DISPATCHED_TURNS,
                    )
                    self.assertEqual((await latest).turn_id, 128)
                    await manager.wait_pending()
                    self.assertEqual(manager._unresolved_cancel_turns, set())
            finally:
                for delayed in client.commit_delays.values():
                    delayed.set()
                await manager.cleanup()

    async def test_held_http_bursts_bound_tasks_and_preserve_latest_aggregated_turn(
        self,
    ):
        tracker = TurnTracker("s1", 0)
        replies = []
        tasks_before = asyncio.all_tasks()
        async with ControllablePhoenixClient() as client:
            client.commit_events[1] = asyncio.Event()
            client.commit_delays[1] = asyncio.Event()
            client.cancel_events[1] = asyncio.Event()
            client.cancel_delays[1] = asyncio.Event()
            manager = TurnManager(tracker, client, on_reply=replies.append)
            peak = 0
            latest = None
            try:
                async with asyncio.timeout(3):
                    first = manager.commit_turn(1, "First question")
                    await client.commit_events[1].wait()
                    tracker.turn_id = 2
                    for turn_id in range(2, 514):
                        client.cancel_delays[turn_id] = client.cancel_delays[1]
                        for speech_event in (
                            event(FINAL, "Latest"),
                            event(FINAL, "question"),
                            event(END),
                        ):
                            manager.on_speech_event(speech_event)
                            transcript = tracker.handle(speech_event)
                            if transcript and transcript["final"]:
                                latest = manager.commit_turn(
                                    transcript["turn_id"], transcript["text"]
                                )
                        await asyncio.sleep(0)
                        peak = max(peak, len(manager._all_tasks))
                        self.assertLessEqual(len(asyncio.all_tasks() - tasks_before), 3)
                        self.assertEqual(
                            manager._queued_commit, (turn_id, "Latest question")
                        )
                    self.assertEqual(peak, 3)
                    self.assertEqual(manager._unresolved_cancel_turns, {1})
                    self.assertEqual(client.commit_calls, [(1, "First question")])
                    client.cancel_delays[1].set()
                    reply = await latest
                    self.assertEqual(reply.turn_id, 513)
                    self.assertEqual(
                        client.commit_calls,
                        [(1, "First question"), (513, "Latest question")],
                    )
                    client.commit_delays[1].set()
                    self.assertIsNone(await first)
                    await manager.wait_pending()
                    self.assertEqual([reply.turn_id for reply in replies], [513])
                    self.assertEqual(manager._unresolved_cancel_turns, set())
                    self.assertTrue(tracker.is_turn_stale(2))
                    self.assertLessEqual(len(tracker.cancelled_turns), 1)
            finally:
                client.cancel_delays[1].set()
                client.commit_delays[1].set()
                await manager.cleanup()

    async def test_interruption_history_is_bounded_and_old_work_stays_stale(self):
        tracker = TurnTracker("s1", 0)
        tracker.cancel(turn_id=10000)
        tracker.cancel(generation_id=10000)
        async with ControllablePhoenixClient() as client:
            manager = TurnManager(tracker, client)
            try:
                async with asyncio.timeout(3):
                    for turn_id in range(1, 257, 2):
                        client.commit_events[turn_id] = asyncio.Event()
                        client.commit_delays[turn_id] = asyncio.Event()
                        tracker.handle(event(FINAL, "Old question"))
                        old_final = tracker.handle(event(END))
                        self.assertEqual(old_final["turn_id"], turn_id)
                        old = manager.commit_turn(
                            old_final["turn_id"], old_final["text"]
                        )
                        await client.commit_events[turn_id].wait()
                        await manager.on_speech_event(event(INTERIM, "New question"))
                        tracker.handle(event(FINAL, "New question"))
                        new_final = tracker.handle(event(END))
                        await manager.commit_turn(
                            new_final["turn_id"], new_final["text"]
                        )
                        client.commit_delays[turn_id].set()
                        self.assertIsNone(await old)
                    self.assertLessEqual(len(tracker.cancelled_turns), 1)
                    self.assertLessEqual(len(tracker.cancelled_generations), 1)
                    self.assertTrue(tracker.is_turn_stale(1))
                    self.assertIsNone(
                        tracker.accept_reply(VoiceTurnReply(1, "committed", 1, "Late"))
                    )
                    calls = list(client.commit_calls)
                    self.assertIsNone(
                        await manager.commit_turn(1, "Old queued question")
                    )
                    self.assertEqual(client.commit_calls, calls)
                    await manager.cleanup()
                    # Reconnect keeps the same tracker and does not reuse old IDs.
                    self.assertEqual(tracker.turn_id, 257)
                    queue = asyncio.Queue()
                    queue.put_nowait(event(FINAL, "Reconnect question"))
                    queue.put_nowait(event(END))
                    queue.put_nowait(None)
                    await process_speech_stream(MockStream(queue), tracker, client)
                    self.assertEqual(tracker.last_accepted_turn_id, 257)
                    self.assertEqual(tracker.turn_id, 258)
                    self.assertTrue(tracker.is_turn_stale(10000))
                    self.assertIsNone(
                        tracker.accept_reply(
                            VoiceTurnReply(
                                10000, "committed", 10000, "Future cancelled"
                            )
                        )
                    )
            finally:
                await manager.cleanup()

    async def test_ambiguous_dispatch_survives_http_completion_until_scoped_fence(
        self,
    ):
        for exhausted in (False, True):
            for independent_active, teardown in (
                (False, False),
                (True, False),
                (False, True),
                (True, True),
            ):
                with self.subTest(
                    exhausted=exhausted,
                    independent_active=independent_active,
                    teardown=teardown,
                ):
                    active = None
                    highwater = 0
                    attempts = 0
                    cancelled = []
                    appends = []
                    release = asyncio.Event()
                    generations = []

                    async def generate(turn_id):
                        await release.wait()
                        if active == turn_id:
                            appends.append(turn_id)

                    async def handler(request):
                        nonlocal active, highwater, attempts
                        body = json.loads(request.content)
                        turn_id = body["turn_id"]
                        if request.url.path.endswith("/cancel"):
                            cancelled.append(turn_id)
                            if active != turn_id:
                                return httpx.Response(409, json={})
                            active = None
                            return httpx.Response(200, json={"status": "cancelled"})
                        attempts += 1
                        if turn_id > highwater:
                            highwater = turn_id
                            active = turn_id
                            generations.append(asyncio.create_task(generate(turn_id)))
                            raise httpx.ReadTimeout("private timeout detail")
                        if exhausted:
                            raise httpx.ReadTimeout("private retry detail")
                        return httpx.Response(
                            200, json={"turn_id": turn_id, "status": "duplicate"}
                        )

                    async with phoenix(handler) as client:
                        manager = TurnManager(TurnTracker("s1", 0), client)
                        try:
                            async with asyncio.timeout(1):
                                task = manager.commit_turn(1, "Question")
                                if exhausted:
                                    with self.assertRaises(VoiceFailure):
                                        await task
                                    with self.assertRaises(VoiceFailure):
                                        manager.check_errors()
                                else:
                                    self.assertIsNone(await task)
                                self.assertEqual(attempts, 2)
                                self.assertEqual(active, 1)
                                if independent_active:
                                    active = 3
                                if teardown:
                                    await manager.cleanup()
                                else:
                                    cancel = manager.on_speech_event(
                                        event(SpeechEventType.START_OF_SPEECH)
                                    )
                                    self.assertIsNotNone(cancel)
                                    await cancel
                                release.set()
                                await asyncio.gather(*generations)
                                self.assertEqual(cancelled, [1])
                                self.assertEqual(appends, [])
                                self.assertEqual(
                                    active, 3 if independent_active else None
                                )
                        finally:
                            release.set()
                            await manager.cleanup()
                            await asyncio.gather(*generations)

    async def _assert_safe_close_failure(self, primary=None):
        sentinel = "private closure sentinel"

        class FailingAudio(MockAudioStream):
            async def __anext__(self):
                await asyncio.Event().wait()

            async def aclose(self):
                raise RuntimeError(sentinel)

        queue = asyncio.Queue()
        stream = MockStream(queue)
        tasks_before = asyncio.all_tasks()

        def receive_reply(reply):
            raise primary

        async with ControllablePhoenixClient() as client:
            with self.assertLogs("voice-worker", level="WARNING") as logs:
                task = asyncio.create_task(
                    transcribe(
                        MockRoom(),
                        None,
                        {},
                        TurnTracker("s1", 0),
                        client,
                        stt=MockSTT(stream),
                        audio=FailingAudio(),
                        on_reply=(
                            receive_reply if isinstance(primary, VoiceFailure) else None
                        ),
                    )
                )
                async with asyncio.timeout(1):
                    if isinstance(primary, VoiceFailure):
                        queue.put_nowait(event(FINAL, "Question"))
                        queue.put_nowait(event(END))
                    elif isinstance(primary, asyncio.CancelledError):
                        await asyncio.sleep(0)
                        task.cancel()
                    else:
                        queue.put_nowait(None)
                    expected = (
                        asyncio.CancelledError
                        if isinstance(primary, asyncio.CancelledError)
                        else VoiceFailure
                    )
                    with self.assertRaises(expected) as caught:
                        await task
                self.assertTrue(stream.closed)
                self.assertNotIn(sentinel, str(caught.exception))
                self.assertNotIn(sentinel, " ".join(logs.output))
                if isinstance(primary, VoiceFailure):
                    self.assertIs(caught.exception, primary)
                elif primary is None:
                    self.assertEqual(caught.exception.kind, "malformed")
                self.assertEqual(asyncio.all_tasks() - tasks_before, set())

    async def test_audio_close_error_preserves_primary_auth_failure(self):
        await self._assert_safe_close_failure(VoiceFailure("auth"))

    async def test_audio_close_error_preserves_primary_cancellation(self):
        await self._assert_safe_close_failure(asyncio.CancelledError())

    async def test_normal_audio_close_error_is_typed_and_content_free(self):
        await self._assert_safe_close_failure()

    async def test_double_cancellation_joins_local_resource_closure(self):
        close_started = asyncio.Event()
        release_close = asyncio.Event()

        class HeldAudio(MockAudioStream):
            async def __anext__(self):
                await asyncio.Event().wait()

            async def aclose(self):
                close_started.set()
                await release_close.wait()
                self.closed = True

        audio = HeldAudio()
        stream = MockStream(asyncio.Queue())
        tasks_before = asyncio.all_tasks()
        async with ControllablePhoenixClient() as client:
            task = asyncio.create_task(
                transcribe(
                    MockRoom(),
                    None,
                    {},
                    TurnTracker("s1", 0),
                    client,
                    stt=MockSTT(stream),
                    audio=audio,
                )
            )
            try:
                async with asyncio.timeout(1):
                    await asyncio.sleep(0)
                    task.cancel()
                    await close_started.wait()
                    task.cancel()
                    await asyncio.sleep(0)
                    release_close.set()
                    with self.assertRaises(asyncio.CancelledError):
                        await task
                    self.assertTrue(audio.closed)
                    self.assertTrue(stream.closed)
                    self.assertEqual(asyncio.all_tasks() - tasks_before, set())
            finally:
                release_close.set()
                task.cancel()
                await asyncio.wait_for(asyncio.gather(task, return_exceptions=True), 1)

    async def test_invalid_server_receipts_preserve_older_cancel_ownership(self):
        cases = (
            [{"generation_id": value} for value in ("invalid", True, 0, -1, [], None)]
            + [{"turn_id": value} for value in (None, True, 0, -1, "2", 3)]
            + [{"status": "duplicate"}, {"reply_text": "  "}, {"reply_text": 7}]
        )
        for override in cases:
            with self.subTest(override=override):
                started = asyncio.Event()
                release = asyncio.Event()
                cancelled = []
                response = {
                    "turn_id": 2,
                    "status": "committed",
                    "generation_id": 2,
                    "reply_text": "Reply",
                }
                response.update(override)
                if response.get("turn_id") is None:
                    response.pop("turn_id")
                if response.get("generation_id") is None:
                    response.pop("generation_id")

                async def handler(request):
                    body = json.loads(request.content)
                    if request.url.path.endswith("/cancel"):
                        cancelled.append(body["turn_id"])
                        if len(cancelled) <= 2:
                            raise httpx.ReadTimeout("private transport detail")
                        return httpx.Response(200, json={"status": "cancelled"})
                    if body["turn_id"] == 1:
                        started.set()
                        await release.wait()
                        return httpx.Response(200, json={"status": "duplicate"})
                    return httpx.Response(201, json=response)

                async with phoenix(handler) as client:
                    manager = TurnManager(TurnTracker("s1", 0), client)
                    async with asyncio.timeout(1):
                        manager.commit_turn(1, "Old question")
                        await started.wait()
                        await manager.on_speech_event(event(INTERIM, "Next question"))
                        try:
                            await manager.commit_turn(2, "Next question")
                        except (VoiceFailure, TypeError):
                            pass
                        await manager.cleanup()
                        # Both dispatched identities remain ambiguous: invalid
                        # turn 2 metadata cannot release turn 1 OR turn 2 ownership.
                        self.assertEqual(cancelled, [1, 1, 1, 2])

    async def _assert_non_speech_preserves_pending_turn(self, held_commit=False):
        async with ControllablePhoenixClient() as client:
            tracker = TurnTracker("s1", last_turn_id=0)
            replies = []
            queue = asyncio.Queue()
            client.commit_events[1] = asyncio.Event()
            if held_commit:
                client.commit_delays[1] = asyncio.Event()
            task = asyncio.create_task(
                process_speech_stream(
                    MockStream(queue), tracker, client, on_reply=replies.append
                )
            )
            try:
                async with asyncio.timeout(1):
                    queue.put_nowait(event(FINAL, "First segment"))
                    queue.put_nowait(event(FINAL, "second segment"))
                    queue.put_nowait(event(END))
                    if held_commit:
                        await client.commit_events[1].wait()
                    # The queued case delivers these before the commit task first runs.
                    queue.put_nowait(event(SpeechEventType.RECOGNITION_USAGE))
                    queue.put_nowait(event(END))
                    queue.put_nowait(event(INTERIM, "  "))
                    queue.put_nowait(event(FINAL, "  "))
                    await asyncio.sleep(0)
                    self.assertFalse(tracker.is_turn_stale(1))
                    self.assertEqual(client.cancel_calls, [])
                    if held_commit:
                        client.commit_delays[1].set()
                    queue.put_nowait(None)
                    await task
                    self.assertEqual(
                        client.commit_calls, [(1, "First segment second segment")]
                    )
                    self.assertEqual([reply.turn_id for reply in replies], [1])
                    self.assertEqual(client.cancel_calls, [])
            finally:
                task.cancel()
                await asyncio.wait_for(asyncio.gather(task, return_exceptions=True), 1)

    async def test_usage_and_empty_events_before_commit_start_preserve_turn(self):
        await self._assert_non_speech_preserves_pending_turn()

    async def test_usage_and_empty_events_during_held_commit_preserve_turn(self):
        await self._assert_non_speech_preserves_pending_turn(held_commit=True)

    async def test_nonempty_final_without_start_still_supersedes_pending_turn(self):
        async with ControllablePhoenixClient() as client:
            tracker = TurnTracker("s1", 0)
            replies = []
            manager = TurnManager(tracker, client, on_reply=replies.append)
            try:
                async with asyncio.timeout(1):
                    old = manager.commit_turn(1, "First question")
                    await manager.on_speech_event(event(FINAL, "Next question"))
                    await old
                    self.assertTrue(tracker.is_turn_stale(1))
                    self.assertEqual(client.commit_calls, [])
                    self.assertEqual(replies, [])
                    self.assertEqual(
                        client.cancel_calls, [{"generation_id": None, "turn_id": 1}]
                    )
            finally:
                await asyncio.wait_for(manager.cleanup(), 1)

    async def test_newer_server_commit_reconciles_failed_historical_cancels(self):
        async with ControllablePhoenixClient() as client:
            manager = TurnManager(TurnTracker("s1", 0), client)
            try:
                async with asyncio.timeout(1):
                    for turn_id in range(1, 13, 2):
                        client.commit_events[turn_id] = asyncio.Event()
                        client.commit_delays[turn_id] = asyncio.Event()
                        client.cancel_errors[turn_id] = VoiceFailure("timeout")
                        old = manager.commit_turn(turn_id, "Old question")
                        await client.commit_events[turn_id].wait()
                        cancel = manager.on_speech_event(event(INTERIM, "New question"))
                        await cancel
                        newer = await manager.commit_turn(turn_id + 1, "New question")
                        self.assertEqual(newer.turn_id, turn_id + 1)
                        client.commit_delays[turn_id].set()
                        await old
                    calls_before_cleanup = list(client.cancel_calls)
                    await manager.cleanup()
                    self.assertEqual(client.cancel_calls, calls_before_cleanup)
            finally:
                await asyncio.wait_for(manager.cleanup(), 1)

    async def test_cleanup_has_one_budget_for_unconfirmed_cancellation_obligations(
        self,
    ):
        async with ControllablePhoenixClient() as client:
            manager = TurnManager(TurnTracker("s1", 0), client, cleanup_timeout=0.03)
            async with asyncio.timeout(1):
                # No newer server receipt: these obligations must NOT be reconciled.
                for turn_id in range(1, 13):
                    client.commit_events[turn_id] = asyncio.Event()
                    client.commit_delays[turn_id] = asyncio.Event()
                    client.cancel_errors[turn_id] = VoiceFailure("disconnected")
                    client.replies[turn_id] = VoiceTurnReply(turn_id, "duplicate")
                    old = manager.commit_turn(turn_id, "Question")
                    await client.commit_events[turn_id].wait()
                    await manager.on_speech_event(event(INTERIM, "Next question"))
                    client.commit_delays[turn_id].set()
                    await old
            calls_before = len(client.cancel_calls)
            hold = asyncio.Event()
            for turn_id in range(1, 13):
                client.cancel_delays[turn_id] = hold
            tasks_before = asyncio.all_tasks()
            try:
                try:
                    failure = await asyncio.wait_for(manager.cleanup(), 0.2)
                except TimeoutError:
                    self.fail("cleanup exceeded its aggregate cancellation budget")
                self.assertIsInstance(failure, VoiceFailure)
                self.assertEqual(failure.kind, "timeout")
                self.assertEqual(len(client.cancel_calls) - calls_before, 1)
                self.assertEqual(asyncio.all_tasks(), tasks_before)
            finally:
                hold.set()
                await asyncio.wait_for(manager.cleanup(), 1)

    async def test_healthy_newer_commits_keep_teardown_bounded_independent_of_history(
        self,
    ):
        for history_size in (1, 8):
            with self.subTest(history_size=history_size):
                async with ControllablePhoenixClient() as client:
                    queue = asyncio.Queue()
                    stream = MockStream(queue)
                    audio = MockAudioStream()
                    replies = []
                    reply_received = asyncio.Event()

                    def receive_reply(reply):
                        replies.append(reply.turn_id)
                        reply_received.set()

                    task = asyncio.create_task(
                        transcribe(
                            MockRoom(),
                            None,
                            {},
                            TurnTracker("s1", 0),
                            client,
                            stt=MockSTT(stream),
                            audio=audio,
                            on_reply=receive_reply,
                            cleanup_timeout=0.03,
                        )
                    )
                    try:
                        async with asyncio.timeout(2):
                            for turn_id in range(1, history_size * 2 + 1, 2):
                                client.commit_events[turn_id] = asyncio.Event()
                                client.commit_delays[turn_id] = asyncio.Event()
                                client.cancel_events[turn_id] = asyncio.Event()
                                client.cancel_errors[turn_id] = VoiceFailure("timeout")
                                queue.put_nowait(event(FINAL, "Old question"))
                                queue.put_nowait(event(END))
                                await client.commit_events[turn_id].wait()
                                queue.put_nowait(event(FINAL, "New question"))
                                queue.put_nowait(event(END))
                                await client.cancel_events[turn_id].wait()
                                await reply_received.wait()
                                reply_received.clear()
                                client.commit_delays[turn_id].set()
                            pending = history_size * 2 + 1
                            client.commit_events[pending] = asyncio.Event()
                            client.commit_delays[pending] = asyncio.Event()
                            client.cancel_events[pending] = asyncio.Event()
                            client.cancel_delays[pending] = asyncio.Event()
                            queue.put_nowait(event(FINAL, "Pending question"))
                            queue.put_nowait(event(END))
                            await client.commit_events[pending].wait()
                            calls_before = len(client.cancel_calls)
                            task.cancel()
                            await client.cancel_events[pending].wait()
                            self.assertTrue(audio.closed)
                            self.assertTrue(stream.closed)
                            self.assertFalse(task.done())
                            with self.assertRaises(asyncio.CancelledError):
                                await asyncio.wait_for(task, 0.2)
                            self.assertEqual(
                                client.cancel_calls[calls_before:],
                                [{"generation_id": None, "turn_id": pending}],
                            )
                            self.assertEqual(replies, list(range(2, pending, 2)))
                    finally:
                        task.cancel()
                        await asyncio.wait_for(
                            asyncio.gather(task, return_exceptions=True), 1
                        )

    async def test_transcribe_closes_local_resources_before_remote_cleanup_finishes(
        self,
    ):
        queue = asyncio.Queue()
        stream = MockStream(queue)
        pump_stopped = asyncio.Event()

        class HeldAudio(MockAudioStream):
            async def __anext__(self):
                try:
                    await asyncio.Event().wait()
                finally:
                    pump_stopped.set()

        audio = HeldAudio()
        cancel_started = asyncio.Event()
        release_cancel = asyncio.Event()
        commit_started = asyncio.Event()

        async def handler(request):
            if request.url.path.endswith("/cancel"):
                cancel_started.set()
                await release_cancel.wait()
                return httpx.Response(200, json={"status": "cancelled"})
            commit_started.set()
            await asyncio.Event().wait()

        async with phoenix(handler) as client:
            task = asyncio.create_task(
                transcribe(
                    MockRoom(),
                    None,
                    {},
                    TurnTracker("s1", 0),
                    client,
                    stt=MockSTT(stream),
                    audio=audio,
                )
            )
            try:
                async with asyncio.timeout(1):
                    queue.put_nowait(event(FINAL, "Question"))
                    queue.put_nowait(event(END))
                    await commit_started.wait()
                    task.cancel()
                    await cancel_started.wait()
                    self.assertTrue(audio.closed)
                    self.assertTrue(stream.closed)
                    self.assertTrue(pump_stopped.is_set())
                    self.assertFalse(task.done())
            finally:
                release_cancel.set()
                await asyncio.wait_for(asyncio.gather(task, return_exceptions=True), 1)

    async def _assert_cleanup_preserves_scoped_cancel(self, newer_active=False):
        active_turn = None
        commit_calls = []
        cancel_calls = []
        fenced_turns = []
        patient_appends = []
        replies = []
        generation_tasks = []
        generation_started = asyncio.Event()
        release_generation = asyncio.Event()
        cancel_started = asyncio.Event()
        hold_first_cancel = asyncio.Event()

        async def generate(turn_id):
            nonlocal active_turn
            await release_generation.wait()
            # Model the backend's generation fence, independently of local HTTP tasks.
            if active_turn != turn_id:
                return httpx.Response(409, json={})
            patient_appends.append(turn_id)
            active_turn = None
            return httpx.Response(
                201,
                json={
                    "turn_id": turn_id,
                    "status": "committed",
                    "generation_id": turn_id,
                    "reply_text": "Patient reply",
                },
            )

        async def handler(request):
            nonlocal active_turn
            body = json.loads(request.content)
            turn_id = body["turn_id"]
            if request.url.path.endswith("/cancel"):
                self.assertEqual(body, {"turn_id": turn_id})
                cancel_calls.append(turn_id)
                if len(cancel_calls) == 1:
                    cancel_started.set()
                    await hold_first_cancel.wait()
                # Match the immutable backend's scoped cancellation guard.
                if active_turn != turn_id:
                    return httpx.Response(409, json={})
                active_turn = None
                fenced_turns.append(turn_id)
                return httpx.Response(200, json={"status": "cancelled"})
            commit_calls.append(turn_id)
            active_turn = turn_id
            generation = asyncio.create_task(generate(turn_id))
            generation_tasks.append(generation)
            generation_started.set()
            return await asyncio.shield(generation)

        async with phoenix(handler) as client:
            manager = TurnManager(
                TurnTracker("s1", last_turn_id=0), client, on_reply=replies.append
            )
            try:
                async with asyncio.timeout(3):
                    commit1 = manager.commit_turn(1, "First question")
                    await generation_started.wait()
                    self.assertEqual(active_turn, 1)
                    cancel1 = manager.on_speech_event(event(INTERIM, "Next question"))
                    self.assertIsNotNone(cancel1)
                    await cancel_started.wait()
                    commit2 = manager.commit_turn(2, "Next question")
                    # Run the queued commit until it blocks on cancel1, before POST.
                    await asyncio.sleep(0)
                    self.assertEqual(commit_calls, [1])
                    self.assertFalse(commit2.done())
                    if newer_active:
                        # Another worker owns a newer turn, not this manager's queue.
                        active_turn = 3
                    await manager.cleanup()
                    self.assertTrue(commit1.cancelled())
                    self.assertTrue(cancel1.cancelled())
                    self.assertTrue(commit2.cancelled())
                    active_after_cleanup = active_turn
                    release_generation.set()
                    await asyncio.gather(*generation_tasks)
                    self.assertEqual(patient_appends, [])
                    self.assertEqual(replies, [])
                    self.assertEqual(active_after_cleanup, 3 if newer_active else None)
                    self.assertEqual(commit_calls, [1])
                    self.assertEqual(cancel_calls, [1, 1, 2])
                    self.assertEqual(fenced_turns, [] if newer_active else [1])
            finally:
                release_generation.set()
                hold_first_cancel.set()
                await asyncio.wait_for(manager.cleanup(), timeout=3)
                await asyncio.wait_for(
                    asyncio.gather(*generation_tasks, return_exceptions=True), timeout=3
                )

    async def test_cleanup_fences_older_turn_while_newer_commit_waits_for_cancel(self):
        await self._assert_cleanup_preserves_scoped_cancel()

    async def test_cleanup_does_not_cancel_independently_newer_active_turn(self):
        await self._assert_cleanup_preserves_scoped_cancel(newer_active=True)

    async def test_accepted_reply_is_delivered_to_private_consumer(self):
        client = ControllablePhoenixClient()
        tracker = TurnTracker("s1", last_turn_id=0)
        replies: list[VoiceTurnReply] = []
        queue: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()

        async def receive_reply(reply: VoiceTurnReply) -> None:
            replies.append(reply)

        stream_task = asyncio.create_task(
            process_speech_stream(
                MockStream(queue), tracker, client, on_reply=receive_reply
            )
        )
        queue.put_nowait(event(FINAL, "onde dói"))
        queue.put_nowait(event(END))
        queue.put_nowait(None)
        await stream_task

        self.assertEqual(len(replies), 1)
        self.assertEqual(replies[0].turn_id, 1)
        self.assertEqual(replies[0].reply_text, "Resposta clinica confidencial 1")

    async def test_delayed_commit_with_new_speech_event_and_cancellation_order(self):
        client = ControllablePhoenixClient()
        client.commit_delays[1] = asyncio.Event()
        client.commit_events[1] = asyncio.Event()
        client.commit_events[2] = asyncio.Event()
        client.cancel_delays[1] = asyncio.Event()
        client.cancel_events[1] = asyncio.Event()

        tracker = TurnTracker("s1", last_turn_id=0)
        published: list[dict] = []
        replies: list[VoiceTurnReply] = []
        queue: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()
        stream = MockStream(queue)

        stream_task = asyncio.create_task(
            process_speech_stream(
                stream,
                tracker,
                client,
                on_publish=lambda ev: published.append(ev),
                on_reply=lambda reply: replies.append(reply),
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
        idx_commit_2_start = next(
            i for i, log in enumerate(client.call_log) if log[:2] == ("commit_start", 2)
        )
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
        self.assertEqual([reply.turn_id for reply in replies], [2])

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
        replies: list[VoiceTurnReply] = []
        queue: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()
        stream = MockStream(queue)

        stream_task = asyncio.create_task(
            process_speech_stream(
                stream, tracker, client, on_reply=lambda reply: replies.append(reply)
            )
        )

        queue.put_nowait(event(FINAL, "repetida"))
        queue.put_nowait(event(END))
        queue.put_nowait(None)
        await stream_task

        # Duplicate reply was not accepted into tracker
        self.assertEqual(tracker.last_accepted_turn_id, 0)
        self.assertIsNone(tracker.active_generation_id)
        self.assertEqual(replies, [])

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

    # Issue #281: a streamed reply is announced as ended once Phoenix settles it.
    async def test_turn_end_callback_runs_only_after_a_settled_streamed_reply(self):
        client = ControllablePhoenixClient()
        client.streams[2] = ["Começou ontem.", "Ainda dói."]
        tracker = TurnTracker("s1", last_turn_id=0)
        queue: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()
        log: list[tuple] = []

        async def on_reply(reply: VoiceTurnReply) -> None:
            log.append(("reply", reply.turn_id, reply.index))

        async def on_turn_end(reply: VoiceTurnReply) -> None:
            log.append(("end", reply.turn_id, reply.generation_id))

        stream_task = asyncio.create_task(
            process_speech_stream(
                MockStream(queue),
                tracker,
                client,
                on_reply=on_reply,
                on_turn_end=on_turn_end,
            )
        )
        for text in ("não transmitida", "transmitida"):
            queue.put_nowait(event(FINAL, text))
            queue.put_nowait(event(END))
            await asyncio.sleep(0.01)
        queue.put_nowait(None)
        await stream_task

        self.assertEqual(
            log,
            [
                ("reply", 1, None),
                ("reply", 2, 0),
                ("reply", 2, 1),
                ("end", 2, 2),
            ],
        )

    async def test_reply_callback_failure_uses_stream_error_pipeline(self):
        client = ControllablePhoenixClient()
        tracker = TurnTracker("s1", last_turn_id=0)
        queue: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()

        def fail_on_reply(reply: VoiceTurnReply) -> None:
            raise RuntimeError("private consumer failed")

        with self.assertRaises(VoiceFailure) as ctx:
            stream_task = asyncio.create_task(
                process_speech_stream(
                    MockStream(queue), tracker, client, on_reply=fail_on_reply
                )
            )
            queue.put_nowait(event(FINAL, "pergunta"))
            queue.put_nowait(event(END))
            await stream_task

        self.assertEqual(ctx.exception.kind, "malformed")

    async def test_reply_callback_cancellation_cancels_stream(self):
        client = ControllablePhoenixClient()
        tracker = TurnTracker("s1", last_turn_id=0)
        queue: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()
        tasks_before_stream = asyncio.all_tasks()

        async def cancel_on_reply(reply: VoiceTurnReply) -> None:
            raise asyncio.CancelledError

        stream_task = asyncio.create_task(
            process_speech_stream(
                MockStream(queue), tracker, client, on_reply=cancel_on_reply
            )
        )
        queue.put_nowait(event(FINAL, "pergunta"))
        queue.put_nowait(event(END))

        with self.assertRaises(asyncio.CancelledError):
            await stream_task

        await asyncio.sleep(0)
        self.assertTrue(stream_task.cancelled())
        self.assertEqual(asyncio.all_tasks() - tasks_before_stream, set())

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
        replies: list[VoiceTurnReply] = []

        transcribe_task = asyncio.create_task(
            transcribe(
                room,
                learner=None,
                context={"language": "pt-BR", "keyterms": []},
                tracker=tracker,
                phoenix=client,
                stt=stt,
                audio=audio,
                on_reply=lambda reply: replies.append(reply),
            )
        )

        queue.put_nowait(event(INTERIM, "teste"))
        queue.put_nowait(event(FINAL, "teste de voz"))
        queue.put_nowait(event(END))
        queue.put_nowait(None)

        await transcribe_task

        self.assertEqual(tracker.last_accepted_turn_id, 1)
        self.assertEqual([reply.turn_id for reply in replies], [1])
        self.assertEqual(replies[0].reply_text, "Resposta clinica confidencial 1")
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

    async def test_barge_in_notifies_the_cancel_consumer_with_the_superseded_turn(self):
        client = ControllablePhoenixClient()
        client.commit_delays[1] = asyncio.Event()
        client.commit_events[1] = asyncio.Event()
        client.cancel_events[1] = asyncio.Event()
        tracker = TurnTracker("s1", last_turn_id=0)
        cancelled: list[int] = []
        queue: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()

        stream_task = asyncio.create_task(
            process_speech_stream(
                MockStream(queue), tracker, client, on_cancel=cancelled.append
            )
        )
        queue.put_nowait(event(FINAL, "primeira"))
        queue.put_nowait(event(END))
        await client.commit_events[1].wait()
        self.assertEqual(cancelled, [])

        queue.put_nowait(event(SpeechEventType.START_OF_SPEECH))
        await client.cancel_events[1].wait()
        self.assertEqual(cancelled, [1])

        client.commit_delays[1].set()
        queue.put_nowait(None)
        await stream_task

    async def _reply_after_the_learner_spoke_again(
        self, reply: VoiceTurnReply
    ) -> tuple[list[VoiceTurnReply], list[int]]:
        """Phoenix answers turn 1 only after the learner spoke over it (#193)."""
        client = ControllablePhoenixClient()
        client.replies[1] = reply
        client.commit_delays[1] = asyncio.Event()
        client.commit_events[1] = asyncio.Event()
        client.cancel_events[1] = asyncio.Event()
        tracker = TurnTracker("s1", last_turn_id=0)
        replies: list[VoiceTurnReply] = []
        cancelled: list[int] = []
        queue: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()

        stream_task = asyncio.create_task(
            process_speech_stream(
                MockStream(queue),
                tracker,
                client,
                on_reply=replies.append,
                on_cancel=cancelled.append,
            )
        )
        queue.put_nowait(event(FINAL, "solicito um hemograma"))
        queue.put_nowait(event(END))
        await client.commit_events[1].wait()
        queue.put_nowait(event(SpeechEventType.START_OF_SPEECH))
        await client.cancel_events[1].wait()
        self.assertTrue(tracker.is_turn_stale(1))

        client.commit_delays[1].set()
        queue.put_nowait(None)
        await asyncio.wait_for(stream_task, timeout=2)
        return replies, cancelled

    async def test_a_stale_turn_still_publishes_the_impresso_outcome_phoenix_recorded(
        self,
    ):
        # Issue #432: Phoenix decided the spoken exam request (#364) before the
        # learner spoke again; the decision is still shown.
        outcome = {
            "request_id": "voice-exam-1",
            "decision": "released",
            "newly_released": [
                {"id": "imp-1", "title": "Hemograma", "category": "laboratory"}
            ],
            "feedback_message": "Liberado",
        }
        receipt = VoiceTurnReply(
            turn_id=1, status="impresso_requested", impresso=outcome
        )

        replies, cancelled = await self._reply_after_the_learner_spoke_again(receipt)

        self.assertEqual(len(replies), 1)
        self.assertTrue(replies[0].is_impresso_receipt())
        self.assertEqual(replies[0].turn_id, 1)
        self.assertEqual(replies[0].impresso, outcome)
        self.assertEqual(cancelled, [1])

    async def test_a_stale_turn_still_drops_the_patient_reply(self):
        # The barge-in rules of #193 hold for every patient reply (#432).
        for reply in (
            VoiceTurnReply(
                turn_id=1, status="committed", generation_id=1, reply_text="Dói aqui."
            ),
            VoiceTurnReply(turn_id=1, status="kept", generation_id=1),
        ):
            with self.subTest(status=reply.status):
                replies, cancelled = await self._reply_after_the_learner_spoke_again(
                    reply
                )

                self.assertEqual(replies, [])
                self.assertEqual(cancelled, [1])

    async def test_stale_generation_result_notifies_the_cancel_consumer(self):
        client = ControllablePhoenixClient()
        client.commit_errors[1] = VoiceFailure("stale_generation")
        # A superseded reply the tracker refuses is a stale result as well.
        client.replies[2] = VoiceTurnReply(
            turn_id=2, status="committed", generation_id=2, reply_text="texto"
        )
        tracker = TurnTracker("s1", last_turn_id=0)
        tracker.cancel(generation_id=2)
        cancelled: list[int] = []
        replies: list[VoiceTurnReply] = []
        queue: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()

        stream_task = asyncio.create_task(
            process_speech_stream(
                MockStream(queue),
                tracker,
                client,
                on_reply=replies.append,
                on_cancel=cancelled.append,
            )
        )
        for text in ("primeira", "segunda"):
            queue.put_nowait(event(FINAL, text))
            queue.put_nowait(event(END))
            await asyncio.sleep(0.01)
        queue.put_nowait(None)
        await stream_task

        self.assertEqual(cancelled, [1, 2])
        self.assertEqual(replies, [])

    async def test_station_time_elapsed_propagates_instead_of_notifying_a_stale_turn(
        self,
    ):
        client = ControllablePhoenixClient()
        client.commit_errors[1] = VoiceFailure("station_time_elapsed")
        tracker = TurnTracker("s1", last_turn_id=0)
        cancelled: list[int] = []
        replies: list[VoiceTurnReply] = []
        queue: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()

        stream_task = asyncio.create_task(
            process_speech_stream(
                MockStream(queue),
                tracker,
                client,
                on_reply=replies.append,
                on_cancel=cancelled.append,
            )
        )
        queue.put_nowait(event(FINAL, "primeira"))
        queue.put_nowait(event(END))

        with self.assertRaises(VoiceFailure) as ctx:
            await asyncio.wait_for(stream_task, timeout=2)

        self.assertEqual(ctx.exception.kind, "station_time_elapsed")
        self.assertEqual(client.commit_calls, [(1, "primeira")])
        self.assertEqual(cancelled, [])
        self.assertEqual(replies, [])

    async def test_accepted_reply_does_not_notify_the_cancel_consumer(self):
        client = ControllablePhoenixClient()
        tracker = TurnTracker("s1", last_turn_id=0)
        cancelled: list[int] = []
        queue: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()

        stream_task = asyncio.create_task(
            process_speech_stream(
                MockStream(queue), tracker, client, on_cancel=cancelled.append
            )
        )
        queue.put_nowait(event(FINAL, "primeira"))
        queue.put_nowait(event(END))
        queue.put_nowait(None)
        await stream_task

        self.assertEqual(tracker.last_accepted_turn_id, 1)
        self.assertEqual(cancelled, [])

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
