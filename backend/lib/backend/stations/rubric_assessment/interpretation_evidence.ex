defmodule Backend.Stations.RubricAssessment.InterpretationEvidence do
  @moduledoc """
  A learner cannot interpret an exam before receiving it (issue #265).

  An action may author `interprets_impresso_ids`: the impressos it interprets.
  Its evidence is then only a learner turn that comes, in the evidence pool,
  after a verified Impressos request that released one of those ids. The pool
  is already in session order (`Backend.Stations.RubricAssessment.Evidence`
  sorts by `at`, with turns before events on a tie), so the rule compares pool
  positions and never clocks. The request itself is not interpretation
  evidence.

  `Backend.Stations.RubricAssessment` applies the rule to every action decision,
  after the rubric resolver merged its answers, so it covers Jev's citations and
  the resolver's alike. A citation that fails it is dropped; a `"performed"`
  action left with none is `"not_performed"`, so an earlier turn never raises a
  level. An action that interprets nothing is unchanged.

  The module is pure.
  """

  alias Backend.Stations.RubricAssessment.Evidence

  @performed "performed"
  @not_performed "not_performed"

  @typedoc "An action decision with validated evidence identifiers."
  @type sub_action :: %{id: String.t(), classification: String.t(), evidence_ids: [String.t()]}

  @doc """
  Returns the impressos each action of a package criterion (string keys)
  interprets, keyed by action id. Actions that interpret nothing are absent.
  """
  @spec dependencies(map()) :: %{optional(String.t()) => [String.t()]}
  def dependencies(criterion) when is_map(criterion) do
    for %{"id" => id, "interprets_impresso_ids" => [_ | _] = ids} <- actions(criterion),
        into: %{},
        do: {id, ids}
  end

  @doc """
  Applies the rule to one action decision, given the impressos it interprets
  (`nil` when it interprets nothing).
  """
  @spec restrict(sub_action(), [String.t()] | nil, Evidence.pool()) :: sub_action()
  def restrict(sub_action, nil, _pool), do: sub_action

  def restrict(%{evidence_ids: cited} = sub_action, impresso_ids, pool) do
    case {sub_action.classification, admissible(pool, cited, impresso_ids)} do
      {@performed, []} when cited != [] ->
        %{sub_action | classification: @not_performed, evidence_ids: []}

      {_classification, kept} ->
        %{sub_action | evidence_ids: kept}
    end
  end

  @doc """
  Returns the cited identifiers, in citation order, that may ground an action
  interpreting `impresso_ids`: every one when it is `nil`, otherwise the
  learner turns positioned after the first verified release of one of them.
  """
  @spec admissible(Evidence.pool(), [String.t()], [String.t()] | nil) :: [String.t()]
  def admissible(_pool, cited, nil), do: cited

  def admissible(pool, cited, impresso_ids) do
    positioned = Enum.with_index(pool)

    case Enum.find(positioned, fn {item, _position} -> releases?(item, impresso_ids) end) do
      nil ->
        []

      {_release, released_at} ->
        later_turns =
          for {%{kind: :turn, id: id}, position} <- positioned,
              position > released_at,
              into: MapSet.new(),
              do: id

        Enum.filter(cited, &MapSet.member?(later_turns, &1))
    end
  end

  defp releases?(%{kind: :impresso_event, provenance: :impressos, released_ids: released}, ids),
    do: Enum.any?(released, &(&1 in ids))

  defp releases?(_item, _ids), do: false

  defp actions(criterion) do
    case Map.get(criterion, "actions") do
      actions when is_list(actions) -> Enum.filter(actions, &is_map/1)
      _missing -> []
    end
  end
end
