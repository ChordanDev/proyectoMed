import { useCallback, useRef, useState } from "react";
import {
  ApiError,
  fetchResult,
  finishSession,
  sendMessage,
  startSession,
  transcribeAudio,
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
  transcribeAudio: typeof transcribeAudio;
}

const defaultApi: StationApi = {
  startSession,
  sendMessage,
  finishSession,
  fetchResult,
  transcribeAudio,
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
  const pendingSendRef = useRef<Promise<MessageReply | null> | null>(null);
  const pendingSendTokenRef = useRef<object | null>(null);

  const fail = useCallback((cause: unknown) => {
    sessionRef.current = null;
    hasStartedRef.current = false;
    isFinishingRef.current = false;
    pendingSendRef.current = null;
    pendingSendTokenRef.current = null;
    setError(cause instanceof ApiError ? cause.message : unknownErrorMessage);
    setStatus("failed");
  }, []);

  const reset = useCallback(() => {
    sessionRef.current = null;
    hasStartedRef.current = false;
    isFinishingRef.current = false;
    pendingSendRef.current = null;
    pendingSendTokenRef.current = null;
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
          return sessionRef.current === session ? messageReply : null;
        } catch (cause) {
          if (sessionRef.current === session) fail(cause);
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
    [api, fail],
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

  const finish = useCallback(
    async (reason: FinishReason = "user"): Promise<void> => {
      const session = sessionRef.current;
      if (!session || isFinishingRef.current) return;

      isFinishingRef.current = true;
      setStatus("finishing");

      const pendingSend = pendingSendRef.current;
      if (pendingSend) await pendingSend;
      if (sessionRef.current !== session || !isFinishingRef.current) return;

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
    transcribe,
    finish,
    reset,
    result,
    status,
    error,
    audioConsent,
  };
};
