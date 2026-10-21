import React from "react";
import { createVoiceSession } from "../api/client";
import {
  useVoiceSession,
  type VoiceRoom,
  type VoiceSessionApi,
  type VoiceSessionStatus,
} from "../hooks/useVoiceSession";
import type { VoiceTranscriptEvent } from "../hooks/voiceTranscriptEvents";
import strings from "../i18n/pt-BR.json";

const defaultApi: VoiceSessionApi = { createVoiceSession };

export interface VoicePanelProps {
  sessionId: string | null;
  active: boolean;
  api?: VoiceSessionApi;
  createRoom?: () => VoiceRoom;
  /** Receives the voice worker's transcript events (#270). */
  onTranscriptEvent?: (event: VoiceTranscriptEvent) => void;
}

const statusText: Record<VoiceSessionStatus, string> = {
  idle: strings.voiceStatusIdle,
  requesting: strings.voiceStatusRequesting,
  connecting: strings.voiceStatusConnecting,
  connected: strings.voiceStatusConnected,
  reconnecting: strings.voiceStatusReconnecting,
  disconnected: strings.voiceStatusDisconnected,
  failed: strings.voiceStatusFailed,
};

const connectedStatuses = new Set<VoiceSessionStatus>([
  "connected",
  "reconnecting",
]);
const pendingStatuses = new Set<VoiceSessionStatus>([
  "requesting",
  "connecting",
]);

export function VoicePanel({
  sessionId,
  active,
  api = defaultApi,
  createRoom,
  onTranscriptEvent,
}: VoicePanelProps): React.JSX.Element {
  const { status, error, connect, disconnect, attachAudioElement } =
    useVoiceSession({ api, sessionId, active, createRoom, onTranscriptEvent });

  const isConnected = connectedStatuses.has(status);
  const isPending = pendingStatuses.has(status);

  const handleClick = () => {
    if (isConnected) {
      disconnect();
    } else {
      void connect();
    }
  };

  return (
    <div className="voice-panel" data-testid="voice-panel">
      <p data-testid="voice-status">{statusText[status]}</p>
      {status === "connected" && (
        <p data-testid="voice-mic-indicator">{strings.voiceMicOnIndicator}</p>
      )}
      {error && <p data-testid="voice-error">{error.message}</p>}
      <button
        type="button"
        data-testid="voice-toggle-button"
        onClick={handleClick}
        disabled={isPending || !active}
      >
        {isConnected ? strings.voiceDisconnectButton : strings.voiceConnectButton}
      </button>
      {/* eslint-disable-next-line jsx-a11y/media-has-caption -- live remote patient audio has no track to caption */}
      <audio ref={attachAudioElement} autoPlay data-testid="voice-audio" />
    </div>
  );
}
