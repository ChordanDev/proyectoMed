"""Provider-neutral transcript normalization and the Phoenix worker API client.

Nothing in this module logs or stores transcript text, audio or provider payloads.
"""

# pyright: reportMissingImports=false
import asyncio
import logging
import sys

import httpx
from livekit.agents import APIConnectionError, APIStatusError, APITimeoutError
from livekit.agents.stt import SpeechEvent, SpeechEventType

logger = logging.getLogger("voice-worker.transcripts")


class VoiceFailure(Exception):
    """Typed failure. `kind` is one of: auth, timeout, disconnected, malformed, session_inactive, stale_generation,
    station_time_elapsed (the station deadline ended the session; never retried),
    synthesis_failed (patient speech only; never stops the worker job).
    The room `failure` event may also carry text_delivery_failed (see worker.PatientVoice).

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

    def is_committed_receipt(self) -> bool:
        """Validate runtime metadata before trusting it as server fence evidence."""
        return (
            self.status == "committed"
            and type(self.turn_id) is int
            and self.turn_id > 0
            and type(self.generation_id) is int
            and self.generation_id > 0
            and isinstance(self.reply_text, str)
            and bool(self.reply_text.strip())
        )

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
    authoritative allocation floor, covering committed and cancelled turn IDs.
    Tracks active generation identity and cancels/rejects superseded or duplicate replies.
    """

    def __init__(
        self, session_id: str, last_turn_id: int, turn_id_floor: int | None = None
    ):
        self.session_id = session_id
        allocation_floor = max(last_turn_id, turn_id_floor or 0)
        self.turn_id = allocation_floor + 1
        self.segments: list[str] = []
        self.active_generation_id: int | None = None
        self.last_accepted_turn_id: int = last_turn_id
        self.cancelled_generations: set[int] = set()
        self.cancelled_turns: set[int] = set()
        # Allocation is not acceptance, but replies from this prefix must not replay.
        self._stale_turn_floor = allocation_floor

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
        """Fence an interrupted monotonic stream prefix, including delayed work.

        Explicit cancel(turn_id=...) remains specific, including future IDs;
        stream barge-in supersedes all earlier turns, not an arbitrary future ID.
        """
        self._stale_turn_floor = max(self._stale_turn_floor, turn_id)
        self.cancelled_turns.difference_update(
            turn
            for turn in tuple(self.cancelled_turns)
            if turn <= self._stale_turn_floor
        )

    def is_turn_stale(self, turn_id: int) -> bool:
        return (
            turn_id <= max(self._stale_turn_floor, self.last_accepted_turn_id)
            or turn_id in self.cancelled_turns
        )

    def is_valid_reply(self, reply: VoiceTurnReply) -> bool:
        """Validates that a reply is generation-bound, not duplicate, and not superseded/cancelled."""
        if not isinstance(reply, VoiceTurnReply):
            return False
        if not reply.is_committed_receipt():
            return False
        if self.is_turn_stale(reply.turn_id):
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
        self.cancelled_turns.difference_update(
            turn
            for turn in tuple(self.cancelled_turns)
            if turn <= self.last_accepted_turn_id
        )
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
            turn_id=result.get("turn_id"),
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
            raise VoiceFailure(_conflict_kind(response))
        if response.status_code == 400:
            raise VoiceFailure("malformed")
        if response.status_code >= 300:
            raise VoiceFailure("disconnected")
        try:
            return response.json()
        except ValueError:
            raise VoiceFailure("malformed") from None


def _conflict_kind(response: httpx.Response) -> str:
    """Kind of a 409: one superseded turn, unless Phoenix names the station deadline.

    Only the `error` code is read; an unreadable or unexpected body stays stale.
    """
    try:
        body = response.json()
    except ValueError:
        return "stale_generation"
    if isinstance(body, dict) and body.get("error") == "station_time_elapsed":
        return "station_time_elapsed"
    return "stale_generation"


