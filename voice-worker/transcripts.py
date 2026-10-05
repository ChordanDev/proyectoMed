"""Provider-neutral transcript normalization and the Phoenix worker API client.

Nothing in this module logs or stores transcript text, audio or provider payloads.
"""

# pyright: reportMissingImports=false
import asyncio
import logging

import httpx
from livekit.agents import APIConnectionError, APIStatusError, APITimeoutError
from livekit.agents.stt import SpeechEvent, SpeechEventType

logger = logging.getLogger("voice-worker.transcripts")


class VoiceFailure(Exception):
    """Typed failure. `kind` is one of: auth, timeout, disconnected, malformed, session_inactive, stale_generation.

    The message is only the kind, so provider errors (which may echo credentials) never leak.
    """

    def __init__(self, kind: str):
        super().__init__(kind)
        self.kind = kind


def classify_provider_error(exc: Exception) -> VoiceFailure:
    status_code = getattr(exc, "status_code", None)
    if isinstance(exc, APIStatusError) and status_code in (401, 403):
        return VoiceFailure("auth")
    if isinstance(exc, APITimeoutError):
        return VoiceFailure("timeout")
    if isinstance(exc, (APIStatusError, APIConnectionError)):
        return VoiceFailure("disconnected")
    return VoiceFailure("malformed")


class VoiceTurnReply:
    """Typed generation-bound reply metadata returned by Phoenix (#119)."""

    def __init__(
        self,
        turn_id: int,
        status: str,
        generation_id: int | None = None,
        reply_text: str | None = None,
    ):
        self.turn_id = turn_id
        self.status = status
        self.generation_id = generation_id
        self.reply_text = reply_text

    def __eq__(self, other: object) -> bool:
        if isinstance(other, VoiceTurnReply):
            return (
                self.turn_id == other.turn_id
                and self.status == other.status
                and self.generation_id == other.generation_id
                and self.reply_text == other.reply_text
            )
        return False

    def __repr__(self) -> str:
        # Never log or expose reply_text in string representations or logs
        return (
            f"VoiceTurnReply(turn_id={self.turn_id}, "
            f"status={self.status!r}, "
            f"generation_id={self.generation_id})"
        )


class TurnTracker:
    """Turns Deepgram interim/final/end-of-speech events into session- and turn-scoped events.

    Deepgram may split one utterance into several FINAL segments; they are joined and
    committed as exactly one learner turn at END_OF_SPEECH. Turn ids continue after the
    last turn Phoenix already committed, so a restarted worker never reuses an id.
    Tracks active generation identity and cancels/rejects superseded or duplicate replies.
    """

    def __init__(self, session_id: str, last_turn_id: int):
        self.session_id = session_id
        self.turn_id = last_turn_id + 1
        self.segments: list[str] = []
        self.active_generation_id: int | None = None
        self.last_accepted_turn_id: int = last_turn_id
        self.cancelled_generations: set[int] = set()
        self.cancelled_turns: set[int] = set()

    def handle(self, event: SpeechEvent) -> dict | None:
        if event.type == SpeechEventType.INTERIM_TRANSCRIPT:
            return self._event(False, self._text(event))
        if event.type == SpeechEventType.FINAL_TRANSCRIPT:
            text = self._text(event)
            if text:
                self.segments.append(text)
            return self._event(False)
        if event.type == SpeechEventType.END_OF_SPEECH and self.segments:
            final = self._event(True)
            self.segments = []
            self.turn_id += 1
            return final
        return None

    def cancel(
        self, generation_id: int | None = None, turn_id: int | None = None
    ) -> None:
        """Explicitly cancels active or specific generation or turn."""
        if turn_id is not None:
            self.cancelled_turns.add(turn_id)
        if generation_id is not None:
            self.cancelled_generations.add(generation_id)
        elif turn_id is None and self.active_generation_id is not None:
            self.cancelled_generations.add(self.active_generation_id)
            self.active_generation_id = None

    def mark_turn_stale(self, turn_id: int) -> None:
        """Marks a turn locally stale before or during generation."""
        self.cancelled_turns.add(turn_id)

    def is_turn_stale(self, turn_id: int) -> bool:
        return turn_id in self.cancelled_turns

    def is_valid_reply(self, reply: VoiceTurnReply) -> bool:
        """Validates that a reply is generation-bound, not duplicate, and not superseded/cancelled."""
        if not isinstance(reply, VoiceTurnReply):
            return False
        if reply.status != "committed":
            return False
        if reply.turn_id in self.cancelled_turns:
            return False
        if (
            reply.generation_id is None
            or reply.generation_id in self.cancelled_generations
        ):
            return False
        if (
            self.active_generation_id is not None
            and reply.generation_id < self.active_generation_id
        ):
            return False
        if reply.turn_id <= self.last_accepted_turn_id:
            return False
        return bool(reply.reply_text)

    def accept_reply(self, reply: VoiceTurnReply) -> VoiceTurnReply | None:
        """Accepts typed generation-bound reply metadata; rejects superseded or cancelled results."""
        if not self.is_valid_reply(reply):
            return None
        if reply.generation_id is not None:
            self.active_generation_id = max(
                self.active_generation_id or 0, reply.generation_id
            )
        self.last_accepted_turn_id = max(self.last_accepted_turn_id, reply.turn_id)
        return reply

    def _event(self, final: bool, interim: str = "") -> dict:
        text = " ".join([*self.segments, interim]).strip()
        return {
            "session_id": self.session_id,
            "turn_id": self.turn_id,
            "final": final,
            "text": text,
        }

    @staticmethod
    def _text(event: SpeechEvent) -> str:
        if not event.alternatives or not isinstance(event.alternatives[0].text, str):
            raise VoiceFailure("malformed")
        return event.alternatives[0].text.strip()


