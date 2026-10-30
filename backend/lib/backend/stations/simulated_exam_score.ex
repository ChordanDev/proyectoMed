defmodule Backend.Stations.SimulatedExamScore do
  @moduledoc """
  The result of a simulated exam (#318, #426, ADR-012 amendment on #124): the
  total scaled to the full maximum, the certainty level, and the incomplete
  flag. Computed only here from the rubric estimates; the clients display it.

  The certainty level is the share of eligible points that were assessed,
  compared in exact integer arithmetic: 5 at 100 %, 4 from 80 %, 3 from 60 %,
  2 from 40 %, and 1 below that or when nothing is eligible. It never reads
  provider or model confidence.

  The scaled total is `scored_subtotal / scored_max × eligible_max`, held in
  integer fortieths and rounded half up to the nearest fortieth, so it stays
  an exact point value, equals the rubric total at full coverage and never
  passes `eligible_max`. Level 1 has no total. An unassessed criterion is left
  out of the sum, never counted as zero, and makes the result `incomplete`.
  """

  alias Backend.Stations.RubricAssessment.Estimates
  alias Backend.Stations.RubricAssessment.Points

  @certainty_floors [{5, 100}, {4, 80}, {3, 60}, {2, 40}]
  @lowest_level 1

  @type t :: %{
          scaled_total: Points.t() | nil,
          certainty_level: 1..5,
          incomplete: boolean()
        }

  @doc "Scores a simulated exam from its rubric estimates."
  @spec score(Estimates.t()) :: t()
  def score(estimates) do
    level = certainty_level(estimates)

    %{
      scaled_total: scaled_total(estimates, level),
      certainty_level: level,
      incomplete: estimates.unresolved != []
    }
  end

  defp certainty_level(%{eligible_max: 0}), do: @lowest_level

  defp certainty_level(%{scored_max: scored_max, eligible_max: eligible_max}) do
    Enum.find_value(@certainty_floors, @lowest_level, fn {level, percent} ->
      if scored_max * 100 >= eligible_max * percent, do: level
    end)
  end

  defp scaled_total(_estimates, @lowest_level), do: nil

  defp scaled_total(estimates, _level) do
    %{scored_subtotal: subtotal, scored_max: scored_max, eligible_max: eligible_max} = estimates
    div(2 * subtotal * eligible_max + scored_max, 2 * scored_max)
  end
end
