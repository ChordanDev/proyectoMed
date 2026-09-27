import React from "react";
import { useStation } from "../hooks/useStation";
import strings from "../i18n/pt-BR.json";
import { NoticeScreen } from "./NoticeScreen";
import { VoicePanel } from "./VoicePanel";

/** Thin feature composition: notice consent, start a station session, then
 * either the LiveKit voice panel (audio consent given) or a text-only
 * notice, wired for manual end-to-end testing of #117. */
export function StationSession(): React.JSX.Element {
  const { start, finish, status, audioConsent, sessionId } = useStation();

  if (status === "active" || status === "finishing" || status === "finished") {
    return (
      <>
        {audioConsent ? (
          <VoicePanel sessionId={sessionId} active={status === "active"} />
        ) : (
          <p data-testid="voice-off-notice">{strings.voiceOffNotice}</p>
        )}
        <button
          type="button"
          data-testid="finish-button"
          disabled={status !== "active"}
          onClick={() => void finish("user")}
        >
          {strings.finishStationButton}
        </button>
      </>
    );
  }

  return <NoticeScreen onStart={start} />;
}
