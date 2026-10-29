# pyright: reportMissingImports=false
import asyncio
import json
import os
import unittest
from types import SimpleNamespace
from typing import ClassVar
from unittest.mock import patch

from livekit import rtc
from livekit.agents import APIConnectionError
from livekit.agents.stt import SpeechEvent

import worker
from speech import SpeechPlayer
from test_speech import FakeSource, FakeTTS, chunk, settle
from test_transcripts import (
    END,
    FINAL,
    INTERIM,
    ControllablePhoenixClient,
    MockAudioStream,
    MockRoom,
    MockStream,
    MockSTT,
    event,
)
from transcripts import TurnTracker, VoiceFailure, VoiceTurnReply
from worker import (
    TYPED_REPLY_TOPIC,
    PatientVoice,
    build_tts,
    build_voice_tts,
    on_typed_reply,
    phoenix_turn_settings,
    transcribe,
)

REPLY_TEXT = "Resposta clinica confidencial"
PROVIDER_SECRET = "sk-provider-secret"


class VoiceRoom(MockRoom):
    """MockRoom whose worker participant can also publish the patient track.

    `timeline` records data events and audio frames in the order the room saw them.
    """

    def __init__(self):
        super().__init__()
        self.timeline: list[tuple[str, object]] = []
        self.published_tracks: list[object] = []
        self.unpublished: list[str] = []
        self.data_error: Exception | None = None
        self.text_error: Exception | None = None
        participant = self.local_participant
        publish_data = participant.publish_data

        async def recording_publish_data(data, topic="transcript", reliable=True):
            if self.data_error is not None and "failure" in json.loads(data):
                raise self.data_error
            if (
                self.text_error is not None
                and json.loads(data).get("role") == "patient"
            ):
                raise self.text_error
            await publish_data(data, topic=topic, reliable=reliable)
            self.timeline.append(("data", json.loads(data)))

        async def publish_track(track, options=None):
            self.published_tracks.append(track)
            return SimpleNamespace(sid=f"TR_{len(self.published_tracks)}")

        async def unpublish_track(track_sid):
            self.unpublished.append(track_sid)

        participant.publish_data = recording_publish_data
        participant.publish_track = publish_track
        participant.unpublish_track = unpublish_track

    def patient_events(self) -> list[dict]:
        return [
            payload
            for kind, payload in self.timeline
            if kind == "data" and "final" not in payload
        ]


class TimelineSource(FakeSource):
    timeline: list[tuple[str, object]]

    async def capture_frame(self, frame) -> None:
        await super().capture_frame(frame)
        self.timeline.append(("frame", frame))


class PatientVoiceFlowTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.client = ControllablePhoenixClient()
        self.tracker = TurnTracker("s1", last_turn_id=0)
        self.room = VoiceRoom()
        self.tts = FakeTTS()
        self.sources: list[TimelineSource] = []
        self.queue: asyncio.Queue[SpeechEvent | None] = asyncio.Queue()
        self.stream = MockStream(self.queue)
        self.voice = PatientVoice(
            self.room,
            SpeechPlayer(
                self.room,
                self.tracker,
                self.tts,
                source_factory=self._source,
                track_factory=lambda source: SimpleNamespace(source=source),
            ),
        )

    def _source(self, sample_rate: int, num_channels: int) -> TimelineSource:
        source = TimelineSource(sample_rate, num_channels)
        source.timeline = self.room.timeline
        self.sources.append(source)
        return source

    def connect(self, voice="default", learner=None) -> asyncio.Task:
        return asyncio.create_task(
            transcribe(
                self.room,
                learner=learner,
                context={"language": "pt-BR", "keyterms": []},
                tracker=self.tracker,
                phoenix=self.client,
                stt=MockSTT(self.stream),
                audio=MockAudioStream(),
                voice=self.voice if voice == "default" else voice,
            )
        )

    async def say(self, text: str) -> None:
        self.queue.put_nowait(event(FINAL, text))
        self.queue.put_nowait(event(END))
        await asyncio.sleep(0.01)

    def learner(self, muted: bool = False) -> SimpleNamespace:
        microphone = SimpleNamespace(
            source=rtc.TrackSource.SOURCE_MICROPHONE, muted=muted
        )
        return SimpleNamespace(
            identity="learner-s1", track_publications={"TR_mic": microphone}
        )

    def set_microphone(self, learner, muted: bool) -> None:
        microphone = learner.track_publications["TR_mic"]
        microphone.muted = muted
        handler = self.room.handlers["track_muted" if muted else "track_unmuted"]
        handler(learner, microphone)

    async def disconnect(self, task: asyncio.Task) -> None:
        self.queue.put_nowait(None)
        await task

    async def test_approved_text_is_published_before_the_first_audio_frame(self):
        task = self.connect()
        await self.say("onde dói")
        self.tts.streams[0].queue.put_nowait(chunk("a1"))
        await settle()

        self.assertEqual(self.tts.texts, [f"{REPLY_TEXT} 1"])
        patient = [
            entry
            for entry in self.room.timeline
            if entry[0] == "frame" or "final" not in entry[1]
        ]
        self.assertEqual(
            patient,
            [
                (
                    "data",
                    {
                        "session_id": "s1",
                        "turn_id": 1,
                        "generation_id": 1,
                        "role": "patient",
                        "speaker": "patient",
                        "text": f"{REPLY_TEXT} 1",
                    },
                ),
                ("frame", "a1"),
            ],
        )
        for _data, topic, reliable in self.room.local_participant.published_data:
            self.assertEqual(topic, "transcript")
            self.assertTrue(reliable)

        await self.disconnect(task)

    # Issue #271: Phoenix streams the verified sentences of a reply.
    # Issue #341: every spoken reply names its speaker; Phoenix sends one only
    # for a station with a companion, and a reply without one is the patient's.
    async def test_each_reply_event_names_its_speaker(self):
        companion = VoiceTurnReply(1, "committed", 1, "Começou ontem.", index=0)
        companion.speaker = "companion"
        assert self.tracker.accept_sentence(companion) is companion
        await self.voice.on_reply(companion)
        unlabelled = VoiceTurnReply(1, "committed", 1, "Ainda dói.", index=1)
        assert self.tracker.accept_sentence(unlabelled) is unlabelled
        await self.voice.on_reply(unlabelled)
        await settle()

        self.assertEqual(
            [(e["speaker"], e["text"]) for e in self.room.patient_events()],
            [("companion", "Começou ontem."), ("patient", "Ainda dói.")],
        )
        await self.voice.stop()

    async def test_first_streamed_sentence_is_spoken_while_the_reply_still_streams(
        self,
    ):
        more = asyncio.Event()
        self.client.streams[1] = ["Começou ontem.", more, "Ainda dói."]
        task = self.connect()
        await self.say("quando")
        await settle()

        # The first sentence is being synthesized; Phoenix has not answered yet.
        self.assertEqual(self.tts.texts, ["Começou ontem."])
        self.assertNotIn("commit_end", [entry[0] for entry in self.client.call_log])
        self.tts.streams[0].queue.put_nowait(chunk("s1"))
        await settle()

        more.set()
        await asyncio.sleep(0.01)
        # The next sentence waits for the one being spoken.
        self.assertEqual(self.tts.texts, ["Começou ontem."])
        self.tts.streams[0].queue.put_nowait(None)
        await asyncio.sleep(0.01)
        self.assertEqual(self.tts.texts, ["Começou ontem.", "Ainda dói."])
        self.tts.streams[1].queue.put_nowait(chunk("s2"))
        self.tts.streams[1].queue.put_nowait(None)
        await asyncio.sleep(0.01)

        self.assertEqual(self.sources[0].frames, ["s1", "s2"])
        self.assertEqual(
            [
                (e["turn_id"], e["segment"], e["text"])
                for e in self.room.patient_events()
                if "segment" in e
            ],
            [(1, 0, "Começou ontem."), (1, 1, "Ainda dói.")],
        )
        # Each sentence's text event precedes its audio.
        timeline = self.room.timeline
        first_text = timeline.index(("data", self.room.patient_events()[0]))
        self.assertLess(first_text, timeline.index(("frame", "s1")))
        # The settled turn is accepted once and never spoken again as a whole.
        self.assertEqual(self.tracker.last_accepted_turn_id, 1)
        await self.disconnect(task)
        self.assertEqual(len(self.tts.texts), 2)

    # Issue #281: the web reconciles a streamed reply only once its turn has ended.
    def completions(self) -> list[dict]:
        return [e for e in self.room.patient_events() if e.get("status") == "complete"]

    async def test_a_settled_streamed_reply_ends_with_a_content_free_end_event(self):
        self.client.streams[1] = ["Começou ontem.", "Ainda dói.", "Muito."]
        task = self.connect()
        await self.say("quando")
        await settle()

        self.assertEqual(
            self.completions(),
            [
                {
                    "session_id": "s1",
                    "turn_id": 1,
                    "generation_id": 1,
                    "role": "patient",
                    "status": "complete",
                }
            ],
        )
        # It follows every sentence of the reply.
        events = self.room.patient_events()
        self.assertEqual(events[-1], self.completions()[0])
        self.assertEqual([e.get("segment") for e in events[:-1]], [0, 1, 2])
        await self.disconnect(task)

    async def test_a_reply_that_was_not_streamed_publishes_no_end_event(self):
        task = self.connect()
        await self.say("onde dói")
        await settle()
        self.assertEqual(len(self.room.patient_events()), 1)
        self.assertEqual(self.completions(), [])
        await self.disconnect(task)

    async def test_a_reply_cut_by_barge_in_publishes_no_end_event(self):
        more = asyncio.Event()
        self.client.streams[1] = ["Começou ontem.", more, "Ainda dói."]
        task = self.connect()
        await self.say("quando")
        await settle()
        self.queue.put_nowait(event(INTERIM, "espera"))
        await asyncio.sleep(0.01)
        more.set()
        await asyncio.sleep(0.01)
        await self.disconnect(task)
        self.assertEqual(self.completions(), [])

    async def test_an_end_event_the_room_rejects_is_logged_without_content(self):
        self.client.streams[1] = ["Começou ontem."]
        task = self.connect()
        await self.say("quando")
        await settle()
        with self.assertLogs("voice-worker", level="WARNING") as logs:
            self.room.text_error = RuntimeError(PROVIDER_SECRET)
            await self.voice.on_turn_end(self.client.replies[1])
            self.room.text_error = None
        self.assertFalse(task.done())
        await self.disconnect(task)
        output = "\n".join(logs.output)
        self.assertIn("turn end not published for session s1 turn 1", output)
        self.assertNotIn(PROVIDER_SECRET, output)
        self.assertNotIn("Começou", output)
        # Not a failure event: the web keeps the streamed sentences it has.
        self.assertEqual([e for e in self.room.patient_events() if "failure" in e], [])

    async def test_barge_in_mid_stream_stops_the_reply_and_its_later_sentences(self):
        more = asyncio.Event()
        self.client.streams[1] = ["Começou ontem.", more, "Ainda dói."]
        task = self.connect()
        await self.say("quando")
        await settle()
        first = self.tts.streams[0]
        first.queue.put_nowait(chunk("s1"))
        await settle()

        self.queue.put_nowait(event(INTERIM, "espera"))
        await asyncio.sleep(0.01)

        self.assertEqual(first.closed, 1)
        self.assertIn({"generation_id": None, "turn_id": 1}, self.client.cancel_calls)
        more.set()
        await asyncio.sleep(0.01)
        self.assertEqual(self.tts.texts, ["Começou ontem."])
        self.assertEqual(self.sources[0].frames, ["s1"])
        await self.disconnect(task)

    async def test_first_audio_latency_is_logged_without_content(self):
        self.client.streams[1] = ["Começou ontem.", "Ainda dói."]
        with self.assertLogs("voice-worker", level="INFO") as logs:
            task = self.connect()
            await self.say("quando")
            await settle()
            self.tts.streams[0].queue.put_nowait(chunk("s1"))
            self.tts.streams[0].queue.put_nowait(None)
            await asyncio.sleep(0.01)
            self.tts.streams[1].queue.put_nowait(chunk("s2"))
            self.tts.streams[1].queue.put_nowait(None)
            await asyncio.sleep(0.01)
            await self.disconnect(task)

        output = "\n".join(logs.output)
        first_audio = [line for line in logs.output if "first patient audio" in line]
        self.assertEqual(len(first_audio), 1)
        self.assertRegex(first_audio[0], r"session s1 turn 1 generation 1 after \d+ ms")
        self.assertNotIn("Começou", output)
        self.assertNotIn("Ainda", output)
        self.assertNotIn("quando", output)

    async def test_barge_in_on_the_pending_turn_cancels_it_in_phoenix(self):
        self.client.commit_delays[2] = asyncio.Event()
        task = self.connect()
        await self.say("primeira")
        old_stream = self.tts.streams[0]
        old_stream.queue.put_nowait(chunk("a1"))
        await settle()

        await self.say("segunda")  # held in Phoenix: turn 2 is pending
        # Speaking over the reply of turn 1 already stopped it (#193).
        self.assertEqual(old_stream.closed, 1)
        self.queue.put_nowait(event(INTERIM, "terceira"))
        await asyncio.sleep(0.01)

        self.assertIn({"generation_id": None, "turn_id": 2}, self.client.cancel_calls)
        self.assertEqual(old_stream.closed, 1)
        self.assertEqual(self.sources[0].cleared, 1)
        old_stream.queue.put_nowait(chunk("late"))
        await settle()
        self.assertEqual(self.sources[0].frames, ["a1"])
        self.assertEqual(self.voice.player.speaking, None)

        self.client.commit_delays[2].set()
        await self.disconnect(task)
        self.assertEqual(len(self.tts.texts), 1)

    async def test_a_reply_phoenix_finds_stale_stops_its_playback(self):
        # Nobody speaks over it: only the cancel wiring can stop this playback.
        self.client.streams[1] = [
            "Começou ontem.",
            asyncio.Event(),
            "Ainda dói.",
        ]
        stale = self.client.streams[1][1]
        task = self.connect()
        await self.say("quando")
        await settle()
        stream = self.tts.streams[0]
        stream.queue.put_nowait(chunk("s1"))
        await settle()

        self.client.streams[1][2] = VoiceFailure("stale_generation")
        stale.set()
        await asyncio.sleep(0.01)

        self.assertEqual(stream.closed, 1)
        self.assertEqual(self.sources[0].cleared, 1)
        stream.queue.put_nowait(chunk("late"))
        await settle()
        self.assertEqual(self.sources[0].frames, ["s1"])
        self.assertEqual(self.voice.player.speaking, None)
        await self.disconnect(task)

    # Issue #193: speaking over the patient stops it, even after Phoenix settled the turn.
    async def test_barge_in_over_a_settled_reply_stops_its_playback(self):
        task = self.connect()
        await self.say("primeira")
        stream = self.tts.streams[0]
        stream.queue.put_nowait(chunk("a1"))
        await settle()
        # Settled, still speaking.
        self.assertEqual(self.tracker.last_accepted_turn_id, 1)

        self.queue.put_nowait(event(INTERIM, "espera"))
        await asyncio.sleep(0.01)

        self.assertEqual(stream.closed, 1)
        self.assertEqual(self.sources[0].cleared, 1)
        stream.queue.put_nowait(chunk("late"))
        await settle()
        self.assertEqual(self.sources[0].frames, ["a1"])
        self.assertEqual(self.voice.player.speaking, None)
        # Phoenix stored the reply: nothing is cancelled there.
        self.assertEqual(self.client.cancel_calls, [])
        await self.disconnect(task)

    # Issue #419: the Unreal client holds its microphone open only while the
    # learner holds the talk key; the worker hears the mutes as push-to-talk.
    async def test_muting_the_held_microphone_commits_the_turn_without_end_of_speech(
        self,
    ):
        learner = self.learner()
        with patch("push_to_talk.RELEASE_QUIET_S", 0.01):
            task = self.connect(learner=learner)
            await settle()
            self.set_microphone(learner, muted=True)
            self.set_microphone(learner, muted=False)
            await self.say("onde dói")

            self.assertEqual(self.client.commit_calls, [])

            self.set_microphone(learner, muted=True)
            await asyncio.sleep(0.05)

        self.assertEqual(self.client.commit_calls, [(1, "onde dói")])
        self.assertEqual(self.stream.flushes, 1)
        await self.disconnect(task)

    async def test_unmuting_the_microphone_stops_the_patient_at_once(self):
        learner = self.learner()
        task = self.connect(learner=learner)
        await self.say("primeira")
        stream = self.tts.streams[0]
        stream.queue.put_nowait(chunk("a1"))
        await settle()
        self.set_microphone(learner, muted=True)

        self.set_microphone(learner, muted=False)
        await asyncio.sleep(0.01)

        self.assertEqual(stream.closed, 1)
        self.assertEqual(self.sources[0].cleared, 1)
        await self.disconnect(task)

    async def test_a_microphone_muted_before_the_worker_joined_is_push_to_talk(self):
        learner = self.learner(muted=True)
        task = self.connect(learner=learner)
        await self.say("onde dói")

        self.assertEqual(self.client.commit_calls, [])
        await self.disconnect(task)

    async def test_a_microphone_published_muted_is_push_to_talk(self):
        learner = self.learner()
        task = self.connect(learner=learner)
        await settle()
        microphone = learner.track_publications["TR_mic"]
        microphone.muted = True
        self.room.handlers["track_published"](microphone, learner)
        await self.say("onde dói")

        self.assertEqual(self.client.commit_calls, [])
        await self.disconnect(task)

    async def test_only_the_connected_learner_microphone_mutes_count(self):
        learner = self.learner()
        task = self.connect(learner=learner)
        await settle()
        someone_else = SimpleNamespace(identity="learner-s2", track_publications={})
        self.room.handlers["track_muted"](
            someone_else, learner.track_publications["TR_mic"]
        )
        camera = SimpleNamespace(source=rtc.TrackSource.SOURCE_CAMERA, muted=True)
        self.room.handlers["track_muted"](learner, camera)
        await self.say("onde dói")

        self.assertEqual(self.client.commit_calls, [(1, "onde dói")])
        await self.disconnect(task)
        self.assertNotIn("track_muted", self.room.handlers)
        self.assertNotIn("track_unmuted", self.room.handlers)
        self.assertNotIn("track_published", self.room.handlers)

    async def test_newer_accepted_turn_supersedes_playback(self):
        task = self.connect()
        await self.say("primeira")
        old_stream = self.tts.streams[0]
        old_stream.queue.put_nowait(chunk("old-1"))
        await settle()

        await self.say("segunda")
        old_stream.queue.put_nowait(chunk("old-late"))
        self.tts.streams[1].queue.put_nowait(chunk("new-1"))
        await settle()

        self.assertEqual(old_stream.closed, 1)
        self.assertEqual(self.sources[0].frames, ["old-1", "new-1"])
        self.assertEqual(
            [(e["turn_id"], e["generation_id"]) for e in self.room.patient_events()],
            [(1, 1), (2, 2)],
        )
        text_2 = self.room.timeline.index(("data", self.room.patient_events()[1]))
        self.assertLess(text_2, self.room.timeline.index(("frame", "new-1")))

        await self.disconnect(task)

    async def test_learner_disconnect_cancels_playback_and_keeps_the_track(self):
        task = self.connect()
        await self.say("primeira")
        stream = self.tts.streams[0]
        stream.queue.put_nowait(chunk("a1"))
        await settle()

        await self.disconnect(task)

        self.assertEqual(stream.closed, 1)
        self.assertEqual(self.sources[0].cleared, 1)
        self.assertIsNone(self.voice.player.speaking)
        stream.queue.put_nowait(chunk("late"))
        await settle()
        self.assertEqual(self.sources[0].frames, ["a1"])
        # The player outlives one learner connection: the job still owns the track.
        self.assertEqual(self.room.unpublished, [])
        self.assertEqual(self.tts.closed, 0)

    async def test_reconnected_learner_reuses_the_published_track(self):
        await self.disconnect(self.connect())
        self.queue = asyncio.Queue()
        self.stream = MockStream(self.queue)
        task = self.connect()
        await self.say("primeira")
        self.tts.streams[0].queue.put_nowait(chunk("a1"))
        await settle()

        self.assertEqual(self.sources[0].frames, ["a1"])
        self.assertEqual(len(self.room.published_tracks), 1)
        await self.disconnect(task)

    async def test_job_end_releases_speech_resources_once(self):
        await self.voice.start()
        task = self.connect()
        await self.say("primeira")
        await self.disconnect(task)

        await self.voice.aclose()
        await self.voice.aclose()

        self.assertEqual(self.room.unpublished, ["TR_1"])
        self.assertEqual(self.sources[0].closed, 1)
        self.assertEqual(self.tts.closed, 1)

    async def test_synthesis_failure_publishes_failure_event_and_job_continues(self):
        self.tts.synthesize_error = APIConnectionError(
            f"{PROVIDER_SECRET} {REPLY_TEXT}"
        )
        with self.assertLogs("voice-worker", level="DEBUG") as logs:
            task = self.connect()
            await self.say("primeira")

            self.assertEqual(
                self.room.patient_events(),
                [
                    {
                        "session_id": "s1",
                        "turn_id": 1,
                        "generation_id": 1,
                        "role": "patient",
                        "speaker": "patient",
                        "text": f"{REPLY_TEXT} 1",
                    },
                    {
                        "session_id": "s1",
                        "turn_id": 1,
                        "generation_id": 1,
                        "failure": "synthesis_failed",
                    },
                ],
            )
            self.assertFalse(task.done())

            # The same job speaks the next turn.
            self.tts.synthesize_error = None
            await self.say("segunda")
            self.tts.streams[0].queue.put_nowait(chunk("b1"))
            await settle()
            self.assertEqual(self.sources[0].frames, ["b1"])
            await self.disconnect(task)

        output = "\n".join(logs.output)
        self.assertIn("synthesis_failed", output)
        self.assertNotIn(REPLY_TEXT, output)
        self.assertNotIn(PROVIDER_SECRET, output)
        for payload in self.room.patient_events():
            self.assertNotIn("error", payload)
            self.assertNotIn(PROVIDER_SECRET, json.dumps(payload))

    async def test_failure_event_that_cannot_be_published_does_not_stop_the_job(self):
        self.tts.synthesize_error = APIConnectionError("down")
        self.room.data_error = RuntimeError(PROVIDER_SECRET)
        with self.assertLogs("voice-worker", level="WARNING") as logs:
            task = self.connect()
            await self.say("primeira")
            self.assertFalse(task.done())
            await self.disconnect(task)

        self.assertEqual(len(self.room.patient_events()), 1)
        self.assertNotIn(PROVIDER_SECRET, "\n".join(logs.output))
        self.assertNotIn(REPLY_TEXT, "\n".join(logs.output))

    async def test_text_event_that_cannot_be_published_still_speaks_and_job_continues(
        self,
    ):
        self.room.text_error = RuntimeError(PROVIDER_SECRET)
        with self.assertLogs("voice-worker", level="WARNING") as logs:
            task = self.connect()
            await self.say("primeira")
            self.tts.streams[0].queue.put_nowait(chunk("a1"))
            await settle()
            self.assertFalse(task.done())

            self.room.text_error = None
            await self.say("segunda")
            self.assertFalse(task.done())
            await self.disconnect(task)

        self.assertEqual(self.tts.texts, [f"{REPLY_TEXT} 1", f"{REPLY_TEXT} 2"])
        self.assertIn(("frame", "a1"), self.room.timeline)
        self.assertEqual(
            self.room.patient_events(),
            [
                {
                    "session_id": "s1",
                    "turn_id": 1,
                    "generation_id": 1,
                    "failure": "text_delivery_failed",
                },
                {
                    "session_id": "s1",
                    "turn_id": 2,
                    "generation_id": 2,
                    "role": "patient",
                    "speaker": "patient",
                    "text": f"{REPLY_TEXT} 2",
                },
            ],
        )
        output = "\n".join(logs.output)
        self.assertIn("text_delivery_failed", output)
        self.assertNotIn(REPLY_TEXT, output)
        self.assertNotIn(PROVIDER_SECRET, output)

    async def test_room_that_rejects_every_event_does_not_stop_the_job(self):
        self.room.text_error = RuntimeError(PROVIDER_SECRET)
        self.room.data_error = RuntimeError(PROVIDER_SECRET)
        with self.assertLogs("voice-worker", level="WARNING") as logs:
            task = self.connect()
            await self.say("primeira")
            self.assertFalse(task.done())
            await self.disconnect(task)

        self.assertEqual(self.room.patient_events(), [])
        self.assertEqual(self.tts.texts, [f"{REPLY_TEXT} 1"])
        self.assertNotIn(PROVIDER_SECRET, "\n".join(logs.output))
        self.assertNotIn(REPLY_TEXT, "\n".join(logs.output))

    async def test_unavailable_provider_falls_back_to_text(self):
        with self.assertLogs("voice-worker", level="WARNING") as logs:
            task = self.connect(voice=PatientVoice(self.room, None))
            await self.say("primeira")
            await self.disconnect(task)

        self.assertEqual(
            [sorted(payload) for payload in self.room.patient_events()],
            [
                ["generation_id", "role", "session_id", "speaker", "text", "turn_id"],
                ["failure", "generation_id", "session_id", "turn_id"],
            ],
        )
        self.assertNotIn(REPLY_TEXT, "\n".join(logs.output))

    async def test_kept_turn_publishes_an_examiner_acknowledgement_and_speaks_nothing(
        self,
    ):
        # Issue #269: a refused reply kept the learner turn. It is an examiner
        # acknowledgement on the data channel, never a failure or patient speech.
        self.client.replies[1] = VoiceTurnReply(
            turn_id=1, status="kept", generation_id=1
        )
        task = self.connect()
        with self.assertNoLogs("voice-worker", level="WARNING"):
            await self.say("abdome flácido")
            await self.say("onde dói")
            self.tts.streams[0].queue.put_nowait(chunk("a2"))
            await settle()
            await self.disconnect(task)

        self.assertEqual(
            self.room.patient_events()[0],
            {
                "session_id": "s1",
                "turn_id": 1,
                "generation_id": 1,
                "role": "examiner",
                "status": "kept",
            },
        )
        self.assertEqual(self.room.patient_events()[1]["role"], "patient")
        self.assertEqual(self.tts.texts, [f"{REPLY_TEXT} 2"])
        # The kept receipt settles the turn: cleanup has nothing to fence.
        self.assertEqual(self.client.cancel_calls, [])

    async def test_examiner_addressed_turn_publishes_an_acknowledgement_and_speaks_nothing(
        self,
    ):
        # Issue #274: Phoenix kept a turn addressed to the examiner before any
        # generation. The examiner acknowledges it; nothing is spoken.
        self.client.replies[1] = VoiceTurnReply(
            turn_id=1, status="kept", generation_id=1, addressee="examiner"
        )
        task = self.connect()
        with self.assertNoLogs("voice-worker", level="WARNING"):
            await self.say("blumberg positivo")
            await settle()
            await self.disconnect(task)

        self.assertEqual(
            self.room.patient_events()[0],
            {
                "session_id": "s1",
                "turn_id": 1,
                "generation_id": 1,
                "role": "examiner",
                "status": "acknowledged",
            },
        )
        self.assertEqual(self.tts.texts, [])
        self.assertEqual(self.client.cancel_calls, [])

    async def test_spoken_exam_request_publishes_its_outcome_and_speaks_nothing(self):
        # Issue #364: in exam mode Phoenix routed the utterance to the impresso
        # request. The outcome goes to the learner's screen; nothing is spoken.
        outcome = {
            "request_id": "voice-exam-1",
            "decision": "released",
            "newly_released": [
                {"id": "lab", "title": "Laboratório", "category": "laboratory"}
            ],
            "feedback_message": "Impresso liberado: Laboratório",
        }
        self.client.replies[1] = VoiceTurnReply(
            turn_id=1, status="impresso_requested", impresso=outcome
        )
        task = self.connect()
        with self.assertNoLogs("voice-worker", level="WARNING"):
            await self.say("solicito hemograma")
            await self.say("onde dói")
            self.tts.streams[0].queue.put_nowait(chunk("a2"))
            await settle()
            await self.disconnect(task)

        self.assertEqual(
            self.room.patient_events()[0],
            {
                "session_id": "s1",
                "turn_id": 1,
                "role": "examiner",
                "status": "impresso_requested",
                **outcome,
            },
        )
        # The next utterance is a dialogue turn again.
        self.assertEqual(self.room.patient_events()[1]["role"], "patient")
        self.assertEqual(self.tts.texts, [f"{REPLY_TEXT} 2"])
        self.assertEqual(self.client.cancel_calls, [])

    async def test_duplicate_turn_without_reply_text_speaks_nothing(self):
        self.client.replies[1] = VoiceTurnReply(turn_id=1, status="duplicate")
        task = self.connect()
        await self.say("repetida")
        await self.disconnect(task)

        self.assertEqual(self.room.patient_events(), [])
        self.assertEqual(self.tts.texts, [])
        self.assertEqual(self.room.published_tracks, [])

    async def test_track_publication_failure_at_job_start_is_not_fatal(self):
        async def failing_publish_track(_track, _options=None):
            raise RuntimeError(PROVIDER_SECRET)

        self.room.local_participant.publish_track = failing_publish_track
        with self.assertLogs("voice-worker", level="WARNING") as logs:
            await self.voice.start()

        output = "\n".join(logs.output)
        self.assertIn("synthesis_failed", output)
        self.assertNotIn(PROVIDER_SECRET, output)


