defmodule Backend.Stations.Overtime do
  @moduledoc """
  Training overtime and its penalty (#323).

  A training marks the expected end at `deadline_at` but does not stop there:
  the time beyond it is the overtime. Each started minute of overtime costs a
  quarter of a point, up to ten minutes, and the penalty produces a training
  score separate from the rubric estimate. A real test (`:simulated_exam`) has
  no overtime. Points are integer fortieths, as in
  `Backend.Stations.RubricAssessment.Points`.
  """

  @fortieths_per_started_minute 10
  @max_penalised_minutes 10

  @doc """
  Whole seconds a completed training ran past `deadline_at`, `0` when it was
  finished within the expected time, and `nil` for a real test.
  """
  @spec seconds(map()) :: non_neg_integer() | nil
  def seconds(%{mode: :simulated_exam}), do: nil

  def seconds(%{deadline_at: deadline_at, completed_at: %DateTime{} = completed_at}) do
    max(0, DateTime.diff(completed_at, deadline_at, :second))
  end

  @doc "Penalty in fortieths for the given overtime seconds, capped at ten started minutes."
  @spec penalty(non_neg_integer()) :: non_neg_integer()
  def penalty(overtime_seconds) when is_integer(overtime_seconds) and overtime_seconds >= 0 do
    started_minutes = div(overtime_seconds + 59, 60)
    min(started_minutes, @max_penalised_minutes) * @fortieths_per_started_minute
  end

  @doc "The rubric total minus the penalty, never negative; `nil` when the total is unresolved."
  @spec training_score(non_neg_integer() | nil, non_neg_integer()) :: non_neg_integer() | nil
  def training_score(nil, _penalty), do: nil
  def training_score(total, penalty), do: max(0, total - penalty)
end
