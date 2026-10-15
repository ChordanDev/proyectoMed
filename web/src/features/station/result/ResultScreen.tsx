import React from "react";
import type { CriterionStatus, SessionResult } from "../api/client";
import strings from "../i18n/pt-BR.json";
import "./ResultScreen.css";

export type ResultScreenStatus = "finishing" | "finished" | "failed";

export interface ResultScreenStateProps {
  status: ResultScreenStatus;
  hasUsableFeedback: boolean;
  onRestart: () => void | Promise<void>;
  disabled?: boolean;
  errorMessage?: string;
}

export interface ResultScreenProps {
  status: ResultScreenStatus;
  result: SessionResult | null;
  onRestart: () => void | Promise<void>;
  disabled?: boolean;
  errorMessage?: string;
}

const STATUS_TEXT_MAP: Record<CriterionStatus, string> = {
  assessed: strings.criterionAssessed,
  uncertain: strings.criterionUnresolved,
  not_observable: strings.criterionNotObservable,
  not_applicable: strings.criterionExcluded,
};

// Localize punctuation only: do not parse, round or rescale exact wire points.
const displayPoints = (points: string) => points.replace(".", ",");

export function ResultScreenState({
  status,
  hasUsableFeedback,
  onRestart,
  disabled = false,
  errorMessage,
}: ResultScreenStateProps): React.JSX.Element | null {
  if (status === "finishing") {
    return (
      <section
        key="finishing"
        className="result-screen-state result-screen-state--finishing"
        role="status"
        aria-live="polite"
        aria-atomic="true"
      >
        <p className="result-screen-state__text">{strings.loadingResult}</p>
        <p className="result-screen-state__note">{strings.loadingResultFeedbackWait}</p>
      </section>
    );
  }

  if (status === "failed" || (status === "finished" && !hasUsableFeedback)) {
    return (
      <section
        key="recovery"
        className="result-screen-state result-screen-state--recovery"
        role="alert"
        aria-live="assertive"
      >
        <p className="result-screen-state__text">
          {errorMessage || strings.resultUnavailable}
        </p>
        <p className="result-screen-state__note">{strings.resultRestartDiscards}</p>
        <button
          type="button"
          className="result-screen-state__button"
          disabled={disabled}
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
  disabled = false,
  errorMessage,
}: ResultScreenProps): React.JSX.Element | null {
  const criteria = result?.criteria;
  const hasUsableFeedback = result !== null;

  if (status !== "finished" || !criteria || !result) {
    return (
      <div className="result-screen result-screen--state">
        <p className="educational-disclaimer" role="note">
          {strings.educationalDisclaimer}
        </p>
        <ResultScreenState
          status={status}
          hasUsableFeedback={hasUsableFeedback}
          onRestart={onRestart}
          disabled={disabled}
          errorMessage={errorMessage}
        />
      </div>
    );
  }

  return (
    <section className="result-screen" aria-labelledby="result-screen-title">
      <header className="result-screen__title-header">
        <h1 id="result-screen-title" className="result-screen__title">
          {strings.resultReportTitle}
        </h1>
      </header>

      <p className="educational-disclaimer" role="note">
        {strings.educationalDisclaimer}
      </p>
      {result.placeholder && <p className="result-screen__fictional">{strings.fictionalResult}</p>}
      <section aria-labelledby="result-estimates-title" className="result-screen__summary">
        <h2 id="result-estimates-title">{strings.resultCoverage}</h2>
        <ul className="result-screen__counts">
          <li>{strings.coverageAssessed}: {result.coverage.assessed}</li>
          <li>{strings.coverageUncertain}: {result.coverage.uncertain}</li>
          <li>{strings.coverageNotObservable}: {result.coverage.not_observable}</li>
          <li>{strings.coverageExcluded}: {result.coverage.not_applicable}</li>
        </ul>
        <p>{strings.resultScoredPoints}: {displayPoints(result.estimates.scored_subtotal)} {strings.resultOf} {displayPoints(result.estimates.scored_max)}</p>
        <p>{strings.resultEligibleMax}: {displayPoints(result.estimates.eligible_max)}</p>
        {result.estimates.total !== null ? (
          <p>{strings.resultTotal}: {displayPoints(result.estimates.total)}</p>
        ) : <p>{criteria.every((criterion) => criterion.status === "not_applicable") ? strings.resultNoEligible : strings.resultOpenTotal}</p>}
        {result.estimates.unresolved.length > 0 && <>
          <h3>{strings.resultUnresolvedHeading}</h3>
          <ul className="result-screen__unresolved">
            {result.estimates.unresolved.map((item) => {
              const ordinal = criteria.findIndex((criterion) => criterion.id === item.id) + 1;
              return (
                <li key={item.id}>
                  {`${strings.resultOrdinalPrefix} ${ordinal}: ${STATUS_TEXT_MAP[item.status]}`}
                </li>
              );
            })}
          </ul>
        </>}
      </section>

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
                <h2 className="result-screen__ordinal">
                  {strings.resultOrdinalPrefix} {ordinalNumber}
                </h2>
                <span
                  className={`result-screen__status result-screen__status--${criterion.status}`}
                >
                  {statusLabel}
                </span>
              </header>

              <p>{criterion.description}</p>
              {criterion.status === "assessed" && <>
                {criterion.level_description.trim() !== "" && (
                  <p>{strings.resultLevel}: {criterion.level_description}</p>
                )}
                <p>{strings.resultPoints}: {displayPoints(criterion.points)} {strings.resultOf} {displayPoints(criterion.max_points)}</p>
              </>}

              {hasEvidence ? (
                <section className="result-screen__evidence">
                  <h3 className="result-screen__evidence-heading">
                    {strings.resultEvidenceHeading}
                  </h3>
                  <ul className="result-screen__evidence-list">
                    {criterion.evidence.map((excerpt) => (
                      <li
                        key={excerpt.id}
                        className="result-screen__evidence-item"
                      >
                        <blockquote className="result-screen__evidence-quote">
                          <mark className="result-screen__evidence-highlight">
                            {excerpt.text}
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

      {errorMessage && (
        <p
          className="result-screen-state__text"
          role="alert"
          data-testid="result-error"
        >
          {errorMessage}
        </p>
      )}

      <footer className="result-screen__footer">
        <p className="result-screen__session-note">{strings.resultSessionOnly}</p>
        <button
          type="button"
          className="result-screen-state__button"
          disabled={disabled}
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