def typed_reply_packet(
    turn_id=0,
    generation_id=1,
    text="Resposta digitada",
    session_id="s1",
    participant=None,
    topic=TYPED_REPLY_TOPIC,
    **extra,
):
    """A data packet as LiveKit hands it over: from the server when `participant` is None."""
    payload = {
        "session_id": session_id,
        "turn_id": turn_id,
        "generation_id": generation_id,
        "text": text,
        **extra,
    }
    return SimpleNamespace(
        data=json.dumps(payload).encode(),
        participant=participant,
        topic=topic,
        kind=None,
    )


# Issue #325: the approved reply to a typed turn is spoken, fenced like a spoken one.
class TypedReplyTest(unittest.IsolatedAsyncioTestCase):
    setUp = PatientVoiceFlowTest.setUp
    _source = PatientVoiceFlowTest._source
    connect = PatientVoiceFlowTest.connect
    say = PatientVoiceFlowTest.say
    disconnect = PatientVoiceFlowTest.disconnect

    def receive(self, packet) -> None:
        on_typed_reply(packet, self.tracker, self.voice)

    async def test_an_approved_typed_reply_is_spoken_and_publishes_no_text(self):
        task = self.connect()
        self.receive(typed_reply_packet(text="Doi aqui"))
        await settle()

        self.assertEqual(self.tts.texts, ["Doi aqui"])
        self.tts.streams[0].queue.put_nowait(chunk("t1"))
        await settle()
        self.assertEqual(self.sources[0].frames, ["t1"])
        # The learner's screen shows the text from the typed turn's own answer.
        self.assertEqual(self.room.patient_events(), [])
        await self.disconnect(task)

    async def test_a_companion_reply_is_spoken_with_its_voice(self):
        task = self.connect()
        self.receive(typed_reply_packet(speaker="companion", voice="mother"))
        await settle()

        self.assertEqual(self.voice.player.speaking.speaker, "companion")
        self.assertEqual(self.voice.player.speaking.voice, "mother")
        await self.disconnect(task)

    async def test_only_the_server_can_ask_for_a_typed_reply(self):
        task = self.connect()
        with self.assertLogs("voice-worker", level="WARNING") as logs:
            self.receive(typed_reply_packet(participant=SimpleNamespace(identity="x")))
            self.receive(typed_reply_packet(topic="transcript"))
            self.receive(typed_reply_packet(session_id="other"))
            self.receive(typed_reply_packet(text=""))
            self.receive(typed_reply_packet(generation_id=0))
            self.receive(typed_reply_packet(turn_id=-1))
            self.receive(
                SimpleNamespace(data=b"{", participant=None, topic=TYPED_REPLY_TOPIC)
            )
            await settle()
            # Something must be logged for the test to read the logs.
            worker.logger.warning("end of packets")

        self.assertEqual(self.tts.texts, [])
        self.assertNotIn("Resposta digitada", "\n".join(logs.output))
        await self.disconnect(task)

    async def test_a_repeated_typed_reply_is_spoken_once(self):
        task = self.connect()
        self.receive(typed_reply_packet())
        self.receive(typed_reply_packet())
        await settle()

        self.assertEqual(self.tts.texts, ["Resposta digitada"])
        await self.disconnect(task)

    async def test_a_typed_reply_after_the_spoken_turn_it_follows_is_spoken(self):
        task = self.connect()
        await self.say("primeira")
        self.tts.streams[0].queue.put_nowait(chunk("a1"))
        await settle()

        self.receive(typed_reply_packet(turn_id=1, generation_id=2))
        await settle()

        self.assertEqual(self.tts.texts, [f"{REPLY_TEXT} 1", "Resposta digitada"])
        self.assertEqual(self.tts.streams[0].closed, 1)  # it supersedes the older reply
        await self.disconnect(task)

    async def test_a_reply_superseded_by_a_newer_spoken_generation_is_never_spoken(
        self,
    ):
        task = self.connect()
        await self.say("primeira")
        await settle()

        # Generation 1 began before the spoken turn's generation, which reached the worker first.
        self.receive(typed_reply_packet(turn_id=1, generation_id=1))
        await settle()

        self.assertEqual(self.tts.texts, [f"{REPLY_TEXT} 1"])
        await self.disconnect(task)

    async def test_a_reply_the_learner_spoke_after_is_never_spoken(self):
        task = self.connect()
        # The learner speaks turn 1 while Phoenix still answers the typed turn after turn 0.
        self.queue.put_nowait(event(INTERIM, "espera"))
        await asyncio.sleep(0.01)

        self.receive(typed_reply_packet(turn_id=0, generation_id=1))
        await settle()

        self.assertEqual(self.tts.texts, [])
        await self.disconnect(task)

    async def test_speaking_over_a_typed_reply_stops_it(self):
        for turn_id, spoken_turns in ((0, []), (1, ["primeira"])):
            with self.subTest(turn_id=turn_id):
                self.setUp()
                task = self.connect()
                for text in spoken_turns:
                    await self.say(text)
                    await settle()
                self.receive(typed_reply_packet(turn_id=turn_id, generation_id=9))
                await settle()
                stream = self.tts.streams[-1]
                stream.queue.put_nowait(chunk("t1"))
                await settle()

                self.queue.put_nowait(event(INTERIM, "espera"))
                await asyncio.sleep(0.01)

                self.assertEqual(stream.closed, 1)
                stream.queue.put_nowait(chunk("late"))
                await settle()
                self.assertNotIn("late", self.sources[0].frames)
                self.assertEqual(self.voice.player.speaking, None)
                await self.disconnect(task)

    async def test_a_newer_spoken_turn_after_a_typed_reply_is_spoken(self):
        task = self.connect()
        self.receive(typed_reply_packet(turn_id=0, generation_id=1))
        await settle()

        # Phoenix gives the spoken turn the next generation.
        self.client.replies[1] = VoiceTurnReply(
            turn_id=1, status="committed", generation_id=2, reply_text="Falada"
        )
        await self.say("primeira")
        await settle()

        self.assertEqual(self.tts.texts, ["Resposta digitada", "Falada"])
        self.assertEqual(self.voice.player.speaking.reply_text, "Falada")
        await self.disconnect(task)

    async def test_a_synthesis_failure_is_logged_and_publishes_nothing(self):
        self.tts.synthesize_error = APIConnectionError(PROVIDER_SECRET)
        task = self.connect()
        with self.assertLogs("voice-worker", level="WARNING") as logs:
            self.receive(typed_reply_packet())
            await settle()

        output = "\n".join(logs.output)
        self.assertIn("synthesis_failed", output)
        self.assertNotIn(PROVIDER_SECRET, output)
        self.assertNotIn("Resposta digitada", output)
        self.assertEqual(self.room.patient_events(), [])
        await self.disconnect(task)


