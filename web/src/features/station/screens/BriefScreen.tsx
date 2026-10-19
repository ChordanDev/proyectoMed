import React from "react";
import type { CandidateBrief } from "../api/client";
import strings from "../i18n/pt-BR.json";
import { StationBrief } from "./StationBrief";

export interface BriefScreenProps {
  /** Station title (`display_title`); falls back to the generic title. */
  title?: string;
  /** The candidate brief, or null while it loads or after it failed. */
  brief: CandidateBrief | null;
  /** pt-BR notice when the brief could not be loaded. */
  error?: string | null;
  /** Starts the station (and its timer). */
  onEnter: () => void;
  disabled?: boolean;
}

/**
 * Shows the "cenário de atuação" and the tasks before the timer starts, as in
 * the Revalida practical exam. The learner can still start when the brief
 * could not be loaded.
 */
export function BriefScreen({
  title,
  brief,
  error = null,
  onEnter,
  disabled = false,
}: BriefScreenProps): React.JSX.Element {
  return (
    <div className="notice-screen brief-screen" data-testid="brief-screen">
      <h1 className="notice-title">{title ?? strings.stationScreenTitle}</h1>
      <p className="notice-body">{strings.briefScreenHeading}</p>
      {brief ? (
        <StationBrief brief={brief} />
      ) : error ? (
        <p role="alert">{error}</p>
      ) : (
        <p role="status">{strings.briefLoading}</p>
      )}
      <p className="brief-screen__timer-note">{strings.briefTimerNote}</p>
      <button
        type="button"
        className="notice-button"
        disabled={disabled}
        onClick={onEnter}
        data-testid="brief-enter-button"
      >
        {strings.briefEnterButton}
      </button>
    </div>
  );
}
