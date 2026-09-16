import { useCallback, useRef, useState } from "react";
import {
  ApiError,
  fetchResult,
  finishSession,
  sendMessage,
  startSession,
  type FinishReason,
  type MessageReply,
  type SendMessageRequest,
  type Session,
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
  sendMessage: typeof sendMessage;
  finishSession: typeof finishSession;
  fetchResult: typeof fetchResult;
}

const defaultApi: StationApi = {
  startSession,
  sendMessage,
  finishSession,
  fetchResult,
};

const unknownErrorMessage =
  "A estação não pôde ser concluída. Você pode reiniciar.";

export const useStation = (api: StationApi = defaultApi) => {
  const [status, setStatus] = useState<StationStatus>("idle");
  const [result, setResult] = useState<SessionResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [audioConsent, setAudioConsent] = useState(false);
  const sessionRef = useRef<Session | null>(null);
  const hasStartedRef = useRef(false);
  const isFinishingRef = useRef(false);

  const fail = useCallback((cause: unknown) => {
    sessionRef.current = null;
    hasStartedRef.current = false;
    isFinishingRef.current = false;
    setError(cause instanceof ApiError ? cause.message : unknownErrorMessage);
    setStatus("failed");
  }, []);

  const start = useCallback(
    async (consent: boolean): Promise<void> => {
      if (hasStartedRef.current) return;

      hasStartedRef.current = true;
      isFinishingRef.current = false;
      setAudioConsent(consent);
      setError(null);
      setResult(null);
      setStatus("loading");
      try {
        sessionRef.current = await api.startSession({ audio_consent: consent });
        setStatus("active");
      } catch (cause) {
        fail(cause);
      }
    },
    [api, fail],
  );

  const send = useCallback(
    async (message: SendMessageRequest): Promise<MessageReply | null> => {
      const session = sessionRef.current;
      if (!session || isFinishingRef.current) return null;

      try {
        const messageReply = await api.sendMessage(session.session_id, message);
        return sessionRef.current === session && !isFinishingRef.current
          ? messageReply
          : null;
      } catch (cause) {
        if (sessionRef.current !== session || isFinishingRef.current) {
          return null;
        }

        fail(cause);
        return null;
      }
    },
    [api, fail],
  );

  const finish = useCallback(
    async (reason: FinishReason = "user"): Promise<void> => {
      const session = sessionRef.current;
      if (!session || isFinishingRef.current) return;

      isFinishingRef.current = true;
      setStatus("finishing");

      try {
        await api.finishSession(session.session_id, reason);
        const stationResult = await api.fetchResult(session.session_id);
        setResult(stationResult);
        setStatus("finished");
      } catch (cause) {
        fail(cause);
      }
    },
    [api, fail],
  );

  return {
    start,
    send,
    finish,
    result,
    status,
    error,
    audioConsent,
  };
};