class BuildVoiceTTSTest(unittest.TestCase):
    """Issues #341, #398: voice keys (`voz=`) map to Cartesia voices by environment."""

    CONTEXT: ClassVar[dict[str, object]] = {"language": "pt-BR", "keyterms": []}
    BASE: ClassVar[dict[str, str]] = {
        "CARTESIA_API_KEY": PROVIDER_SECRET,
        "CARTESIA_VOICE_ID": "voice-1",
    }

    def test_maps_each_voice_key_to_its_cartesia_voice(self):
        env = {
            **self.BASE,
            "CARTESIA_VOICE_IDS": "feminina-adulta=voice-f, infantil=voice-c",
        }
        with (
            patch.dict(os.environ, env, clear=True),
            patch.object(worker.cartesia, "TTS") as tts,
        ):
            voices = build_voice_tts("s1", self.CONTEXT)

        self.assertEqual(sorted(voices), ["feminina-adulta", "infantil"])
        self.assertEqual(
            sorted(call.kwargs["voice"] for call in tts.call_args_list),
            ["voice-c", "voice-f"],
        )
        for call in tts.call_args_list:
            self.assertEqual(
                call.kwargs,
                {
                    **call.kwargs,
                    "api_key": PROVIDER_SECRET,
                    "model": "sonic-3",
                    "encoding": "pcm_s16le",
                    "sample_rate": 24000,
                    "word_timestamps": False,
                    "language": "pt-BR",
                },
            )

    def test_every_voice_key_of_the_case_format_can_be_mapped(self):
        keys = [
            "infantil",
            "masculina-adulta",
            "feminina-adulta",
            "masculina-idosa",
            "feminina-idosa",
        ]
        env = {
            **self.BASE,
            "CARTESIA_VOICE_IDS": ",".join(f"{key}=id-{key}" for key in keys),
        }
        with (
            patch.dict(os.environ, env, clear=True),
            patch.object(worker.cartesia, "TTS"),
        ):
            self.assertEqual(sorted(build_voice_tts("s1", self.CONTEXT)), sorted(keys))

    def test_uses_the_cartesia_model_override(self):
        env = {
            **self.BASE,
            "CARTESIA_MODEL": "sonic-turbo",
            "CARTESIA_VOICE_IDS": "infantil=voice-c",
        }
        with (
            patch.dict(os.environ, env, clear=True),
            patch.object(worker.cartesia, "TTS") as tts,
        ):
            build_voice_tts("s1", self.CONTEXT)
        self.assertEqual(tts.call_args.kwargs["model"], "sonic-turbo")

    def test_no_mapping_means_the_default_voice_only(self):
        with (
            patch.dict(os.environ, self.BASE, clear=True),
            patch.object(worker.cartesia, "TTS") as tts,
        ):
            self.assertEqual(build_voice_tts("s1", self.CONTEXT), {})
        tts.assert_not_called()

    def test_malformed_entries_are_skipped_without_leaking_them(self):
        env = {
            **self.BASE,
            "CARTESIA_VOICE_IDS": "feminina-adulta=voice-f,broken,=x,y=",
        }
        with (
            patch.dict(os.environ, env, clear=True),
            patch.object(worker.cartesia, "TTS"),
            self.assertLogs("voice-worker", level="WARNING") as logs,
        ):
            voices = build_voice_tts("s1", self.CONTEXT)

        self.assertEqual(list(voices), ["feminina-adulta"])
        self.assertIn("CARTESIA_VOICE_IDS", "\n".join(logs.output))
        self.assertNotIn("voice-f", "\n".join(logs.output))
        self.assertNotIn(PROVIDER_SECRET, "\n".join(logs.output))

    def test_missing_api_key_maps_nothing(self):
        env = {"CARTESIA_VOICE_IDS": "feminina-adulta=voice-f"}
        with (
            patch.dict(os.environ, env, clear=True),
            patch.object(worker.cartesia, "TTS") as tts,
        ):
            self.assertEqual(build_voice_tts("s1", self.CONTEXT), {})
        tts.assert_not_called()

    def test_elevenlabs_voice_map_is_no_longer_read(self):
        env = {**self.BASE, "ELEVENLABS_VOICE_IDS": "feminina-adulta=voice-f"}
        with (
            patch.dict(os.environ, env, clear=True),
            patch.object(worker.cartesia, "TTS") as tts,
        ):
            self.assertEqual(build_voice_tts("s1", self.CONTEXT), {})
        tts.assert_not_called()

    def test_fake_providers_map_no_cartesia_voice(self):
        env = {
            **self.BASE,
            "CARTESIA_VOICE_IDS": "feminina-adulta=voice-f",
            "VOICE_WORKER_FAKE_PROVIDERS": "true",
            "LIVEKIT_URL": "ws://127.0.0.1:7880",
        }
        with (
            patch.dict(os.environ, env, clear=True),
            patch.object(worker.cartesia, "TTS") as tts,
        ):
            self.assertEqual(build_voice_tts("s1", self.CONTEXT), {})
        tts.assert_not_called()


