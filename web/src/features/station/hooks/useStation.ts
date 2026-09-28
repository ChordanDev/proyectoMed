import { useCallback, useEffect, useRef, useState } from "react";
import {
  ApiError,
  fetchResult,
  finishSession,
  getImpressos,
  getSession,
  requestImpresso as requestImpressoApi,
  sendMessage,
  startSession,
  synthesizeSpeech,
  transcribeAudio,
  type FinishReason,
  type Impresso,
  type MessageReply,
  type RequestImpressoResponse,
  type SendMessageRequest,
  type Session,
  type SessionMessage,
  type SessionResult,
} from "../api/client";

export type StationStatus =
  | "idle"
  | "loading"
  | "active"
  | "finishing"
  | "finished"
  | "failed";

export interface StationApi {
  startSession: typeof startSession;
  getSession: typeof getSession;
  sendMessage: typeof sendMessage;
  finishSession: typeof finishSession;
  fetchResult: typeof fetchResult;
  transcribeAudio: typeof transcribeAudio;
  synthesizeSpeech: typeof synthesizeSpeech;
  requestImpresso: typeof requestImpressoApi;
  getImpressos: typeof getImpressos;
}

const defaultApi: StationApi = {
  startSession,
  getSession,
  sendMessage,
  finishSession,
  fetchResult,
  transcribeAudio,
  synthesizeSpeech,
  requestImpresso: requestImpressoApi,
  getImpressos,
};

const unknownErrorMessage =
  "A estação não pôde ser concluída. Você pode reiniciar.";

const unknownImpressoErrorMessage =
  "Não foi possível solicitar o impresso. Tente novamente.";

// A tick close to the deadline is deliberately more frequent than the
// server's own ~2s early-finish tolerance, so the client rarely needs a
// deadline_not_reached resync round trip.
const countdownTickMs = 250;

// Exported for tests only; production code never reads this literal directly.
export const sessionIdStorageKey = "revalida.station.sessionId";

const readPersistedSessionId = (): string | null => {
  try {
    return sessionStorage.getItem(sessionIdStorageKey);
  } catch {
    return null;
  }
};

const persistSessionId = (sessionId: string): void => {
  try {
    sessionStorage.setItem(sessionIdStorageKey, sessionId);
  } catch {
    // Best effort only: refresh/reconnect resume is a convenience, not a guarantee.
  }
};

const clearPersistedSessionId = (): void => {
  try {
    sessionStorage.removeItem(sessionIdStorageKey);
  } catch {
    // Ignore: nothing to clean up if storage is unavailable.
  }
};

interface ClockAnchor {
  serverNowMs: number;
  perfAnchor: number;
}

