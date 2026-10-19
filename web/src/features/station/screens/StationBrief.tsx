import React, { useId } from "react";
import type { CandidateBrief } from "../api/client";
import strings from "../i18n/pt-BR.json";
import "./StationBrief.css";

export interface StationBriefProps {
  brief: CandidateBrief;
}

/** Renders the learner-facing scenario and the numbered station tasks. */
export function StationBrief({ brief }: StationBriefProps): React.JSX.Element {
  const scenarioId = useId();
  const tasksId = useId();

  return (
    <div className="station-brief" data-testid="station-brief">
      <p className="station-brief__fictional" role="note">
        {strings.briefFictionalNote}
      </p>
      <section aria-labelledby={scenarioId}>
        <h2 id={scenarioId}>{strings.briefScenarioHeading}</h2>
        <p className="station-brief__scenario">{brief.scenario}</p>
      </section>
      <section>
        <h2 id={tasksId}>{strings.briefTasksHeading}</h2>
        <ol className="station-brief__tasks" aria-labelledby={tasksId}>
          {brief.tasks.map((task, index) => (
            <li key={index}>{task}</li>
          ))}
        </ol>
      </section>
    </div>
  );
}
