"""Provider-neutral transcript normalization and the Phoenix worker API client.

Nothing in this module logs or stores transcript text, audio or provider payloads.
"""

# pyright: reportMissingImports=false
import asyncio
import json
import logging
import sys

import httpx
from livekit.agents import APIConnectionError, APIStatusError, APITimeoutError
from livekit.agents.stt import SpeechEvent, SpeechEventType

logger = logging.getLogger("voice-worker.transcripts")

# Phoenix answers a transcript POST only after the patient reply is generated and
# verified (#269). Worst case: the patient generation (Phoenix sets no timeout of
# its own, so Req's 15 s receive timeout applies), the Jev verification budget
# (`jev_decision_default_deadline_ms`, 3 s), one regeneration after a refusal
# (another 15 s) and 2 s headroom: 15 + 3 + 15 + 2 = 35 s. Override with
# PHOENIX_TURN_TIMEOUT_S when the server budget changes.
PATIENT_GENERATION_TIMEOUT_S = 15.0
VERIFICATION_DEADLINE_S = 3.0
TURN_HEADROOM_S = 2.0
DEFAULT_TURN_TIMEOUT_S = (
    2 * PATIENT_GENERATION_TIMEOUT_S + VERIFICATION_DEADLINE_S + TURN_HEADROOM_S
)
DEFAULT_TURN_RETRIES = 1
# Context and cancellation calls do no generation work.
REQUEST_TIMEOUT_S = 5.0
# Drain headroom on top of every transcript attempt at end of stream.
EOF_HEADROOM_S = 5.0
# The transcript POST asks Phoenix to stream the verified sentences of the reply
# (#271); JSON stays acceptable because Phoenix answers a turn that speaks
# nothing, and older servers answer every turn, with one JSON body.
NDJSON = "application/x-ndjson"
STREAM_ACCEPT = f"{NDJSON}, application/json"
# Error codes a sentence stream may end with, mapped to the kinds the status
# responses produce.
_STREAM_ERROR_KINDS = {
    "unauthorized": "auth",
    "stale_generation": "stale_generation",
    "station_time_elapsed": "station_time_elapsed",
    "no_consent": "session_inactive",
    "session_not_found": "session_inactive",
    "session_expired": "session_inactive",
    "session_completed": "session_inactive",
    "station_ai_unavailable": "disconnected",
}


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
    """Typed generation-bound reply metadata returned by Phoenix (#119).

    `status` is `committed` (a verified reply to speak), `kept` (the patient reply
    was refused and Phoenix kept the learner turn without one, #269) or `duplicate`.
    A streamed sentence (#271) is a `committed` reply carrying one verified sentence
    and its `index`. A kept reply carries `addressee` (#274): `examiner` when
    Phoenix kept a turn addressed to the examiner before any generation, `patient`
    when the patient reply was refused, and `None` from an older server.
    `speech_ended_at` is the event-loop time the learner's
    utterance ended, set by `TurnManager` for the first-audio latency log.

    A sentence of a station with a companion (#341) carries `speaker` (`patient`
    or `companion`) and `voice`, the speaker's voice key; `None` otherwise.
    """

    def __init__(
        self,
        turn_id: int,
        status: str,
        generation_id: int | None = None,
        reply_text: str | None = None,
        index: int | None = None,
        addressee: str | None = None,
        speaker: str | None = None,
        voice: str | None = None,
    ):
        self.turn_id = turn_id
        self.status = status
        self.generation_id = generation_id
        self.reply_text = reply_text
        self.index = index
        self.addressee = addressee
        self.speaker = speaker
        self.voice = voice
        self.speech_ended_at: float | None = None

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

    def is_kept_receipt(self) -> bool:
        """A refused reply kept the learner turn: generation-bound, with no text."""
        return (
            self.status == "kept"
            and type(self.turn_id) is int
            and self.turn_id > 0
            and type(self.generation_id) is int
            and self.generation_id > 0
            and self.reply_text is None
        )

    def is_examiner_acknowledgement(self) -> bool:
        """A kept turn addressed to the examiner (#274), not a refused reply."""
        return self.is_kept_receipt() and self.addressee == "examiner"

    def is_settled_receipt(self) -> bool:
        """Server evidence that this turn was admitted and resolved."""
        return self.is_committed_receipt() or self.is_kept_receipt()

    def __eq__(self, other: object) -> bool:
        if isinstance(other, VoiceTurnReply):
            return (
                self.turn_id == other.turn_id
                and self.status == other.status
                and self.generation_id == other.generation_id
                and self.reply_text == other.reply_text
                and self.addressee == other.addressee
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
        if not reply.is_settled_receipt():
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
        return reply.is_kept_receipt() or bool(reply.reply_text)

    def accept_sentence(self, reply: VoiceTurnReply) -> VoiceTurnReply | None:
        """Accept one streamed verified sentence of the pending turn (#271).

        The sentence makes its generation the active one, so it can be spoken, but
        does not settle the turn: it stays pending (and open to barge-in) until
        Phoenix's result arrives and `accept_reply` settles it.
        """
        if not isinstance(reply, VoiceTurnReply) or not reply.is_committed_receipt():
            return None
        if self.is_turn_stale(reply.turn_id):
            return None
        if reply.generation_id in self.cancelled_generations:
            return None
        if (
            self.active_generation_id is not None
            and reply.generation_id < self.active_generation_id
        ):
            return None
        self.active_generation_id = reply.generation_id
        return reply

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

    def __init__(
        self,
        base_url: str,
        secret: str,
        session_id: str,
        transport=None,
        turn_timeout: float = DEFAULT_TURN_TIMEOUT_S,
        turn_retries: int = DEFAULT_TURN_RETRIES,
    ):
        self._path = f"/api/internal/voice/sessions/{session_id}"
        self._turn_timeout = turn_timeout
        self._turn_retries = turn_retries
        # End-of-stream wait for pending turns: every transcript attempt plus drain.
        self.eof_timeout = turn_timeout * (turn_retries + 1) + EOF_HEADROOM_S
        self._http = httpx.AsyncClient(
            base_url=base_url,
            headers={"authorization": f"Bearer {secret}"},
            timeout=REQUEST_TIMEOUT_S,
            transport=transport,
        )

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        await self._http.aclose()

    async def context(self) -> dict:
        return await self._request("GET", self._path)

    async def commit(self, turn_id: int, text: str, on_sentence=None) -> VoiceTurnReply:
        """Commits a final transcript; returns typed VoiceTurnReply.

        Each attempt waits for the server budget (`turn_timeout`, #269), and a
        transport failure is retried `turn_retries` times: `turn_id` makes the retry
        idempotent.

        With `on_sentence` (#271) the worker asks for the reply as a stream:
        `on_sentence` is awaited with each verified sentence (a `committed`
        `VoiceTurnReply` with `index`) as Phoenix sends it, and the returned reply
        is Phoenix's final result. Once a sentence was handed over the request is
        never retried: a retry could only answer `duplicate`.
        """
        body = {"turn_id": turn_id, "text": text}
        path = self._path + "/transcripts"
        attempts_left = self._turn_retries
        handed_over = False

        async def hand_over(sentence: VoiceTurnReply) -> None:
            nonlocal handed_over
            handed_over = True
            await on_sentence(sentence)

        while True:
            try:
                if on_sentence is None:
                    result = await self._request(
                        "POST", path, json=body, timeout=self._turn_timeout
                    )
                else:
                    result = await self._stream_turn(path, body, hand_over)
                break
            except VoiceFailure as failure:
                if (
                    failure.kind not in ("timeout", "disconnected")
                    or attempts_left <= 0
                    or handed_over
                ):
                    raise
                attempts_left -= 1

        return VoiceTurnReply(
            turn_id=result.get("turn_id"),
            status=result["status"],
            generation_id=result.get("generation_id"),
            reply_text=result.get("reply_text"),
            addressee=result.get("addressee"),
        )

    async def _stream_turn(self, path: str, body: dict, on_sentence) -> dict:
        """POST a transcript asking for NDJSON; returns the final result object.

        Lines are `sentence`, then one `result` or `error`. A single JSON body (a
        turn that speaks nothing, or an older server) is read as before.
        """
        try:
            async with self._http.stream(
                "POST",
                path,
                json=body,
                timeout=self._turn_timeout,
                headers={"accept": STREAM_ACCEPT},
            ) as response:
                if not response.headers.get("content-type", "").startswith(NDJSON):
                    await response.aread()
                    return self._decode(response)
                if response.status_code != 200:
                    self._check_status(response)
                    raise VoiceFailure("malformed")
                async for line in response.aiter_lines():
                    if not line.strip():
                        continue
                    item = _stream_item(line)
                    kind = item.get("type")
                    if kind == "sentence":
                        await on_sentence(
                            VoiceTurnReply(
                                turn_id=item.get("turn_id"),
                                status="committed",
                                generation_id=item.get("generation_id"),
                                reply_text=item.get("text"),
                                index=item.get("index"),
                                speaker=_label(item.get("speaker")),
                                voice=_label(item.get("voice")),
                            )
                        )
                    elif kind == "result" and isinstance(item.get("status"), str):
                        return item
                    elif kind == "error":
                        raise VoiceFailure(
                            _STREAM_ERROR_KINDS.get(item.get("error"), "malformed")
                        )
                    else:
                        raise VoiceFailure("malformed")
        except httpx.TimeoutException:
            raise VoiceFailure("timeout") from None
        except httpx.HTTPError:
            raise VoiceFailure("disconnected") from None
        # The stream ended without its result line.
        raise VoiceFailure("disconnected")

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
        return self._decode(response)

    def _decode(self, response: httpx.Response) -> dict:
        self._check_status(response)
        try:
            return response.json()
        except ValueError:
            raise VoiceFailure("malformed") from None

    @staticmethod
    def _check_status(response: httpx.Response) -> None:
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


def _label(value) -> str | None:
    """A speaker or voice label from Phoenix (#341); anything but a non-empty string is none."""
    return value if isinstance(value, str) and value else None


def _stream_item(line: str) -> dict:
    """One NDJSON line as a dict; anything else is malformed. Never logged."""
    try:
        item = json.loads(line)
    except ValueError:
        raise VoiceFailure("malformed") from None
    if not isinstance(item, dict):
        raise VoiceFailure("malformed")
    return item


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
        on_turn_end=None,
    ):
        self.tracker = tracker
        self.phoenix = phoenix
        self.on_reply = on_reply
        # Told when Phoenix settled a reply streamed sentence by sentence (#281).
        self.on_turn_end = on_turn_end
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
        self._speech_ended_at: dict[int, float] = {}
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
        # End of the learner's utterance, for the first-audio latency log (#271).
        self._speech_ended_at[turn_id] = asyncio.get_running_loop().time()
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
            speech_ended_at = self._speech_ended_at.pop(turn_id, None)
            for older in [t for t in self._speech_ended_at if t < turn_id]:
                del self._speech_ended_at[older]  # superseded before dispatch
            streamed = False

            async def on_sentence(sentence: VoiceTurnReply) -> None:
                # Each verified sentence is spoken as it arrives (#271); the turn
                # stays pending, so a barge-in still cancels it.
                nonlocal streamed
                if sentence.turn_id != turn_id:
                    return
                accepted_sentence = self.tracker.accept_sentence(sentence)
                if accepted_sentence is None:
                    return
                streamed = True
                accepted_sentence.speech_ended_at = speech_ended_at
                if self.on_reply is not None:
                    result = self.on_reply(accepted_sentence)
                    if asyncio.iscoroutine(result):
                        await result

            reply = await self.phoenix.commit(turn_id, text, on_sentence=on_sentence)
            reply.speech_ended_at = speech_ended_at
            if (
                isinstance(reply, VoiceTurnReply)
                and reply.is_settled_receipt()
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
                # A streamed reply was already spoken sentence by sentence; its
                # result only settles the turn.
                if accepted is not None and self.on_reply is not None and not streamed:
                    result = self.on_reply(accepted)
                    if asyncio.iscoroutine(result):
                        await result
                if accepted is not None and streamed and self.on_turn_end is not None:
                    # Every sentence was handed over: the reply is complete (#281).
                    result = self.on_turn_end(accepted)
                    if asyncio.iscoroutine(result):
                        await result
                if accepted is None and reply.is_settled_receipt():
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
        # The worker passes PhoenixClient.eof_timeout (every transcript attempt
        # plus drain headroom, #269); this default only serves direct callers.
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
    on_turn_end=None,
) -> None:
    turn_manager = TurnManager(
        tracker=tracker,
        phoenix=phoenix,
        on_reply=on_reply,
        cleanup_timeout=cleanup_timeout,
        on_cancel=on_cancel,
        on_turn_end=on_turn_end,
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
