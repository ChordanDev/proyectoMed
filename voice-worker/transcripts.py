"""Provider-neutral transcript normalization and the Phoenix worker API client.

Nothing in this module logs or stores transcript text, audio or provider payloads.
"""

import httpx
from livekit.agents import APIConnectionError, APIStatusError, APITimeoutError
from livekit.agents.stt import SpeechEvent, SpeechEventType


class VoiceFailure(Exception):
    """Typed failure. `kind` is one of: auth, timeout, disconnected, malformed, session_inactive.

    The message is only the kind, so provider errors (which may echo credentials) never leak.
    """

    def __init__(self, kind: str):
        super().__init__(kind)
        self.kind = kind


def classify_provider_error(exc: Exception) -> VoiceFailure:
    if isinstance(exc, APIStatusError) and exc.status_code in (401, 403):
        return VoiceFailure("auth")
    if isinstance(exc, APITimeoutError):
        return VoiceFailure("timeout")
    if isinstance(exc, (APIStatusError, APIConnectionError)):
        return VoiceFailure("disconnected")
    return VoiceFailure("malformed")


class TurnTracker:
    """Turns Deepgram interim/final/end-of-speech events into session- and turn-scoped events.

    Deepgram may split one utterance into several FINAL segments; they are joined and
    committed as exactly one learner turn at END_OF_SPEECH. Turn ids continue after the
    last turn Phoenix already committed, so a restarted worker never reuses an id.
    """

    def __init__(self, session_id: str, last_turn_id: int):
        self.session_id = session_id
        self.turn_id = last_turn_id + 1
        self.segments: list[str] = []

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

    def _event(self, final: bool, interim: str = "") -> dict:
        text = " ".join([*self.segments, interim]).strip()
        return {"session_id": self.session_id, "turn_id": self.turn_id, "final": final, "text": text}

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

    async def commit(self, turn_id: int, text: str) -> str:
        """Commits a final transcript; returns "committed" or "duplicate".

        Retries once on a transport failure: `turn_id` makes the retry idempotent.
        """
        body = {"turn_id": turn_id, "text": text}
        try:
            result = await self._request("POST", self._path + "/transcripts", json=body)
        except VoiceFailure as failure:
            if failure.kind not in ("timeout", "disconnected"):
                raise
            result = await self._request("POST", self._path + "/transcripts", json=body)
        return result["status"]

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
        if response.status_code == 400:
            raise VoiceFailure("malformed")
        if response.status_code >= 300:
            raise VoiceFailure("disconnected")
        try:
            return response.json()
        except ValueError:
            raise VoiceFailure("malformed") from None
