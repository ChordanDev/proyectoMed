import React, { useCallback, useState } from "react";
import {
  BriefScreen,
  NoticeScreen,
  StationScreen,
  ResultScreen,
  useActiveStation,
  useStation,
  type ResultScreenStatus,
} from "./features/station";
import strings from "./features/station/i18n/pt-BR.json";
import "./index.css";

export default function App(): React.JSX.Element {
  const station = useStation();
  const activeStation = useActiveStation();
  // Consent given on the notice; the brief screen shows until the learner enters.
  const [pendingConsent, setPendingConsent] = useState<boolean | null>(null);
  const title = activeStation.station?.display_title;
  const brief = activeStation.station?.candidate_brief ?? null;
  // One voice experience per deployment (VOICE_MODE, #270).
  const voiceMode = activeStation.station?.voice_mode ?? "turn";

  const handleEnter = useCallback(() => {
    if (pendingConsent === null) return;
    void station.start(pendingConsent);
  }, [station, pendingConsent]);

  const sendMessage = useCallback(
    async (
      text: string,
      modality: "text" | "voice",
    ): Promise<string | null> => {
      const reply = await station.send({
        role: "learner",
        modality,
        text,
      });
      return reply?.reply_text ?? null;
    },
    [station],
  );

  const handleSend = useCallback(
    (text: string) => sendMessage(text, "text"),
    [sendMessage],
  );

  const handleSendVoice = useCallback(
    (text: string) => sendMessage(text, "voice"),
    [sendMessage],
  );

  const handleFinish = useCallback(() => {
    void station.finish("user");
  }, [station]);

  const handleRestart = useCallback(async () => {
    await station.reset();
    setPendingConsent(null);
  }, [station]);

  // Flow: notice → brief → station → result
  if (station.status === "idle" || station.status === "loading") {
    return (
      <main className="app-root">
        {station.status === "loading" ? (
          <p role="status">{strings.loadingStation}</p>
        ) : pendingConsent === null ? (
          <NoticeScreen
            onStart={setPendingConsent}
            voiceSupport={voiceMode !== "off"}
          />
        ) : (
          <BriefScreen
            title={title}
            brief={brief}
            error={activeStation.error}
            onEnter={handleEnter}
          />
        )}
      </main>
    );
  }

  if (station.status === "finished" || station.status === "finishing") {
    const resultStatus: ResultScreenStatus =
      station.status === "finishing" ? "finishing" : "finished";
    return (
      <main className="app-root">
        <ResultScreen
          status={resultStatus}
          result={station.result}
          onRestart={handleRestart}
          disabled={station.isResetting}
          errorMessage={station.error ?? undefined}
        />
      </main>
    );
  }

  if (station.status === "failed") {
    return (
      <main className="app-root">
        <ResultScreen
          status="failed"
          result={null}
          errorMessage={station.error ?? undefined}
          onRestart={handleRestart}
          disabled={station.isResetting}
        />
      </main>
    );
  }

  // station.status === "active"
  const timeElapsed = station.remainingMs !== null && station.remainingMs <= 0;
  const voice = station.audioConsent && voiceMode !== "off";
  const turnVoice = voice && voiceMode === "turn";
  return (
    <main className="app-root">
      <StationScreen
        title={title}
        brief={brief}
        onSend={handleSend}
        onFinish={handleFinish}
        audioConsent={voice}
        onTranscribe={turnVoice ? station.transcribe : undefined}
        onSendVoice={turnVoice ? handleSendVoice : undefined}
        onSynthesize={turnVoice ? station.synthesize : undefined}
        realtimeVoice={
          voice && voiceMode === "realtime"
            ? { sessionId: station.sessionId }
            : undefined
        }
        onFetchTranscript={station.fetchTranscript}
        error={station.error}
        disabled={timeElapsed}
        remainingMs={station.remainingMs}
        initialMessages={station.initialMessages}
        onRequestImpresso={station.requestImpresso}
        onRefreshImpressos={station.refreshImpressos}
        impressos={station.impressos}
        impressoError={station.impressoError}
      />
    </main>
  );
}