class BuildTTSTest(unittest.TestCase):
    CONTEXT: ClassVar[dict[str, object]] = {"language": "pt-BR", "keyterms": []}

    def test_reads_cartesia_settings_from_the_worker_environment(self):
        env = {"CARTESIA_API_KEY": PROVIDER_SECRET, "CARTESIA_VOICE_ID": "voice-1"}
        with (
            patch.dict(os.environ, env, clear=True),
            patch.object(worker.cartesia, "TTS") as tts,
        ):
            self.assertIs(build_tts("s1", self.CONTEXT), tts.return_value)

        tts.assert_called_once_with(
            api_key=PROVIDER_SECRET,
            voice="voice-1",
            model="sonic-3",
            encoding="pcm_s16le",
            sample_rate=24000,
            word_timestamps=False,
            language="pt-BR",
        )

    def test_model_can_be_overridden(self):
        env = {
            "CARTESIA_API_KEY": PROVIDER_SECRET,
            "CARTESIA_VOICE_ID": "voice-1",
            "CARTESIA_MODEL": "sonic-turbo",
        }
        with (
            patch.dict(os.environ, env, clear=True),
            patch.object(worker.cartesia, "TTS") as tts,
        ):
            build_tts("s1", self.CONTEXT)

        self.assertEqual(tts.call_args.kwargs["model"], "sonic-turbo")

    def test_missing_configuration_disables_speech_without_leaking_it(self):
        env = {"CARTESIA_API_KEY": PROVIDER_SECRET}
        with (
            patch.dict(os.environ, env, clear=True),
            patch.object(worker.cartesia, "TTS") as tts,
            self.assertLogs("voice-worker", level="WARNING") as logs,
        ):
            self.assertIsNone(build_tts("s1", self.CONTEXT))

        tts.assert_not_called()
        self.assertIn("session s1", "\n".join(logs.output))
        self.assertIn("synthesis_failed", "\n".join(logs.output))
        self.assertNotIn(PROVIDER_SECRET, "\n".join(logs.output))

    def test_blank_required_setting_disables_speech_like_a_missing_one(self):
        for blank in ("CARTESIA_API_KEY", "CARTESIA_VOICE_ID"):
            env = {
                "CARTESIA_API_KEY": PROVIDER_SECRET,
                "CARTESIA_VOICE_ID": "voice-1",
                blank: "  ",
            }
            with (
                self.subTest(blank=blank),
                patch.dict(os.environ, env, clear=True),
                patch.object(worker.cartesia, "TTS") as tts,
                self.assertLogs("voice-worker", level="WARNING") as logs,
            ):
                self.assertIsNone(build_tts("s1", self.CONTEXT))

                tts.assert_not_called()
                self.assertNotIn(PROVIDER_SECRET, "\n".join(logs.output))

    def test_blank_model_falls_back_to_the_default(self):
        env = {
            "CARTESIA_API_KEY": PROVIDER_SECRET,
            "CARTESIA_VOICE_ID": "voice-1",
            "CARTESIA_MODEL": "",
        }
        with (
            patch.dict(os.environ, env, clear=True),
            patch.object(worker.cartesia, "TTS") as tts,
        ):
            build_tts("s1", self.CONTEXT)

        self.assertEqual(tts.call_args.kwargs["model"], "sonic-3")

    def test_elevenlabs_settings_no_longer_enable_speech(self):
        env = {"ELEVENLABS_API_KEY": PROVIDER_SECRET, "ELEVENLABS_VOICE_ID": "voice-1"}
        with (
            patch.dict(os.environ, env, clear=True),
            patch.object(worker.cartesia, "TTS") as tts,
            self.assertLogs("voice-worker", level="WARNING"),
        ):
            self.assertIsNone(build_tts("s1", self.CONTEXT))

        tts.assert_not_called()

    def test_real_provider_speaks_pt_br_as_raw_24khz_pcm(self):
        env = {"CARTESIA_API_KEY": PROVIDER_SECRET, "CARTESIA_VOICE_ID": "voice-1"}
        with patch.dict(os.environ, env, clear=True):
            tts = build_tts("s1", self.CONTEXT)

        self.assertEqual((tts.sample_rate, tts.num_channels), (24000, 1))
        self.assertEqual(tts._opts.language.language, "pt")
        self.assertEqual(tts._opts.encoding, "pcm_s16le")

    def test_real_provider_builds_without_a_word_timestamps_warning(self):
        env = {"CARTESIA_API_KEY": PROVIDER_SECRET, "CARTESIA_VOICE_ID": "voice-1"}
        with (
            patch.dict(os.environ, env, clear=True),
            self.assertNoLogs(level="WARNING"),
        ):
            self.assertIsNotNone(build_tts("s1", self.CONTEXT))