export const useStation = (api: StationApi = defaultApi) => {
  const [status, setStatus] = useState<StationStatus>("idle");
  const [result, setResult] = useState<SessionResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [audioConsent, setAudioConsent] = useState(false);
  const [deadlineAtMs, setDeadlineAtMs] = useState<number | null>(null);
  const [remainingMs, setRemainingMs] = useState<number | null>(null);
  const [initialMessages, setInitialMessages] = useState<SessionMessage[]>([]);
  const [impressos, setImpressos] = useState<Impresso[]>([]);
  const [impressoError, setImpressoError] = useState<string | null>(null);
  const sessionRef = useRef<Session | null>(null);
  const hasStartedRef = useRef(false);
  const isFinishingRef = useRef(false);
  const pendingSendRef = useRef<Promise<MessageReply | null> | null>(null);
  const pendingSendTokenRef = useRef<object | null>(null);
  const clockAnchorRef = useRef<ClockAnchor | null>(null);
  const timerFinishTriggeredRef = useRef(false);

  const anchorClock = useCallback((serverNowIso: string) => {
    clockAnchorRef.current = {
      serverNowMs: Date.parse(serverNowIso),
      perfAnchor: performance.now(),
    };
  }, []);

  const fail = useCallback((cause: unknown) => {
    sessionRef.current = null;
    hasStartedRef.current = false;
    isFinishingRef.current = false;
    pendingSendRef.current = null;
    pendingSendTokenRef.current = null;
    clockAnchorRef.current = null;
    timerFinishTriggeredRef.current = false;
    setDeadlineAtMs(null);
    clearPersistedSessionId();
    setImpressoError(null);
    setError(cause instanceof ApiError ? cause.message : unknownErrorMessage);
    setStatus("failed");
  }, []);

  const reset = useCallback(() => {
    sessionRef.current = null;
    hasStartedRef.current = false;
    isFinishingRef.current = false;
    pendingSendRef.current = null;
    pendingSendTokenRef.current = null;
    clockAnchorRef.current = null;
    timerFinishTriggeredRef.current = false;
    clearPersistedSessionId();
    setDeadlineAtMs(null);
    setInitialMessages([]);
    setImpressos([]);
    setImpressoError(null);
    setError(null);
    setResult(null);
    setStatus("idle");
    setAudioConsent(false);
  }, []);

  const start = useCallback(
    async (consent: boolean): Promise<void> => {
      if (hasStartedRef.current) return;

      hasStartedRef.current = true;
      isFinishingRef.current = false;
      pendingSendRef.current = null;
      pendingSendTokenRef.current = null;
      timerFinishTriggeredRef.current = false;
      setAudioConsent(consent);
      setError(null);
      setResult(null);
      setInitialMessages([]);
      setImpressos([]);
      setImpressoError(null);
      setStatus("loading");
      try {
        const session = await api.startSession({ audio_consent: consent });
        sessionRef.current = session;
        anchorClock(session.server_now);
        setDeadlineAtMs(Date.parse(session.deadline_at));
        persistSessionId(session.session_id);
        setStatus("active");
      } catch (cause) {
        fail(cause);
      }
    },
    [anchorClock, api, fail],
  );

  const finish = useCallback(
    async (reason: FinishReason = "user"): Promise<void> => {
      const session = sessionRef.current;
      if (!session || isFinishingRef.current) return;

      isFinishingRef.current = true;
      setStatus("finishing");

      const pendingSend = pendingSendRef.current;
      if (pendingSend) {
        // A pending send can itself reject (e.g. station_time_elapsed); we
        // only need it to settle before finishing, not to propagate here.
        await pendingSend.catch(() => null);
      }
      if (sessionRef.current !== session || !isFinishingRef.current) return;

      try {
        await api.finishSession(session.session_id, reason);
        const stationResult = await api.fetchResult(session.session_id);
        clearPersistedSessionId();
        setResult(stationResult);
        setStatus("finished");
      } catch (cause) {
        if (
          reason === "timer" &&
          cause instanceof ApiError &&
          cause.code === "deadline_not_reached"
        ) {
          // Client clock ran ahead of the server's: resync the deadline from
          // the server and let the next countdown tick retry once the
          // recomputed remaining time actually reaches zero.
          isFinishingRef.current = false;
          timerFinishTriggeredRef.current = false;
          setStatus("active");
          try {
            const refreshed = await api.getSession(session.session_id);
            if (sessionRef.current === session) {
              sessionRef.current = refreshed;
              anchorClock(refreshed.server_now);
              setDeadlineAtMs(Date.parse(refreshed.deadline_at));
            }
          } catch {
            // Ignore resync failure; the existing deadline will be retried.
          }
          return;
        }

        fail(cause);
      }
    },
    [anchorClock, api, fail],
  );

  const send = useCallback(
    (message: SendMessageRequest): Promise<MessageReply | null> => {
      const session = sessionRef.current;
      if (
        !session ||
        isFinishingRef.current ||
        pendingSendRef.current !== null
      ) {
        return Promise.resolve(null);
      }

      const sendToken = {};
      pendingSendTokenRef.current = sendToken;
      const pendingSend = (async () => {
        try {
          const messageReply = await api.sendMessage(
            session.session_id,
            message,
          );
          if (sessionRef.current !== session) return null;
          anchorClock(messageReply.server_now);
          return messageReply;
        } catch (cause) {
          if (sessionRef.current !== session) return null;

          if (cause instanceof ApiError && cause.code === "station_time_elapsed") {
            if (!timerFinishTriggeredRef.current) {
              timerFinishTriggeredRef.current = true;
              void finish("timer");
            }
            throw cause;
          }

          fail(cause);
          return null;
        } finally {
          if (pendingSendTokenRef.current === sendToken) {
            pendingSendRef.current = null;
            pendingSendTokenRef.current = null;
          }
        }
      })();

      pendingSendRef.current = pendingSend;
      return pendingSend;
    },
    [anchorClock, api, fail, finish],
  );

  const transcribe = useCallback(
    async (audioBlob: Blob, filename?: string): Promise<string | null> => {
      const session = sessionRef.current;
      if (!session || !session.audio_consent || isFinishingRef.current) {
        return null;
      }

      try {
        const transcription = await api.transcribeAudio(
          session.session_id,
          audioBlob,
          filename,
        );
        if (sessionRef.current !== session || isFinishingRef.current) {
          return null;
        }

        const text = transcription.text.trim();
        return text.length > 0 ? text : null;
      } catch {
        return null;
      }
    },
    [api],
  );

  const synthesize = useCallback(
    async (text: string): Promise<Blob | null> => {
      const session = sessionRef.current;
      if (!session || !session.audio_consent || isFinishingRef.current) {
        return null;
      }

      try {
        const audioBlob = await api.synthesizeSpeech(
          session.session_id,
          text,
        );
        if (sessionRef.current !== session || isFinishingRef.current) {
          return null;
        }

        return audioBlob;
      } catch {
        return null;
      }
    },
    [api],
  );

  const requestImpresso = useCallback(
    async (text: string): Promise<RequestImpressoResponse | null> => {
      const session = sessionRef.current;
      if (!session || isFinishingRef.current) return null;

      try {
        const response = await api.requestImpresso(session.session_id, {
          text,
        });
        if (sessionRef.current !== session) return null;

        setImpressos(response.released_impressos);
        setImpressoError(null);
        return response;
      } catch (cause) {
        if (sessionRef.current !== session) return null;

        setImpressoError(
          cause instanceof ApiError ? cause.message : unknownImpressoErrorMessage,
        );
        return null;
      }
    },
    [api],
  );

  // Resume an in-progress (or just-completed) session after a refresh or
  // reconnect, from the session id persisted in sessionStorage.
  useEffect(() => {
    const savedSessionId = readPersistedSessionId();
    if (!savedSessionId || hasStartedRef.current) return;

    let cancelled = false;
    hasStartedRef.current = true;
    setStatus("loading");

    void (async () => {
      try {
        const detail = await api.getSession(savedSessionId);
        if (cancelled) return;

        sessionRef.current = detail;
        setAudioConsent(detail.audio_consent);
        anchorClock(detail.server_now);
        setDeadlineAtMs(Date.parse(detail.deadline_at));

        if (detail.status === "completed") {
          setStatus("finishing");
          try {
            const stationResult = await api.fetchResult(detail.session_id);
            if (cancelled) return;
            clearPersistedSessionId();
            setResult(stationResult);
            setStatus("finished");
          } catch (cause) {
            if (!cancelled) fail(cause);
          }
          return;
        }

        timerFinishTriggeredRef.current = false;
        setInitialMessages(detail.messages);
        setStatus("active");

        // Best effort: restore documents released before the refresh so
        // they remain visible; a failure here does not block resume.
        try {
          const impressosResponse = await api.getImpressos(detail.session_id);
          if (!cancelled) setImpressos(impressosResponse.released_impressos);
        } catch {
          // Ignore: the impressos drawer will simply start out empty.
        }
      } catch (cause) {
        if (cancelled) return;
        // An unknown/expired/not-found session cannot be resumed: clear the
        // stale pointer and fall back to a fresh idle start.
        clearPersistedSessionId();
        hasStartedRef.current = false;
        sessionRef.current = null;
        setStatus("idle");
        void cause;
      }
    })();

    return () => {
      cancelled = true;
      // Undo the started flag so a StrictMode remount can retry the resume;
      // a real unmount discards the component anyway.
      hasStartedRef.current = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Derive the countdown from the anchored server clock every tick, so
  // rerenders never reset or extend it, and trigger the exactly-once timer
  // finish when it reaches zero.
  useEffect(() => {
    if (deadlineAtMs === null || status !== "active") {
      setRemainingMs(null);
      return;
    }

    const tick = () => {
      const anchor = clockAnchorRef.current;
      if (!anchor) return;

      const estimatedServerNowMs =
        anchor.serverNowMs + (performance.now() - anchor.perfAnchor);
      const remaining = Math.max(0, deadlineAtMs - estimatedServerNowMs);
      setRemainingMs(remaining);

      if (remaining <= 0 && !timerFinishTriggeredRef.current) {
        timerFinishTriggeredRef.current = true;
        void finish("timer");
      }
    };

    tick();
    const intervalId = setInterval(tick, countdownTickMs);
    return () => clearInterval(intervalId);
  }, [deadlineAtMs, status, finish]);

  return {
    start,
    send,
    transcribe,
    synthesize,
    requestImpresso,
    finish,
    reset,
    result,
    status,
    error,
    audioConsent,
    remainingMs,
    initialMessages,
    impressos,
    impressoError,
  };
};
