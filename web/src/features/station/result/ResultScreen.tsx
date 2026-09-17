import React from "react";
import type { CriterionStatus, SessionResult } from "../../../api/client";
import strings from "../../../i18n/pt-BR.json";
import "./ResultScreen.css";

export type ResultScreenStatus = "finishing" | "finished" | "failed";

export interface ResultScreenStateProps {
  status: ResultScreenStatus;
  hasUsableFeedback: boolean;
  onRestart: () => void | Promise<void>;
}

export interface ResultScreenProps {
  status: ResultScreenStatus;
  result: SessionResult | null;
  onRestart: () => void | Promise<void>;
}

const STATUS_TEXT_MAP: Record<CriterionStatus, string> = {
  met: strings.criterionMet,
  omitted: strings.criterionOmitted,
  uncertain: strings.criterionUncertain,
};

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

export function ResultScreen({
  status,
  result,
  onRestart,
}: ResultScreenProps): React.JSX.Element | null {
  const criteria = result?.criteria;
  const hasUsableFeedback = Boolean(criteria && criteria.length > 0);

  if (status !== "finished" || !criteria || criteria.length === 0) {
    return (
      <ResultScreenState
        status={status}
        hasUsableFeedback={hasUsableFeedback}
        onRestart={onRestart}
      />
    );
  }

  return (
    <section className="result-screen" aria-labelledby="result-screen-title">
      <header className="result-screen__title-header">
        <h1 id="result-screen-title" className="result-screen__title">
          {strings.resultReportTitle}
        </h1>
      </header>

      <ol className="result-screen__list">
        {criteria.map((criterion, index) => {
          const ordinalNumber = index + 1;
          const statusLabel = STATUS_TEXT_MAP[criterion.status];
          const hasEvidence =
            Boolean(criterion.evidence) && criterion.evidence.length > 0;

          return (
            <li
              key={criterion.id}
              data-criterion-id={criterion.id}
              className="result-screen__item"
            >
              <header className="result-screen__item-header">
                <span className="result-screen__ordinal">
                  {strings.resultOrdinalPrefix} {ordinalNumber}
                </span>
                <span
                  className={`result-screen__status result-screen__status--${criterion.status}`}
                  aria-label={`${strings.resultStatusPrefix} ${statusLabel}`}
                >
                  {statusLabel}
                </span>
              </header>

              {hasEvidence ? (
                <section className="result-screen__evidence">
                  <h3 className="result-screen__evidence-heading">
                    {strings.resultEvidenceHeading}
                  </h3>
                  <ul className="result-screen__evidence-list">
                    {criterion.evidence.map((excerpt, excerptIndex) => (
                      <li
                        key={excerptIndex}
                        className="result-screen__evidence-item"
                      >
                        <blockquote className="result-screen__evidence-quote">
                          <mark className="result-screen__evidence-highlight">
                            {excerpt}
                          </mark>
                        </blockquote>
                      </li>
                    ))}
                  </ul>
                </section>
              ) : null}

              <section className="result-screen__recommendation">
                <h3 className="result-screen__recommendation-heading">
                  {strings.resultRecommendationHeading}
                </h3>
                <p className="result-screen__recommendation-text">
                  {criterion.recommendation}
                </p>
              </section>
            </li>
          );
        })}
      </ol>

      <footer className="result-screen__footer">
        <button
          type="button"
          className="result-screen-state__button"
          onClick={() => {
            void onRestart();
          }}
        >
          {strings.resultRestartButton}
        </button>
      </footer>
    </section>
  );
}
