import React, { useState } from "react";
import strings from "../i18n/pt-BR.json";

export interface NoticeScreenProps {
  onStart: (consent: boolean) => void | Promise<void>;
  voiceSupport?: boolean;
}

export function NoticeScreen({
  onStart,
  voiceSupport = true,
}: NoticeScreenProps): React.JSX.Element {
  const [consentChecked, setConsentChecked] = useState(false);

  const isButtonDisabled = voiceSupport && !consentChecked;

  const handleClick = () => {
    if (isButtonDisabled) return;
    void onStart(voiceSupport ? true : false);
  };

  const handleCheckboxChange = () => {
    setConsentChecked((prev) => !prev);
  };

  return (
    <div className="notice-screen" data-testid="notice-screen-scroll">
      {/* Educational notice */}
      <h1 className="notice-title">{strings.noticeTitle}</h1>
      <p className="notice-body">{strings.noticeBody}</p>

      {/* Audio disclosure + consent (voice only) */}
      {voiceSupport && (
        <div className="disclosure-block">
          <p className="disclosure">{strings.audioDisclosure}</p>
          <label className="checkbox-row" data-testid="consent-checkbox">
            <input
              type="checkbox"
              checked={consentChecked}
              onChange={handleCheckboxChange}
              aria-checked={consentChecked}
              className="checkbox-input"
            />
            <span className="checkbox-label">
              {strings.consentCheckboxLabel}
            </span>
          </label>
        </div>
      )}

      {/* Primary action button */}
      <button
        aria-label={strings.noticeButton}
        aria-disabled={isButtonDisabled}
        disabled={isButtonDisabled}
        onClick={handleClick}
        className={`notice-button${isButtonDisabled ? " notice-button--disabled" : ""}`}
        data-testid="notice-button"
      >
        {strings.noticeButton}
      </button>
    </div>
  );
}
