defmodule Backend.Stations.RubricAssessment.Estimates do
  @moduledoc """
  Coverage-aware point estimates over already-decided rubric criteria
  (issue #128, ADR-012).

  A criterion is *active* unless its status is `:not_applicable`. The estimate
  reports three boundaries and never hides unresolved coverage:

    * `scored_subtotal` and `scored_max` cover assessed criteria only;
    * `eligible_max` covers every active criterion;
    * `total` equals `scored_subtotal` only when at least one criterion is
      active and every active criterion is assessed, otherwise it is `nil`;
    * `unresolved` lists the active criteria that are not assessed, in input
      order.

  Nothing is rescaled or prorated, and no probability ever multiplies points.
  A rubric with no active criterion (empty, or every criterion excluded) has
  nothing to estimate, so its `total` is `nil` rather than zero.

  The module is pure: it decides no status and performs no I/O.
  """

  alias Backend.Stations.RubricAssessment.Points

  @typedoc "Status of a decided criterion."
  @type status :: :assessed | :uncertain | :not_observable | :not_applicable

  @typedoc """
  A decided criterion. `:max_points` is the maximum over the criterion's
  authored levels; `:points` is present only when the status is `:assessed`.
  """
  @type criterion_result :: %{
          required(:id) => String.t(),
          required(:status) => status(),
          required(:max_points) => Points.t(),
          optional(:points) => Points.t()
        }

  @typedoc "An active criterion that could not be assessed."
  @type unresolved :: %{id: String.t(), status: :uncertain | :not_observable}

  @typedoc "Point estimates for one attempt."
  @type t :: %{
          total: Points.t() | nil,
          scored_subtotal: Points.t(),
          scored_max: Points.t(),
          eligible_max: Points.t(),
          unresolved: [unresolved()]
        }

  @typedoc "Why the maximum points of a package criterion cannot be computed."
  @type max_points_error :: :no_levels | Points.error()

  @doc """
  Computes the point estimates for a list of decided criteria.
  """
  @spec estimate([criterion_result()]) :: t()
  def estimate(results) when is_list(results) do
    active = Enum.reject(results, &(&1.status == :not_applicable))
    {assessed, unresolved} = Enum.split_with(active, &(&1.status == :assessed))
    scored_subtotal = sum_of(assessed, :points)

    %{
      total: total(active, unresolved, scored_subtotal),
      scored_subtotal: scored_subtotal,
      scored_max: sum_of(assessed, :max_points),
      eligible_max: sum_of(active, :max_points),
      unresolved: Enum.map(unresolved, &Map.take(&1, [:id, :status]))
    }
  end

  @doc """
  Computes the maximum points over the authored `"levels"` of a v2 package
  criterion (string keys, as loaded from JSON).

  Returns `{:error, :no_levels}` when the criterion authors no level, and the
  `Backend.Stations.RubricAssessment.Points` reason when a level's `"points"`
  is not an exact, non-negative multiple of 0.125. Never raises.
  """
  @spec max_points(term()) :: {:ok, Points.t()} | {:error, max_points_error()}
  def max_points(%{"levels" => [_ | _] = levels}) do
    with {:ok, points} <- level_points(levels), do: {:ok, Enum.max(points)}
  end

  def max_points(_criterion), do: {:error, :no_levels}

  defp total([], _unresolved, _scored_subtotal), do: nil
  defp total(_active, [], scored_subtotal), do: scored_subtotal
  defp total(_active, _unresolved, _scored_subtotal), do: nil

  defp sum_of(results, key), do: results |> Enum.map(&Map.fetch!(&1, key)) |> Points.sum()

  defp level_points(levels) do
    Enum.reduce_while(levels, {:ok, []}, fn level, {:ok, acc} ->
      case authored_points(level) do
        {:ok, points} -> {:cont, {:ok, [points | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp authored_points(%{"points" => authored}), do: Points.from_authored(authored)
  defp authored_points(_level), do: {:error, :not_a_number}
end
