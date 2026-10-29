# pyright: reportMissingImports=false
import asyncio
import time
import unittest

from livekit.agents.stt import SpeechEventType

from push_to_talk import PushToTalk
from test_transcripts import END, FINAL, INTERIM, MockStream, event

START = SpeechEventType.START_OF_SPEECH
QUIET_S = 0.03
MAX_SETTLE_S = 0.3


def described(speech_event) -> tuple:
    text = speech_event.alternatives[0].text if speech_event.alternatives else None
    return (speech_event.type, text)


# Issue #419: the Unreal client's microphone is push-to-talk. It publishes the
# track muted, unmutes it while the learner holds the talk key and mutes it again
# on release; the worker hears those as a press and a release.
class PushToTalkTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.queue: asyncio.Queue = asyncio.Queue()
        self.stream = MockStream(self.queue)
        self.ptt = PushToTalk(self.stream, quiet_s=QUIET_S, max_settle_s=MAX_SETTLE_S)

    async def asyncTearDown(self):
        await self.ptt.aclose()

    def hear(self, kind, text=None) -> None:
        self.queue.put_nowait(event(kind, text))

    async def next_events(self, count: int, timeout: float = 1.0) -> list[tuple]:
        return [
            described(await asyncio.wait_for(anext(self.ptt), timeout))
            for _ in range(count)
        ]

    async def assert_nothing_within(self, seconds: float) -> None:
        with self.assertRaises(TimeoutError):
            await asyncio.wait_for(anext(self.ptt), seconds)

    async def on_push_to_talk(self) -> None:
        # The client mutes its microphone right after publishing it.
        self.ptt.release()

    async def test_a_microphone_never_muted_keeps_deepgram_end_of_speech(self):
        self.hear(FINAL, "onde dói")
        self.hear(END)

        self.assertEqual(await self.next_events(2), [(FINAL, "onde dói"), (END, None)])
        self.assertEqual(self.stream.flushes, 0)

    async def test_muting_a_silent_microphone_only_switches_to_push_to_talk(self):
        await self.on_push_to_talk()

        await self.assert_nothing_within(MAX_SETTLE_S + QUIET_S)
        self.assertEqual(self.stream.flushes, 0)

    async def test_a_press_interrupts_at_once(self):
        await self.on_push_to_talk()
        self.ptt.press()

        self.assertEqual(await self.next_events(1, timeout=QUIET_S), [(START, None)])

    async def test_deepgram_end_of_speech_does_not_end_a_held_turn(self):
        await self.on_push_to_talk()
        self.ptt.press()
        self.hear(FINAL, "onde")
        self.hear(END)
        self.hear(FINAL, "dói")

        self.assertEqual(
            await self.next_events(3),
            [(START, None), (FINAL, "onde"), (FINAL, "dói")],
        )
        await self.assert_nothing_within(QUIET_S * 3)

    async def test_release_finalizes_and_ends_the_turn_once_the_transcript_is_quiet(
        self,
    ):
        await self.on_push_to_talk()
        self.ptt.press()
        self.hear(FINAL, "onde dói")
        await self.next_events(2)

        released_at = time.monotonic()
        self.ptt.release()

        self.assertEqual(self.stream.flushes, 1)
        self.assertEqual(await self.next_events(1), [(END, None)])
        self.assertLess(time.monotonic() - released_at, MAX_SETTLE_S)

    async def test_release_waits_for_the_final_of_a_pending_interim(self):
        await self.on_push_to_talk()
        self.ptt.press()
        self.hear(INTERIM, "dor no")
        await self.next_events(2)
        self.ptt.release()

        await self.assert_nothing_within(QUIET_S * 3)
        self.hear(FINAL, "dor no peito")

        self.assertEqual(
            await self.next_events(2), [(FINAL, "dor no peito"), (END, None)]
        )

    async def test_a_pending_interim_stands_in_for_a_final_that_never_comes(self):
        await self.on_push_to_talk()
        self.ptt.press()
        self.hear(INTERIM, "dor no")
        await self.next_events(2)
        self.ptt.release()

        self.assertEqual(
            await self.next_events(2, timeout=MAX_SETTLE_S * 2),
            [(FINAL, "dor no"), (END, None)],
        )

    async def test_a_word_transcribed_only_after_the_release_still_ends_the_turn(self):
        await self.on_push_to_talk()
        self.ptt.press()
        await self.next_events(1)
        self.ptt.release()

        await asyncio.sleep(QUIET_S * 2)
        self.hear(FINAL, "sim")

        self.assertEqual(await self.next_events(2), [(FINAL, "sim"), (END, None)])

    async def test_a_press_with_nothing_heard_ends_no_turn(self):
        await self.on_push_to_talk()
        self.ptt.press()
        await self.next_events(1)
        self.ptt.release()

        await self.assert_nothing_within(MAX_SETTLE_S + QUIET_S)

    async def test_transcript_after_the_turn_ended_is_dropped_until_the_next_press(
        self,
    ):
        await self.on_push_to_talk()
        self.ptt.press()
        self.hear(FINAL, "onde dói")
        self.ptt.release()
        await self.next_events(3)

        self.hear(FINAL, "tarde")
        self.hear(END)
        await self.assert_nothing_within(QUIET_S * 3)

        self.ptt.press()
        self.hear(FINAL, "nova")
        self.assertEqual(await self.next_events(2), [(START, None), (FINAL, "nova")])

    async def test_pressing_again_before_the_turn_ended_continues_the_same_turn(self):
        await self.on_push_to_talk()
        self.ptt.press()
        self.hear(FINAL, "onde")
        await self.next_events(2)
        self.ptt.release()
        self.ptt.press()
        self.hear(FINAL, "dói")
        await asyncio.sleep(QUIET_S * 3)
        self.ptt.release()

        self.assertEqual(
            await self.next_events(3),
            [(START, None), (FINAL, "dói"), (END, None)],
        )
        await self.assert_nothing_within(QUIET_S * 3)

    async def test_a_repeated_press_or_release_changes_nothing(self):
        await self.on_push_to_talk()
        self.ptt.press()
        self.ptt.press()
        self.hear(FINAL, "onde dói")
        self.ptt.release()
        self.ptt.release()

        self.assertEqual(
            await self.next_events(3),
            [(START, None), (FINAL, "onde dói"), (END, None)],
        )
        self.assertEqual(self.stream.flushes, 1)
        await self.assert_nothing_within(QUIET_S * 3)

    async def test_speech_heard_before_the_first_mute_ends_with_it(self):
        self.hear(INTERIM, "onde")
        await self.next_events(1)
        self.ptt.release()
        self.hear(FINAL, "onde dói")

        self.assertEqual(await self.next_events(2), [(FINAL, "onde dói"), (END, None)])
        self.assertEqual(self.stream.flushes, 1)

    async def test_the_end_of_the_transcription_ends_the_stream(self):
        self.queue.put_nowait(None)

        with self.assertRaises(StopAsyncIteration):
            await anext(self.ptt)

    async def test_a_transcription_failure_reaches_the_reader(self):
        self.queue.put_nowait(RuntimeError("deepgram"))

        with self.assertRaisesRegex(RuntimeError, "deepgram"):
            await anext(self.ptt)
