defmodule Backend.Stations.EducationalResult do
  @moduledoc false

  alias Backend.Stations.RubricAssessment.Points

  # Only bounded learner-facing categories cross the wire. Tagged reasons may
  # contain evidence IDs or provider detail and must never be inspected here.
  def serialize(session_id, assessment, package) do
    authored = Map.new(package["rubric"], &{&1["id"], &1})
    criteria = Enum.map(assessment.criteria, &criterion(&1, Map.fetch!(authored, &1.id)))
    estimates = assessment.estimates

    %{
      schema_version: "2",
      session_id: session_id,
      status: "completed",
      placeholder: package["placeholder"] == true,
      criteria: criteria,
      coverage:
        Map.new([:assessed, :uncertain, :not_observable, :not_applicable], fn status ->
          {status, Enum.count(assessment.criteria, &(&1.status == status))}
        end),
      estimates: %{
        total:
          if(is_nil(estimates.total), do: nil, else: Points.to_decimal_string(estimates.total)),
        scored_subtotal: Points.to_decimal_string(estimates.scored_subtotal),
        scored_max: Points.to_decimal_string(estimates.scored_max),
        eligible_max: Points.to_decimal_string(estimates.eligible_max),
        unresolved: Enum.map(estimates.unresolved, &%{id: &1.id, status: to_string(&1.status)})
      }
    }
  end

  defp criterion(result, authored) do
    base = %{
      id: result.id,
      description: authored["description"],
      status: to_string(result.status),
      max_points: Points.to_decimal_string(result.max_points),
      evidence_ids: result.evidence_ids,
      evidence: Enum.map(result.evidence, &%{id: &1.id, role: to_string(&1.role), text: &1.text}),
      reason: reason(result.status),
      recommendation: result.recommendation
    }

    if result.status == :assessed do
      level = Enum.find(authored["levels"], &(&1["label"] == result.level))

      Map.merge(base, %{
        level: result.level,
        level_description: level["description"],
        points: Points.to_decimal_string(result.points)
      })
    else
      base
    end
  end

  defp reason(:assessed), do: nil
  defp reason(:uncertain), do: "assessment_unresolved"
  defp reason(:not_observable), do: "required_modality_unavailable"
  defp reason(:not_applicable), do: "authored_exclusion"
end
