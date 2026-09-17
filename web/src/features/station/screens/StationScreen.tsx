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
  /** Optional station title for the header. */
  title?: string;
  /** External error message to display. */
  error?: string | null;
  /** Whether the send/finish controls are disabled (e.g. finishing in progress). */
  disabled?: boolean;
}

export function StationScreen({
  onSend,
  onFinish,
  title,
  error = null,
  disabled = false,
}: StationScreenProps): React.JSX.Element {
  const [messages, setMessages] = useState<DisplayMessage[]>([]);
  const [inputValue, setInputValue] = useState("");
  const [sending, setSending] = useState(false);
  const [sendError, setSendError] = useState<string | null>(null);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  const scrollToBottom = useCallback(() => {
    if (typeof messagesEndRef.current?.scrollIntoView === "function") {
      messagesEndRef.current.scrollIntoView({ behavior: "smooth" });
    }
  }, []);

  useEffect(() => {
    scrollToBottom();
  }, [messages, sending, scrollToBottom]);

  const handleSend = useCallback(async () => {
    const trimmed = inputValue.trim();
    if (!trimmed || sending || disabled) return;

    const learnerMessage: DisplayMessage = { role: "learner", text: trimmed };
    setMessages((prev) => [...prev, learnerMessage]);
    setInputValue("");
    setSending(true);
    setSendError(null);

    try {
      const replyText = await onSend(trimmed);

      if (replyText) {
        const patientMessage: DisplayMessage = {
          role: "patient",
          text: replyText,
        };
        setMessages((prev) => [...prev, patientMessage]);
      } else {
        setSendError(strings.stationError);
      }
    } catch {
      setSendError(strings.stationError);
    } finally {
      setSending(false);
    }
  }, [inputValue, sending, disabled, onSend]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLInputElement>) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        void handleSend();
      }
    },
    [handleSend],
  );

  const isSendDisabled = disabled || sending || inputValue.trim().length === 0;
  const displayedError = error || sendError;

  return (
    <div className="station-screen" data-testid="station-screen">
      {/* Header with title and finish button */}
      <header className="station-header">
        <h1 className="station-header__title">
          {title ?? strings.stationScreenTitle}
        </h1>
        <button
          type="button"
          className="station-header__finish-button"
          disabled={disabled || sending}
          onClick={() => {
            void onFinish();
          }}
          data-testid="finish-button"
        >
          {strings.finishStation}
        </button>
      </header>

      {/* Message list */}
      <div
        className="station-messages"
        role="log"
        aria-live="polite"
        data-testid="message-list"
      >
        {messages.map((msg, index) => (
          <div
            key={index}
            className={`station-message station-message--${msg.role}`}
            data-testid={`message-${msg.role}`}
          >
            <div className="station-message__role">
              {msg.role === "learner" ? strings.roleLearner : strings.rolePatient}
            </div>
            {msg.text}
          </div>
        ))}

        <div ref={messagesEndRef} />
      </div>

      {sending && (
        <div
          className="station-typing"
          role="status"
          data-testid="typing-indicator"
        >
          {strings.sendingMessage}
        </div>
      )}

      {displayedError && (
        <div className="station-error" role="alert" data-testid="station-error">
          {displayedError}
        </div>
      )}

      {/* Input area */}
      <div className="station-input-area">
        <input
          type="text"
          className="station-input-area__input"
          placeholder={strings.inputPlaceholder}
          value={inputValue}
          onChange={(e) => setInputValue(e.target.value)}
          onKeyDown={handleKeyDown}
          disabled={disabled || sending}
          data-testid="message-input"
          aria-label={strings.inputPlaceholder}
        />
        <button
          type="button"
          className="station-input-area__send-button"
          disabled={isSendDisabled}
          onClick={() => {
            void handleSend();
          }}
          data-testid="send-button"
        >
          {sending ? strings.sendingMessage : strings.sendButton}
        </button>
      </div>
    </div>
  );
}
