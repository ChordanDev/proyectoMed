defmodule Backend.Stations.EducationalResult do
  @moduledoc false

  alias Backend.Stations.Overtime
  alias Backend.Stations.RubricAssessment.Points
  alias Backend.Stations.SimulatedExamScore

  # Only bounded learner-facing categories cross the wire. Tagged reasons may
  # contain evidence IDs or provider detail and must never be inspected here.
  def serialize(session_id, assessment, package, session) do
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
    |> put_overtime(estimates, session)
    |> put_simulated_exam_score(estimates, session)
  end

  # A training adds how long it ran past the expected time and the training
  # score that deducts it (#323); the rubric estimates stay untouched. A real
  # test has no overtime, so it adds nothing.
  defp put_overtime(result, estimates, session) do
    case Overtime.seconds(session) do
      nil ->
        result

      overtime_seconds ->
        penalty = Overtime.penalty(overtime_seconds)
        score = Overtime.training_score(estimates.total, penalty)

        Map.merge(result, %{
          overtime_seconds: overtime_seconds,
          overtime_penalty: Points.to_decimal_string(penalty),
          training_score: if(is_nil(score), do: nil, else: Points.to_decimal_string(score))
        })
    end
  end

  # A simulated exam adds its scaled total, certainty level and incomplete flag
  # (#426); the rubric estimates stay untouched. A training adds nothing.
  defp put_simulated_exam_score(result, estimates, %{mode: :simulated_exam}) do
    score = SimulatedExamScore.score(estimates)

    Map.merge(result, %{
      scaled_total:
        if(is_nil(score.scaled_total),
          do: nil,
          else: Points.to_decimal_string(score.scaled_total)
        ),
      certainty_level: score.certainty_level,
      incomplete: score.incomplete
    })
  end

  defp put_simulated_exam_score(result, _estimates, _session), do: result

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
