// Fictional wire-contract fixture; never used by the runtime.
import type { SessionResult } from "../api/client";

export const partialResult: SessionResult = {
  schema_version: "2",
  session_id: "session-1",
  status: "completed",
  placeholder: true,
  coverage: { assessed: 1, uncertain: 1, not_observable: 0, not_applicable: 0 },
  estimates: {
    total: null,
    scored_subtotal: "0.25",
    scored_max: "0.25",
    eligible_max: "1.25",
    unresolved: [{ id: "criterion-b", status: "uncertain" }],
  },
  criteria: [
    {
      id: "criterion-a",
      description: "Criterion with an observed partial result.",
      status: "assessed",
      level: "parcialmente_adequado",
      level_description: "Criterion A is partially adequate.",
      points: "0.25",
      max_points: "0.25",
      evidence_ids: ["turn-1"],
      evidence: [{ id: "turn-1", role: "learner", text: "Exemplo da sessão" }],
      reason: null,
      recommendation: "Practice criterion A.",
    },
    {
      id: "criterion-b",
      description: "Criterion left unresolved by the assessment.",
      status: "uncertain",
      max_points: "1",
      evidence_ids: [],
      evidence: [],
      reason: "assessment_unresolved",
      recommendation: "Gather enough evidence for criterion B.",
    },
  ],
};
