import React, { useCallback } from "react";
import {
  NoticeScreen,
  StationScreen,
  ResultScreen,
  useStation,
  type ResultScreenStatus,
} from "./features/station";
import strings from "./features/station/i18n/pt-BR.json";
import "./index.css";

export default function App(): React.JSX.Element {
  const station = useStation();

  const handleStart = useCallback(
    (consent: boolean) => {
      void station.start(consent);
    },
    [station],
  );

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

  const handleRestart = useCallback(() => {
    station.reset();
  }, [station]);

  // Flow: notice → station → result
  if (station.status === "idle" || station.status === "loading") {
    return (
      <main className="app-root">
        {station.status === "loading" ? (
          <p role="status">{strings.loadingStation}</p>
        ) : (
          <NoticeScreen onStart={handleStart} voiceSupport />
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
        />
      </main>
    );
  }

  // station.status === "active"
  const timeElapsed = station.remainingMs !== null && station.remainingMs <= 0;
  return (
    <main className="app-root">
      <StationScreen
        onSend={handleSend}
        onFinish={handleFinish}
        audioConsent={station.audioConsent}
        onTranscribe={station.transcribe}
        onSendVoice={handleSendVoice}
        onSynthesize={station.synthesize}
        error={station.error}
        disabled={timeElapsed}
        remainingMs={station.remainingMs}
        initialMessages={station.initialMessages}
        onRequestImpresso={station.requestImpresso}
        impressos={station.impressos}
        impressoError={station.impressoError}
      />
    </main>
  );
}
