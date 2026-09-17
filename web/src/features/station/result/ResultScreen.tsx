import React from "react";
import strings from "../../../i18n/pt-BR.json";
import "./ResultScreen.css";

export type ResultScreenStatus = "finishing" | "finished" | "failed";

export interface ResultScreenStateProps {
  status: ResultScreenStatus;
  hasUsableFeedback: boolean;
  onRestart: () => void | Promise<void>;
}

export function ResultScreenState({
  status,
  hasUsableFeedback,
  onRestart,
}: ResultScreenStateProps): React.JSX.Element | null {
  if (status === "finishing") {
    return (
      <section
        className="result-screen-state result-screen-state--finishing"
        role="status"
        aria-live="polite"
        aria-atomic="true"
      >
        <p className="result-screen-state__text">{strings.loadingResult}</p>
      </section>
    );
  }

  if (status === "failed" || (status === "finished" && !hasUsableFeedback)) {
    return (
      <section
        className="result-screen-state result-screen-state--recovery"
        role="alert"
        aria-live="assertive"
      >
        <p className="result-screen-state__text">{strings.resultUnavailable}</p>
        <button
          type="button"
          className="result-screen-state__button"
          onClick={() => {
            void onRestart();
          }}
        >
          {strings.resultRestartButton}
        </button>
      </section>
    );
  }

  return null;
}
