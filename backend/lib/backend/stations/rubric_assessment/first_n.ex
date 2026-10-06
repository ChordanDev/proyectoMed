defmodule Backend.Stations.RubricAssessment.FirstN do
  @moduledoc """
  The `first_n` rule: only the learner's first N answers to a criterion are
  eligible, including answers that match no authored action (issue #128,
  ADR-012). It exists so that listing everything does not earn credit.

  The rule applies to a criterion that authors `first_n` and at least one
  action; such a criterion also authors thresholds, so its level comes from
  the count of eligible actions and never from Jev's class. For such a
  criterion the batch question requests the enumeration of the learner's
  answers, and `eligible/5` reads the list Jev returned:

    1. Every entry must cite evidence that passes the same validation as any
       other citation of the criterion.
    2. The entries must follow the evidence order: an entry may not cite an
       item earlier in the pool than the entry before it. Equal positions are
       fine, because one turn may hold several answers.
    3. The list must agree with the sub-action decisions: every action
       classified `"performed"` has an entry, and every entry that names an
       action names one classified `"performed"`.
    4. An entry that names an action must cite one of that action's own
       validated evidence items, so the position of an answer is the position
       of evidence that grounds it. An action performed without evidence has
       none to compare and stays unresolved.
    5. Only the first N entries are eligible. A `counted` or `mandatory` action
       whose entry lies beyond them is not performed, with certainty. A
       `forbidden` action keeps its classification wherever it appears: a
       harmful conduct is not excused by position.
    6. An unresolved action must not be able to displace an eligible answer.
       An action classified `"uncertain"` has no entry, so if it was performed
       its answer may lie anywhere and push a later one beyond the first N.
       When an action is unresolved and the list is full (it has at least N
       entries, or its entries plus the actions classified `"uncertain"`
       exceed N), the criterion is uncertain, unless the classified facts
       already score a certain zero.

  A list that fails step 1, 2, 3 or 4 contradicts the transcript or the
  classifier's own reading, so the criterion fails closed. While the list has
  room for every unresolved action, those actions are left to the
  reachable-outcome rule of `Backend.Stations.RubricAssessment.AuthoredRules`,
  which runs afterwards.

  The module never reads the transcript and never reorders or repairs the
  list: it only compares positions of validated evidence. It cannot detect an
  unmatched answer the classifier left out of the list, nor verify the order
  of several answers inside one turn; both rest on the classifier.
  """

  alias Backend.Stations.JevDecision.RubricBatch
  alias Backend.Stations.RubricAssessment.AuthoredRules
  alias Backend.Stations.RubricAssessment.Evidence

  @performed "performed"
  @not_performed "not_performed"
  @uncertain "uncertain"
  @forbidden "forbidden"

  @typedoc "Why the enumerated answers leave their criterion uncertain."
  @type uncertainty ::
          {:answer_out_of_order, String.t()}
          | {:unlisted_performed_action, String.t()}
          | {:listed_unperformed_action, String.t()}
          | {:answer_evidence_mismatch, String.t()}
          | AuthoredRules.uncertainty()

  @doc """
  Says whether the rule applies to a package criterion (string keys): it
  authors `first_n` and at least one action.
  """
  @spec applies?(map()) :: boolean()
  def applies?(criterion) when is_map(criterion) do
    is_integer(first_n(criterion)) and Enum.any?(actions(criterion))
  end

  @doc """
  Returns the sub-action decisions the per-criterion rules must use: the given
  ones, with each `counted` or `mandatory` action enumerated beyond the first N
  answers turned into `"not_performed"` without evidence.

  `sub_actions` are the validated decisions in authored order and `answers` the
  enumeration of the batch decision, in the order Jev listed it. A criterion
  the rule does not apply to gets its sub-actions back unchanged.

  Returns `{:error, {rejection, evidence_id}}` for the first entry whose
  evidence fails validation, or `{:uncertain, reason}` when the list goes
  against the evidence order (`{:answer_out_of_order, evidence_id}`, naming the
  first entry that goes backwards) or disagrees with the sub-action decisions
  (`{:unlisted_performed_action, action_id}` in authored order, then
  `{:listed_unperformed_action, action_id}` in list order), cites for an
  action evidence that is not the action's own
  (`{:answer_evidence_mismatch, action_id}`), or leaves an unresolved action
  able to displace an eligible answer (the reason
  `Backend.Stations.RubricAssessment.AuthoredRules.unresolved/2` gives).
  """
  @spec eligible(
          map(),
          [AuthoredRules.sub_action()],
          [RubricBatch.answer()],
          Evidence.pool(),
          Evidence.requirement()
        ) ::
          {:ok, [AuthoredRules.sub_action()]}
          | {:error, {Evidence.rejection(), term()}}
          | {:uncertain, uncertainty()}
  def eligible(criterion, sub_actions, answers, pool, requirement)
      when is_map(criterion) and is_list(sub_actions) and is_list(answers) and is_list(pool) do
    if applies?(criterion) do
      with :ok <- validate_evidence(answers, pool, requirement),
           :ok <- check_order(answers, pool),
           :ok <- check_agreement(answers, sub_actions),
           :ok <- check_action_evidence(answers, sub_actions) do
        limit(criterion, sub_actions, answers)
      end
    else
      {:ok, sub_actions}
    end
  end

  defp limit(criterion, sub_actions, answers) do
    eligible = beyond_as_not_performed(criterion, sub_actions, answers)

    with :ok <- check_displacement(criterion, eligible, answers), do: {:ok, eligible}
  end

  defp validate_evidence(answers, pool, requirement) do
    with {:ok, _items} <-
           Evidence.validate(pool, Enum.map(answers, & &1.evidence_id), requirement) do
      :ok
    end
  end

  # Every entry already cites an item of the pool.
  defp check_order(answers, pool) do
    positions = pool |> Enum.with_index() |> Map.new(fn {item, index} -> {item.id, index} end)

    answers
    |> Enum.map(&{&1.evidence_id, Map.fetch!(positions, &1.evidence_id)})
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find(fn [{_id, earlier}, {_later_id, later}] -> later < earlier end)
    |> case do
      nil -> :ok
      [_earlier, {evidence_id, _position}] -> {:uncertain, {:answer_out_of_order, evidence_id}}
    end
  end

  defp check_agreement(answers, sub_actions) do
    listed = for %{action_id: action_id} <- answers, action_id != nil, do: action_id
    performed = for %{classification: @performed, id: id} <- sub_actions, do: id

    case {performed -- listed, listed -- performed} do
      {[], []} -> :ok
      {[action_id | _rest], _listed} -> {:uncertain, {:unlisted_performed_action, action_id}}
      {[], [action_id | _rest]} -> {:uncertain, {:listed_unperformed_action, action_id}}
    end
  end

  # Every entry that names an action names one classified performed. An action
  # performed without evidence has nothing to compare.
  defp check_action_evidence(answers, sub_actions) do
    evidence = Map.new(sub_actions, &{&1.id, &1.evidence_ids})

    mismatched =
      Enum.find(answers, fn %{action_id: action_id, evidence_id: evidence_id} ->
        action_id != nil and evidence[action_id] != [] and evidence_id not in evidence[action_id]
      end)

    case mismatched do
      nil -> :ok
      %{action_id: action_id} -> {:uncertain, {:answer_evidence_mismatch, action_id}}
    end
  end

  # An action classified uncertain has no entry: if it was performed, its
  # answer takes a slot at an unknown position. Once the possible answers
  # exceed N, an eligible answer may in fact lie beyond the first N.
  defp check_displacement(criterion, eligible, answers) do
    unlisted = Enum.count(eligible, &(&1.classification == @uncertain))
    full? = length(answers) + max(unlisted, 1) > first_n(criterion)
    reason = AuthoredRules.unresolved(criterion, eligible)

    if full? and reason != nil and not AuthoredRules.certain_zero?(criterion, eligible) do
      {:uncertain, reason}
    else
      :ok
    end
  end

  defp beyond_as_not_performed(criterion, sub_actions, answers) do
    forbidden = for %{"id" => id, "role" => @forbidden} <- actions(criterion), do: id

    beyond =
      for %{action_id: action_id} <- Enum.drop(answers, first_n(criterion)),
          action_id != nil and action_id not in forbidden,
          do: action_id

    Enum.map(sub_actions, fn sub_action ->
      if sub_action.id in beyond do
        %{sub_action | classification: @not_performed, evidence_ids: []}
      else
        sub_action
      end
    end)
  end

  defp first_n(criterion) do
    case Map.get(criterion, "first_n") do
      first_n when is_integer(first_n) and first_n >= 1 -> first_n
      _unset -> nil
    end
  end

  defp actions(criterion) do
    case Map.get(criterion, "actions") do
      actions when is_list(actions) -> Enum.filter(actions, &is_map/1)
      _missing -> []
    end
  end
end
