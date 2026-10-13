defmodule Backend.Stations.RubricAssessment.TaskOrder do
  @moduledoc """
  The task-order criterion (`rule: "task_order"`), assessed in code from the
  results of the ranked criteria of the same rubric (issue #128, ADR-012).

  A ranked criterion is an active criterion with an authored `order` rank. It
  is *performed* when it was assessed above its zero-point level, and its
  position is the pool position of its earliest evidence item. Ranked criteria
  assessed at zero are skipped: order is judged among the steps the learner
  actually did. A `:not_observable` ranked criterion is skipped too: a step the
  station cannot provide can never be performed.

  The order holds when, for every pair of performed criteria with rank `a`
  below rank `b`, the position of `a` is at most the position of `b`. Equal
  ranks are unordered among themselves, and one turn may back several steps.

  `decide/2` answers, in this order:

    1. `:violated` when the performed criteria already break the order. No
       unresolved criterion can undo that.
    2. Uncertain when any ranked criterion is `:uncertain`: its position is
       unknown, so it could still add a violation or a second step.
    3. `:held` with at least two performed criteria in order.
    4. `:too_few` otherwise: there is nothing to compare.

  The module is pure. It never reads a transcript; it only compares positions
  of evidence the ranked criteria already validated.
  """

  alias Backend.Stations.RubricAssessment.Evidence

  @typedoc "A ranked criterion with its authored rank and its criterion result."
  @type ranked :: %{id: String.t(), rank: integer(), result: map()}

  @typedoc "Why the order cannot be judged yet."
  @type uncertainty :: {:unresolved_ranked_criterion, String.t()}

  @typedoc """
  The outcome and the evidence that grounds it: the earliest evidence item of
  each compared criterion, in pool order. `:too_few` compares nothing.
  """
  @type decision :: {:held | :violated | :too_few, [Evidence.item()]}

  @doc """
  Decides the order from the ranked criteria, given in rubric order, and the
  evidence pool their results cite.

  Returns `{:uncertain, reason}` naming the first unresolved ranked criterion
  when the resolved ones show no violation.
  """
  @spec decide([ranked()], Evidence.pool()) :: decision() | {:uncertain, uncertainty()}
  def decide(ranked, pool) when is_list(ranked) and is_list(pool) do
    steps = steps(ranked, pool)
    unresolved = Enum.find(ranked, &(&1.result.status == :uncertain))

    cond do
      violated?(steps) -> {:violated, evidence(steps)}
      unresolved -> {:uncertain, {:unresolved_ranked_criterion, unresolved.id}}
      length(steps) >= 2 -> {:held, evidence(steps)}
      true -> {:too_few, []}
    end
  end

  # The performed criteria as `{rank, position, earliest evidence item}`. A
  # criterion assessed above zero always cites validated evidence, and its
  # evidence identifiers are already in pool order.
  defp steps(ranked, pool) do
    indexed =
      pool |> Enum.with_index() |> Map.new(fn {item, index} -> {item.id, {index, item}} end)

    for %{rank: rank, result: %{status: :assessed, points: points, evidence_ids: [earliest | _]}} <-
          ranked,
        points > 0 do
      {position, item} = Map.fetch!(indexed, earliest)
      {rank, position, item}
    end
  end

  defp violated?(steps) do
    Enum.any?(steps, fn {rank, position, _item} ->
      Enum.any?(steps, fn {later_rank, later_position, _later_item} ->
        rank < later_rank and position > later_position
      end)
    end)
  end

  defp evidence(steps) do
    steps
    |> Enum.sort_by(fn {_rank, position, _item} -> position end)
    |> Enum.map(fn {_rank, _position, item} -> item end)
    |> Enum.uniq_by(& &1.id)
  end
end
