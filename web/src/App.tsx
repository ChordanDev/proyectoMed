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

  const handleSend = useCallback(
    async (text: string): Promise<string | null> => {
      const reply = await station.send({
        role: "learner",
        modality: "text",
        text,
      });
      return reply?.reply_text ?? null;
    },
    [station],
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
          <NoticeScreen onStart={handleStart} voiceSupport={false} />
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
  return (
    <main className="app-root">
      <StationScreen
        onSend={handleSend}
        onFinish={handleFinish}
        error={station.error}
      />
    </main>
  );
}
