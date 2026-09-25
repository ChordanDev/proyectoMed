import React, { useCallback, useEffect, useRef, useState } from "react";
import strings from "../i18n/pt-BR.json";
import "./StationScreen.css";

export interface DisplayMessage {
  role: "learner" | "patient";
  text: string;
}

export interface StationScreenProps {
  /** Send a text turn and receive the AI reply text. Returns null on failure. */
  onSend: (text: string) => Promise<string | null>;
  /** Finish the station session. */
  onFinish: () => void | Promise<void>;
  /** Whether the learner granted consent to capture and transcribe audio. */
  audioConsent?: boolean;
  /** Transcribe a captured audio blob. Returns null when voice is unavailable. */
  onTranscribe?: (audioBlob: Blob) => Promise<string | null>;
  /** Send a transcribed voice turn and receive the AI reply text. */
  onSendVoice?: (text: string) => Promise<string | null>;
  /** Optional station title for the header. */
  title?: string;
  /** External error message to display. */
  error?: string | null;
  /** Whether the send/finish controls are disabled (e.g. finishing in progress). */
  disabled?: boolean;
  /** Milliseconds left until the server-authoritative station deadline, when known. */
  remainingMs?: number | null;
  /** Transcript restored from a resumed session (refresh/reconnect). */
  initialMessages?: DisplayMessage[];
}

const isStationTimeElapsedError = (cause: unknown): boolean =>
  typeof cause === "object" &&
  cause !== null &&
  (cause as { code?: unknown }).code === "station_time_elapsed";