if __name__ == "__main__":
    unittest.main()


class PhoenixTurnSettingsTest(unittest.TestCase):
    def test_defaults_cover_the_server_budget(self):
        import transcripts

        self.assertEqual(
            phoenix_turn_settings({}),
            (transcripts.DEFAULT_TURN_TIMEOUT_S, transcripts.DEFAULT_TURN_RETRIES),
        )

    def test_reads_timeout_and_retries_from_the_environment(self):
        env = {"PHOENIX_TURN_TIMEOUT_S": " 20.5 ", "PHOENIX_TURN_RETRIES": "0"}
        self.assertEqual(phoenix_turn_settings(env), (20.5, 0))

    def test_invalid_values_fall_back_to_the_defaults(self):
        import transcripts

        for env in (
            {"PHOENIX_TURN_TIMEOUT_S": "abc", "PHOENIX_TURN_RETRIES": "-1"},
            {"PHOENIX_TURN_TIMEOUT_S": "0", "PHOENIX_TURN_RETRIES": "1.5"},
            {"PHOENIX_TURN_TIMEOUT_S": "nan", "PHOENIX_TURN_RETRIES": ""},
            # Non-ASCII digits pass str.isdigit() but int() rejects them.
            {"PHOENIX_TURN_TIMEOUT_S": "", "PHOENIX_TURN_RETRIES": "²"},
        ):
            with self.assertLogs("voice-worker", level="WARNING"):
                self.assertEqual(
                    phoenix_turn_settings(env),
                    (
                        transcripts.DEFAULT_TURN_TIMEOUT_S,
                        transcripts.DEFAULT_TURN_RETRIES,
                    ),
                )


class TranscribeEofBudgetTest(unittest.IsolatedAsyncioTestCase):
    async def test_transcribe_waits_for_pending_turns_within_the_phoenix_budget(self):
        client = ControllablePhoenixClient()
        seen = {}

        async def fake_process(*_args, **kwargs):
            seen["eof_timeout"] = kwargs["eof_timeout"]

        with patch.object(worker, "process_speech_stream", fake_process):
            await transcribe(
                MockRoom(),
                learner=None,
                context={"language": "pt-BR", "keyterms": []},
                tracker=TurnTracker("s1", last_turn_id=0),
                phoenix=client,
                stt=MockSTT(MockStream(asyncio.Queue())),
                audio=MockAudioStream(),
            )
        self.assertEqual(seen["eof_timeout"], client.eof_timeout)