class PhoenixClient:
    """Client for Phoenix's internal voice worker API (the transcript authority)."""

    def __init__(self, base_url: str, secret: str, session_id: str, transport=None):
        self._path = f"/api/internal/voice/sessions/{session_id}"
        self._http = httpx.AsyncClient(
            base_url=base_url,
            headers={"authorization": f"Bearer {secret}"},
            timeout=5.0,
            transport=transport,
        )

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        await self._http.aclose()

    async def context(self) -> dict:
        return await self._request("GET", self._path)

    async def commit(self, turn_id: int, text: str) -> VoiceTurnReply:
        """Commits a final transcript; returns typed VoiceTurnReply.

        Retries once on a transport failure: `turn_id` makes the retry idempotent.
        """
        body = {"turn_id": turn_id, "text": text}
        try:
            result = await self._request("POST", self._path + "/transcripts", json=body)
        except VoiceFailure as failure:
            if failure.kind not in ("timeout", "disconnected"):
                raise
            result = await self._request("POST", self._path + "/transcripts", json=body)

        return VoiceTurnReply(
            turn_id=result.get("turn_id", turn_id),
            status=result["status"],
            generation_id=result.get("generation_id"),
            reply_text=result.get("reply_text"),
        )

    async def cancel(
        self, generation_id: int | None = None, turn_id: int | None = None
    ) -> dict:
        """Cancels a pending voice turn generation (#119)."""
        body = {}
        if generation_id is not None:
            body["generation_id"] = generation_id
        if turn_id is not None:
            body["turn_id"] = turn_id
        try:
            return await self._request("POST", self._path + "/cancel", json=body)
        except VoiceFailure as failure:
            if failure.kind not in ("timeout", "disconnected"):
                raise
            return await self._request("POST", self._path + "/cancel", json=body)

    async def _request(self, method: str, path: str, **kwargs) -> dict:
        try:
            response = await self._http.request(method, path, **kwargs)
        except httpx.TimeoutException:
            raise VoiceFailure("timeout") from None
        except httpx.HTTPError:
            raise VoiceFailure("disconnected") from None

        if response.status_code == 401:
            raise VoiceFailure("auth")
        if response.status_code in (403, 404, 410, 422):
            raise VoiceFailure("session_inactive")
        if response.status_code == 409:
            raise VoiceFailure("stale_generation")
        if response.status_code == 400:
            raise VoiceFailure("malformed")
        if response.status_code >= 300:
            raise VoiceFailure("disconnected")
        try:
            return response.json()
        except ValueError:
            raise VoiceFailure("malformed") from None