class TurnManager:
    """Manages bounded asynchronous pending turn tasks and turn-scoped cancellation (#119)."""

    # One queued final and one cancellation runner, in addition to these slots.
    # Ambiguous dispatches occupy ownership slots even after their HTTP task ends.
    MAX_DISPATCHED_TURNS = 16

    def __init__(
        self,
        tracker: TurnTracker,
        phoenix: PhoenixClient,
        on_reply=None,
        cleanup_timeout: float = 1.0,
        on_cancel=None,
    ):
        self.tracker = tracker
        self.phoenix = phoenix
        self.on_reply = on_reply
        # Synchronous consumer told which turn was cancelled or went stale (#120).
        self.on_cancel = on_cancel
        self.pending_turn_id: int | None = None
        self.pending_commit_task: asyncio.Task | None = None
        self.pending_cancel_task: asyncio.Task | None = None
        # Cancellation ownership survives a newer queued turn and local task aborts.
        self._unresolved_cancel_turns: set[int] = set()
        self._all_tasks: set[asyncio.Task] = set()
        self._active_commit_tasks: set[asyncio.Task] = set()
        self._queued_commit: tuple[int, str] | None = None
        self._queued_task: asyncio.Task | None = None
        self._cancel_requested_turns: set[int] = set()
        self._local_cancel_turn: int | None = None
        self._capacity_changed = asyncio.Event()
        self._unhandled_error: BaseException | None = None
        self._main_task: asyncio.Task | None = None
        self._cleaning_up = False
        # One second for the entire remote drain, not each HTTP attempt/retry.
        # Injectable for deterministic tests; timeout cannot confirm a remote fence.
        self.cleanup_timeout = cleanup_timeout

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
        # Accounting and empty/duplicate boundaries are not a new utterance. Keep
        # START handling here: the tracker intentionally normalizes it to None.
        supersedes = speech_event.type == SpeechEventType.START_OF_SPEECH
        if speech_event.type in (
            SpeechEventType.INTERIM_TRANSCRIPT,
            SpeechEventType.FINAL_TRANSCRIPT,
        ):
            supersedes = bool(self.tracker._text(speech_event))
        if not supersedes:
            return None
        if (
            self.pending_turn_id is not None
            and not self.tracker.is_turn_stale(self.pending_turn_id)
        ):
            turn_to_cancel = self.pending_turn_id
            self.tracker.mark_turn_stale(turn_to_cancel)
            self._notify_cancel(turn_to_cancel)
            if self._queued_commit and self._queued_commit[0] == turn_to_cancel:
                # Only explicit barge-in allows queued text to be superseded.
                self._queued_commit = None
            self._cancel_requested_turns.update(
                turn
                for turn in self._unresolved_cancel_turns
                if self.tracker.is_turn_stale(turn)
            )
            if turn_to_cancel not in self._unresolved_cancel_turns:
                # Preserve scoped best-effort cancellation without treating a
                # locally queued turn as evidence of a dispatched remote request.
                self._local_cancel_turn = turn_to_cancel
            self._capacity_changed.set()
            if self.pending_cancel_task is None or self.pending_cancel_task.done():
                self.pending_cancel_task = asyncio.create_task(self._drain_cancels())
                self._track_task(self.pending_cancel_task)
            return self.pending_cancel_task
        return None

    def commit_turn(self, turn_id: int, text: str) -> asyncio.Task:
        """Queue a normalized final without blocking the speech reader.

        Superseded queued finals share one admission task; its result identifies
        the latest dispatched turn, not a separate future for every stream event.
        """
        self.check_errors()
        if self._queued_commit is not None:
            queued_turn, _ = self._queued_commit
            if not self.tracker.is_turn_stale(queued_turn):
                # The stream calls this once per normalized END, after barge-in.
                # Never silently replace a nonsuperseded final from a bad caller.
                raise VoiceFailure("malformed")
        self.pending_turn_id = turn_id
        self._queued_commit = (turn_id, text)
        if len(self._unresolved_cancel_turns) >= self.MAX_DISPATCHED_TURNS:
            self._cancel_requested_turns.update(
                turn
                for turn in self._unresolved_cancel_turns
                if self.tracker.is_turn_stale(turn)
            )
            if self.pending_cancel_task is None or self.pending_cancel_task.done():
                self.pending_cancel_task = asyncio.create_task(self._drain_cancels())
                self._track_task(self.pending_cancel_task)
        self._capacity_changed.set()
        if self._queued_task is None or self._queued_task.done():
            self._queued_task = asyncio.create_task(self._admit_commit())
            self._track_task(self._queued_task)
        task = self._queued_task
        self.pending_commit_task = task
        return task

    async def _admit_commit(self) -> VoiceTurnReply | None:
        try:
            while self._queued_commit is not None:
                turn_id = self._queued_commit[0]
                if self.tracker.is_turn_stale(turn_id):
                    self._queued_commit = None
                    return None
                cancel_task = self.pending_cancel_task
                if cancel_task is not None and not cancel_task.done():
                    await cancel_task
                    continue
                if (
                    len(self._unresolved_cancel_turns) >= self.MAX_DISPATCHED_TURNS
                    or len(self._active_commit_tasks) >= self.MAX_DISPATCHED_TURNS
                ):
                    # No new dispatch while ownership is full. A timeout or local
                    # task abort cannot free it; keep only the latest queued final
                    # and leave the STT reader free to barge in or disconnect.
                    self._capacity_changed.clear()
                    await self._capacity_changed.wait()
                    continue
                turn_id, text = self._queued_commit
                self._queued_commit = None
                self._queued_task = None
                task = asyncio.current_task()
                self._active_commit_tasks.add(task)
                try:
                    return await self._do_commit(turn_id, text, None)
                finally:
                    self._active_commit_tasks.discard(task)
                    self._capacity_changed.set()
            return None
        finally:
            if self._queued_task is asyncio.current_task():
                self._queued_task = None

    async def _drain_cancels(self) -> dict | None:
        result = None
        while self._cancel_requested_turns or self._local_cancel_turn is not None:
            if self._cancel_requested_turns:
                turn_id = min(self._cancel_requested_turns)
                self._cancel_requested_turns.discard(turn_id)
            else:
                turn_id = self._local_cancel_turn
                self._local_cancel_turn = None
            result = await self._do_cancel(turn_id)
            self._capacity_changed.set()
        return result

    async def _do_cancel(self, turn_id: int) -> dict | None:
        self.tracker.mark_turn_stale(turn_id)
        try:
            result = await self.phoenix.cancel(turn_id=turn_id)
            self._unresolved_cancel_turns.discard(turn_id)
            self._capacity_changed.set()
            return result
        except VoiceFailure as failure:
            if failure.kind == "stale_generation":
                # Turn-only cancel's 409 still establishes an admission fence:
                # no matching active work, and delayed POST/retry cannot begin.
                self._unresolved_cancel_turns.discard(turn_id)
                self._capacity_changed.set()
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
            # Dispatch can outlive the HTTP await (including an idempotent retry
            # reporting duplicate). Only correlated server evidence releases it.
            self._unresolved_cancel_turns.add(turn_id)
            reply = await self.phoenix.commit(turn_id, text)
            if (
                isinstance(reply, VoiceTurnReply)
                and reply.is_committed_receipt()
                and reply.turn_id == turn_id
            ):
                # Phoenix atomically replaces the active generation on a newer
                # accepted turn and never accepts an older turn again. Only this
                # server receipt (not a queued POST or local stale flag) proves
                # that older cancellation obligations are obsolete.
                self._unresolved_cancel_turns.difference_update(
                    old
                    for old in tuple(self._unresolved_cancel_turns)
                    if old <= turn_id
                )
                self._capacity_changed.set()
            if reply.turn_id == turn_id and not self.tracker.is_turn_stale(turn_id):
                accepted = self.tracker.accept_reply(reply)
                if accepted is not None and self.on_reply is not None:
                    result = self.on_reply(accepted)
                    if asyncio.iscoroutine(result):
                        await result
                if accepted is None and reply.is_committed_receipt():
                    # A committed result the tracker refuses is a stale generation.
                    self._notify_cancel(turn_id)
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
                self._unresolved_cancel_turns.discard(turn_id)
                self.tracker.mark_turn_stale(turn_id)
                self._notify_cancel(turn_id)
                return None
            self._record_error(failure)
            raise
        except Exception as exc:
            self._record_error(exc)
            raise
        finally:
            if (
                self.pending_turn_id == turn_id
                and turn_id not in self._unresolved_cancel_turns
            ):
                self.pending_turn_id = None

    def _notify_cancel(self, turn_id: int) -> None:
        if self.on_cancel is not None:
            self.on_cancel(turn_id)

    def _track_task(self, task: asyncio.Task) -> None:
        self._all_tasks.difference_update(t for t in tuple(self._all_tasks) if t.done())
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

    async def wait_pending(self, timeout: float = 15.0) -> None:
        # One EOF budget for all work, including admission waiting on ownership.
        # The default allows two five-second HTTP attempts plus drain headroom.
        # asyncio.wait does not cancel dispatches on expiry: only cleanup may
        # abort local tasks, and expiry never releases ambiguous remote ownership.
        deadline = asyncio.get_running_loop().time() + timeout
        while self._all_tasks:
            tasks = [t for t in self._all_tasks if not t.done()]
            if not tasks:
                break
            _, pending = await asyncio.wait(
                tasks, timeout=max(0, deadline - asyncio.get_running_loop().time())
            )
            if pending:
                raise VoiceFailure("timeout")
        self.check_errors()

    async def cleanup(self, on_close=None) -> VoiceFailure | None:
        """Stop local tasks/resources, then best-effort fence owned remote turns.

        A returned failure means the remote fence is unconfirmed. Outstanding
        ownership remains only in this manager; it is not durable after its death.
        """
        self._cleaning_up = True
        turns_to_cancel = self._unresolved_cancel_turns.copy()
        if self.pending_turn_id is not None:
            # A queued ID is a best-effort cleanup target, never ownership proof.
            turns_to_cancel.add(self.pending_turn_id)
        tasks = [t for t in self._all_tasks if not t.done()]
        for task in tasks:
            task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)
        self._all_tasks.clear()
        self.pending_commit_task = None
        self.pending_cancel_task = None
        self.pending_turn_id = None
        self._queued_commit = None
        self._queued_task = None
        self._active_commit_tasks.clear()
        self._cancel_requested_turns.clear()
        self._local_cancel_turn = None

        for turn_to_cancel in turns_to_cancel:
            self.tracker.mark_turn_stale(turn_to_cancel)
        failure = None
        try:
            if on_close is not None:
                await on_close()
        finally:
            try:
                async with asyncio.timeout(self.cleanup_timeout):
                    for turn_to_cancel in sorted(turns_to_cancel):
                        try:
                            await self.phoenix.cancel(turn_id=turn_to_cancel)
                            self._unresolved_cancel_turns.discard(turn_to_cancel)
                        except VoiceFailure as exc:
                            if exc.kind == "stale_generation":
                                self._unresolved_cancel_turns.discard(turn_to_cancel)
                            else:
                                failure = exc
                        except Exception as exc:
                            failure = classify_provider_error(exc)
            except TimeoutError:
                failure = VoiceFailure("timeout")
            if self._unresolved_cancel_turns:
                logger.warning(
                    "cleanup remote fence unconfirmed for %d owned turns: %s",
                    len(self._unresolved_cancel_turns),
                    failure.kind if failure is not None else "disconnected",
                )
        return failure


async def process_speech_stream(
    stream,
    tracker: TurnTracker,
    phoenix: PhoenixClient,
    on_publish=None,
    on_reply=None,
    on_close=None,
    cleanup_timeout: float = 1.0,
    eof_timeout: float = 15.0,
    on_cancel=None,
) -> None:
    turn_manager = TurnManager(
        tracker=tracker,
        phoenix=phoenix,
        on_reply=on_reply,
        cleanup_timeout=cleanup_timeout,
        on_cancel=on_cancel,
    )
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
        await turn_manager.wait_pending(timeout=eof_timeout)
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
        primary = sys.exception()
        try:
            await turn_manager.cleanup(on_close=on_close)
        except asyncio.CancelledError:
            if primary is None:
                raise
        except Exception as exc:
            failure = (
                exc if isinstance(exc, VoiceFailure) else classify_provider_error(exc)
            )
            logger.warning("stream cleanup failed: %s", failure.kind)
            if primary is None:
                raise failure from None