const formatCountdown = (remainingMs: number): string => {
  const totalSeconds = Math.max(0, Math.floor(remainingMs / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
};

export function StationScreen({
  onSend,
  onFinish,
  audioConsent = false,
  onTranscribe,
  onSendVoice,
  title,
  error = null,
  disabled = false,
  remainingMs = null,
  initialMessages,
}: StationScreenProps): React.JSX.Element {
  const [messages, setMessages] = useState<DisplayMessage[]>(
    () => initialMessages ?? [],
  );
  const [inputValue, setInputValue] = useState("");
  const [sending, setSending] = useState(false);
  const [recording, setRecording] = useState(false);
  const [transcribing, setTranscribing] = useState(false);
  const [voiceFallback, setVoiceFallback] = useState(false);
  const [sendError, setSendError] = useState<string | null>(null);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const recorderRef = useRef<MediaRecorder | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const mountedRef = useRef(true);

  const stopStream = useCallback(() => {
    streamRef.current?.getTracks().forEach((track) => track.stop());
    streamRef.current = null;
  }, []);

  const enableTextFallback = useCallback(() => {
    recorderRef.current = null;
    chunksRef.current = [];
    stopStream();
    if (mountedRef.current) {
      setRecording(false);
      setTranscribing(false);
      setVoiceFallback(true);
    }
  }, [stopStream]);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      const recorder = recorderRef.current;
      if (recorder && recorder.state !== "inactive") {
        recorder.stop();
      }
      stopStream();
    };
  }, [stopStream]);

  const browserVoiceSupported =
    typeof MediaRecorder !== "undefined" &&
    typeof navigator.mediaDevices?.getUserMedia === "function";
  const voiceRequested = audioConsent && Boolean(onTranscribe && onSendVoice);

  useEffect(() => {
    if (voiceRequested && !browserVoiceSupported) {
      enableTextFallback();
    }
  }, [browserVoiceSupported, enableTextFallback, voiceRequested]);

  const scrollToBottom = useCallback(() => {
    if (typeof messagesEndRef.current?.scrollIntoView === "function") {
      messagesEndRef.current.scrollIntoView({ behavior: "smooth" });
    }
  }, []);

  useEffect(() => {
    scrollToBottom();
  }, [messages, sending, scrollToBottom]);

  const sendTurn = useCallback(
    async (
      text: string,
      sender: (message: string) => Promise<string | null>,
    ) => {
      const learnerMessage: DisplayMessage = { role: "learner", text };
      setMessages((previous) => [...previous, learnerMessage]);
      setSending(true);
      setSendError(null);

      try {
        const replyText = await sender(text);
        if (replyText) {
          setMessages((previous) => [
            ...previous,
            { role: "patient", text: replyText },
          ]);
        } else {
          setSendError(strings.stationError);
        }
      } catch (cause) {
        if (isStationTimeElapsedError(cause)) {
          // The station's deadline elapsed while this turn was in flight:
          // it was never accepted, so it must not linger in the transcript.
          if (mountedRef.current) {
            setMessages((previous) => previous.slice(0, -1));
          }
        } else {
          setSendError(strings.stationError);
        }
      } finally {
        if (mountedRef.current) setSending(false);
      }
    },
    [],
  );

  const handleSend = useCallback(async () => {
    const trimmed = inputValue.trim();
    if (!trimmed || sending || transcribing || disabled) return;

    setInputValue("");
    await sendTurn(trimmed, onSend);
  }, [disabled, inputValue, onSend, sendTurn, sending, transcribing]);

  const startRecording = useCallback(async () => {
    if (
      !voiceRequested ||
      voiceFallback ||
      sending ||
      transcribing ||
      disabled ||
      !browserVoiceSupported
    ) {
      return;
    }

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      if (!mountedRef.current) {
        stream.getTracks().forEach((track) => track.stop());
        return;
      }

      const recorder = new MediaRecorder(stream);
      streamRef.current = stream;
      recorderRef.current = recorder;
      chunksRef.current = [];

      recorder.addEventListener("dataavailable", (event: BlobEvent) => {
        if (event.data.size > 0) chunksRef.current.push(event.data);
      });
      recorder.addEventListener("error", enableTextFallback);
      recorder.addEventListener("stop", () => {
        const audioBlob = new Blob(chunksRef.current, {
          type: recorder.mimeType || "audio/webm",
        });
        recorderRef.current = null;
        chunksRef.current = [];
        stopStream();
        if (!mountedRef.current) return;

        setRecording(false);
        setTranscribing(true);
        void (async () => {
          try {
            const text = await onTranscribe?.(audioBlob);
            if (!text) {
              enableTextFallback();
              return;
            }

            setTranscribing(false);
            await sendTurn(text, onSendVoice!);
          } catch {
            enableTextFallback();
          }
        })();
      });

      recorder.start();
      setRecording(true);
    } catch {
      enableTextFallback();
    }
  }, [
    browserVoiceSupported,
    disabled,
    onSendVoice,
    onTranscribe,
    sendTurn,
    sending,
    stopStream,
    transcribing,
    enableTextFallback,
    voiceFallback,
    voiceRequested,
  ]);

  const stopRecording = useCallback(() => {
    try {
      recorderRef.current?.stop();
    } catch {
      enableTextFallback();
    }
  }, [enableTextFallback]);

  const handleKeyDown = useCallback(
    (event: React.KeyboardEvent<HTMLInputElement>) => {
      if (event.key === "Enter" && !event.shiftKey) {
        event.preventDefault();
        void handleSend();
      }
    },
    [handleSend],
  );

  const busy = sending || transcribing;
  const isSendDisabled = disabled || busy || inputValue.trim().length === 0;
  const displayedError = error || sendError;
  const showVoiceButton =
    voiceRequested && browserVoiceSupported && !voiceFallback;

  return (
    <div className="station-screen" data-testid="station-screen">
      <header className="station-header">
        <h1 className="station-header__title">
          {title ?? strings.stationScreenTitle}
        </h1>
        {remainingMs !== null && (
          <div
            className="station-header__countdown"
            role="timer"
            aria-label={strings.timeRemainingLabel}
            data-testid="station-countdown"
          >
            {formatCountdown(remainingMs)}
          </div>
        )}
        <button
          type="button"
          className="station-header__finish-button"
          disabled={disabled || sending || recording || transcribing}
          onClick={() => void onFinish()}
          data-testid="finish-button"
        >
          {strings.finishStation}
        </button>
      </header>

      <div
        className="station-messages"
        role="log"
        aria-live="polite"
        data-testid="message-list"
      >
        {messages.map((message, index) => (
          <div
            key={index}
            className={`station-message station-message--${message.role}`}
            data-testid={`message-${message.role}`}
          >
            <div className="station-message__role">
              {message.role === "learner"
                ? strings.roleLearner
                : strings.rolePatient}
            </div>
            {message.text}
          </div>
        ))}
        <div ref={messagesEndRef} />
      </div>

      {busy && (
        <div className="station-typing" role="status" data-testid="typing-indicator">
          {transcribing ? strings.transcribingVoice : strings.sendingMessage}
        </div>
      )}

      {voiceFallback && (
        <div
          className="station-voice-fallback"
          role="status"
          data-testid="voice-fallback"
        >
          {strings.voiceFallbackNotice}
        </div>
      )}

      {displayedError && (
        <div className="station-error" role="alert" data-testid="station-error">
          {displayedError}
        </div>
      )}

      <div className="station-input-area">
        <input
          type="text"
          className="station-input-area__input"
          placeholder={strings.inputPlaceholder}
          value={inputValue}
          onChange={(event) => setInputValue(event.target.value)}
          onKeyDown={handleKeyDown}
          disabled={disabled || busy}
          data-testid="message-input"
          aria-label={strings.inputPlaceholder}
        />
        {showVoiceButton && (
          <button
            type="button"
            className={`station-input-area__voice-button${recording ? " station-input-area__voice-button--recording" : ""}`}
            disabled={disabled || busy}
            onClick={() => void (recording ? stopRecording() : startRecording())}
            data-testid="voice-button"
            aria-label={recording ? strings.stopVoiceInput : strings.startVoiceInput}
          >
            {recording ? strings.stopVoiceInput : strings.startVoiceInput}
          </button>
        )}
        <button
          type="button"
          className="station-input-area__send-button"
          disabled={isSendDisabled}
          onClick={() => void handleSend()}
          data-testid="send-button"
        >
          {sending ? strings.sendingMessage : strings.sendButton}
        </button>
      </div>
    </div>
  );
}