class TurnManager:
    """Manages bounded asynchronous pending turn tasks and turn-scoped cancellation (#119)."""

    def __init__(self, tracker: TurnTracker, phoenix: PhoenixClient, on_reply=None):
        self.tracker = tracker
        self.phoenix = phoenix
        self.on_reply = on_reply
        self.pending_turn_id: int | None = None
        self.pending_commit_task: asyncio.Task | None = None
        self.pending_cancel_task: asyncio.Task | None = None
        self._all_tasks: set[asyncio.Task] = set()
        self._unhandled_error: BaseException | None = None
        self._main_task: asyncio.Task | None = None
        self._cleaning_up = False

    def set_main_task(self, task: asyncio.Task | None = None) -> None:
        self._main_task = task or asyncio.current_task()

    def check_errors(self) -> None:
        if self._unhandled_error is not None:
            err = self._unhandled_error
            self._unhandled_error = None
            raise err

    def has_unhandled_error(self) -> bool:
        return self._unhandled_error is not None

    def on_speech_event(self, speech_event: SpeechEvent) -> asyncio.Task | None:
        self.check_errors()
        if (
            self.pending_turn_id is not None
            and not self.tracker.is_turn_stale(self.pending_turn_id)
        ):
            turn_to_cancel = self.pending_turn_id
            self.tracker.mark_turn_stale(turn_to_cancel)
            self.pending_cancel_task = asyncio.create_task(
                self._do_cancel(turn_to_cancel)
            )
            self._track_task(self.pending_cancel_task)
            return self.pending_cancel_task
        return None

    def commit_turn(self, turn_id: int, text: str) -> asyncio.Task:
        self.check_errors()
        cancel_task = self.pending_cancel_task
        self.pending_cancel_task = None
        self.pending_turn_id = turn_id

        task = asyncio.create_task(self._do_commit(turn_id, text, cancel_task))
        self.pending_commit_task = task
        self._track_task(task)
        return task

    async def _do_cancel(self, turn_id: int) -> dict | None:
        self.tracker.mark_turn_stale(turn_id)
        try:
            return await self.phoenix.cancel(turn_id=turn_id)
        except VoiceFailure as failure:
            if failure.kind in ("stale_generation", "timeout", "disconnected"):
                logger.debug(
                    "cancel turn %d best-effort fallback: %s", turn_id, failure.kind
                )
                return None
            self._record_error(failure)
            raise
        except Exception as exc:
            self._record_error(exc)
            raise

    async def _do_commit(
        self, turn_id: int, text: str, cancel_task: asyncio.Task | None
    ) -> VoiceTurnReply | None:
        try:
            if self.tracker.is_turn_stale(turn_id):
                return None
            if cancel_task and not cancel_task.done():
                await cancel_task
            if self.tracker.is_turn_stale(turn_id):
                return None
            reply = await self.phoenix.commit(turn_id, text)
            if not self.tracker.is_turn_stale(turn_id):
                accepted = self.tracker.accept_reply(reply)
                if accepted is not None and self.on_reply is not None:
                    result = self.on_reply(accepted)
                    if asyncio.iscoroutine(result):
                        await result
                return accepted
            return None
        except asyncio.CancelledError as exc:
            # A consumer may deliberately cancel while handling a reply. Propagate that
            # cancellation to the stream, but do not reinterpret cleanup's own task
            # cancellation as an independent stream failure.
            if not self._cleaning_up:
                self._record_error(exc)
            raise
        except VoiceFailure as failure:
            if failure.kind == "stale_generation":
                self.tracker.mark_turn_stale(turn_id)
                return None
            self._record_error(failure)
            raise
        except Exception as exc:
            self._record_error(exc)
            raise
        finally:
            if self.pending_turn_id == turn_id:
                self.pending_turn_id = None

    def _track_task(self, task: asyncio.Task) -> None:
        self._all_tasks.add(task)

        def _done(t: asyncio.Task) -> None:
            self._all_tasks.discard(t)
            if not t.cancelled():
                exc = t.exception()
                if exc:
                    self._record_error(exc)

        task.add_done_callback(_done)

    def _record_error(self, exc: BaseException) -> None:
        if isinstance(exc, VoiceFailure) and exc.kind == "stale_generation":
            return
        if self._unhandled_error is None:
            self._unhandled_error = exc
            if self._main_task and not self._main_task.done():
                self._main_task.cancel()

    async def wait_pending(self) -> None:
        while self._all_tasks:
            tasks = [t for t in self._all_tasks if not t.done()]
            if not tasks:
                break
            await asyncio.gather(*tasks, return_exceptions=True)
        self.check_errors()

    async def cleanup(self) -> None:
        self._cleaning_up = True
        turn_to_cancel = self.pending_turn_id
        tasks = [t for t in self._all_tasks if not t.done()]
        for task in tasks:
            task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)
        self._all_tasks.clear()
        self.pending_commit_task = None
        self.pending_cancel_task = None
        self.pending_turn_id = None

        if turn_to_cancel is not None:
            self.tracker.mark_turn_stale(turn_to_cancel)
            try:
                await self.phoenix.cancel(turn_id=turn_to_cancel)
            except VoiceFailure as failure:
                if failure.kind != "stale_generation":
                    logger.debug("cleanup cancel returned: %s", failure.kind)
            except Exception as exc:
                logger.debug("cleanup cancel ignored exception: %s", type(exc).__name__)


async def process_speech_stream(
    stream,
    tracker: TurnTracker,
    phoenix: PhoenixClient,
    on_publish=None,
    on_reply=None,
) -> None:
    turn_manager = TurnManager(tracker=tracker, phoenix=phoenix, on_reply=on_reply)
    turn_manager.set_main_task(asyncio.current_task())
    try:
        async for speech_event in stream:
            turn_manager.on_speech_event(speech_event)
            event = tracker.handle(speech_event)
            if event is None:
                continue
            if event["final"]:
                turn_manager.commit_turn(event["turn_id"], event["text"])
            if on_publish:
                res = on_publish(event)
                if asyncio.iscoroutine(res):
                    await res
        await turn_manager.wait_pending()
        turn_manager.check_errors()
    except asyncio.CancelledError:
        if turn_manager.has_unhandled_error():
            try:
                turn_manager.check_errors()
            except VoiceFailure:
                raise
            except Exception as exc:
                raise classify_provider_error(exc) from None
        raise
    except VoiceFailure:
        raise
    except Exception as exc:
        if turn_manager.has_unhandled_error():
            turn_manager.check_errors()
        raise classify_provider_error(exc) from None
    finally:
        await turn_manager.cleanup()
