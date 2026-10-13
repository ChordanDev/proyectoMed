defmodule Backend.E2ESupport.ApprovingJevAdapter do
  @moduledoc """
  Deterministic Jev decision adapter for the process-level E2E suite only.

  **This adapter bypasses Jev verification.** It judges nothing: it never reads
  candidate, learner or patient text, and it performs no I/O. It exists so the
  E2E harness, which boots Phoenix in a separate process and cannot inject an
  adapter, can exercise the learner loop through the real HTTP contract.

  It lives outside `lib/`, is compiled only for `:dev` and `:test`
  (`elixirc_paths/1` in `mix.exs`), and is selected only by
  `JEV_E2E_APPROVING_ADAPTER=true` under `:dev`, where the harness runs
  (`config/runtime.exs`). The default adapter stays
  `Backend.Stations.JevDecision.DisabledAdapter`.

  ## Decisions

    * `decide_patient/1` verifies every candidate.
    * `decide_rubric/1` and `decide_rubric_batch/1` approve only what can be
      grounded. When the evidence pool holds learner evidence, the criterion
      gets its last authored class (the reserved `"uncertain"` class excluded)
      and cites the first learner item; every authored action is `"performed"`
      with that same citation. Without learner evidence, everything is
      `"uncertain"` and nothing is cited.

  The citation is still validated by the caller, so a criterion whose modality
  the first learner item does not satisfy stays uncertain there.
  """

  @behaviour Backend.Stations.JevDecision.Adapter

  @uncertain "uncertain"
  @performed "performed"
  @learner_roles ["learner", "student"]

  @impl true
  def decide_patient(_request) do
    {:ok, %{status: :verified}}
  end

  @impl true
  def decide_rubric(request) do
    citation = first_learner_id(request.evidence_pool, request.allowed_evidence_ids)

    {:ok,
     %{
       classification: classification(request.allowed_classes, citation),
       evidence_ids: List.wrap(citation)
     }}
  end

  @impl true
  def decide_rubric_batch(request) do
    citation = first_learner_id(request.evidence_pool)

    {:ok, %{decisions: Enum.map(request.questions, &decision(&1, citation))}}
  end

  defp decision(question, citation) do
    decision = %{
      criterion_id: question.criterion.id,
      classification: classification(question.allowed_classes, citation),
      evidence_ids: List.wrap(citation),
      actions: Enum.map(question.actions, &action_decision(&1, citation))
    }

    if Map.get(question, :enumerate_answers) do
      Map.put(decision, :answers, answers(question.actions, citation))
    else
      decision
    end
  end

  defp action_decision(action, nil), do: %{id: action.id, classification: @uncertain}

  defp action_decision(action, citation) do
    %{id: action.id, classification: @performed, evidence_ids: [citation]}
  end

  # One answer per performed action, all in the cited item, so the enumeration
  # agrees with the action decisions.
  defp answers(_actions, nil), do: []

  defp answers(actions, citation) do
    Enum.map(actions, &%{evidence_id: citation, action_id: &1.id})
  end

  defp classification(allowed_classes, nil) do
    if @uncertain in allowed_classes, do: @uncertain, else: hd(allowed_classes)
  end

  defp classification(allowed_classes, _citation) do
    allowed_classes |> Enum.reject(&(&1 == @uncertain)) |> List.last() || hd(allowed_classes)
  end

  defp first_learner_id(pool, allowed_ids \\ nil) do
    Enum.find_value(pool, fn item ->
      if to_string(item.role) in @learner_roles and
           (is_nil(allowed_ids) or item.id in allowed_ids),
         do: item.id
    end)
  end
end
