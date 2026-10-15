defmodule Backend.Stations.RubricAssessment.ImpressoActions do
  @moduledoc """
  Decides, without any provider, the rubric actions that are requests for
  impressos (issue #228).

  An action may author `impresso_ids`: the impressos whose release means the
  learner requested what the action asks. Such an action is `"performed"` when
  the evidence pool holds an Impressos request event that released one of those
  ids and passes `Backend.Stations.RubricAssessment.Evidence.validate/3` for the
  criterion's requirement (a verified event that released something, of an
  accepted channel). Every such event is cited, in pool order.

  An action without a matching release is not decided here: the learner may
  have asked in the conversation, so it stays with Jev and the resolver.

  A criterion that authors `first_n` is never decided here, because a released
  impresso has no position among the learner's answers.

  The module is pure.
  """

  alias Backend.Stations.RubricAssessment.Evidence
  alias Backend.Stations.RubricAssessment.FirstN

  @performed "performed"

  @typedoc "An action decided from a released impresso."
  @type sub_action :: %{id: String.t(), classification: String.t(), evidence_ids: [String.t()]}

  @doc """
  Returns the actions of a package criterion (string keys) that a released
  impresso decides, keyed by action id.
  """
  @spec settle(map(), Evidence.requirement(), Evidence.pool()) :: %{
          optional(String.t()) => sub_action()
        }
  def settle(criterion, requirement, pool) when is_map(criterion) and is_list(pool) do
    if FirstN.applies?(criterion) do
      %{}
    else
      for %{"id" => id, "impresso_ids" => [_ | _] = impresso_ids} <- actions(criterion),
          evidence_ids = citable(pool, impresso_ids, requirement),
          evidence_ids != [],
          into: %{} do
        {id, %{id: id, classification: @performed, evidence_ids: evidence_ids}}
      end
    end
  end

  defp citable(pool, impresso_ids, requirement) do
    for %{kind: :impresso_event, released_ids: released} = item <- pool,
        Enum.any?(released, &(&1 in impresso_ids)),
        match?({:ok, _evidence}, Evidence.validate(pool, [item.id], requirement)),
        do: item.id
  end

  defp actions(criterion) do
    case Map.get(criterion, "actions") do
      actions when is_list(actions) -> Enum.filter(actions, &is_map/1)
      _missing -> []
    end
  end
end
