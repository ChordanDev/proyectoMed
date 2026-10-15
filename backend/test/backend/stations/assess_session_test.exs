defmodule Backend.Stations.AssessSessionTest do
  # Swaps application-level adapters, so it cannot run concurrently.
  use ExUnit.Case, async: false

  alias Backend.Stations
  alias Backend.Stations.JevDecision.DisabledAdapter

  @moduletag capture_log: true

  @criterion_id "onset-assessment"
  @learner_text "Quando começou a dor no peito?"

  defmodule PatientDouble do
    @moduledoc "Station AI double that always answers with the same patient line."
    @behaviour Backend.Stations.StationAI

    @impl true
    def next_reply(_package, _context) do
      {:ok, %{text: "Começou há duas horas.", used_facts: []}}
    end
  end

  defmodule JevDouble do
    @moduledoc """
    Verifies every patient reply and classifies every rubric question at its
    last authored level, citing the first learner turn.
    """
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request), do: {:ok, %{status: :verified}}

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}

    @impl true
    def decide_rubric_batch(request), do: decide_rubric_batch(request, [])

    def decide_rubric_batch(request, opts) do
      if pid = opts[:test_pid], do: send(pid, {:batch_request, request})

      {:ok, %{decisions: Enum.map(request.questions, &decision/1)}}
    end

    defp decision(question) do
      [_uncertain, top_level | _lower] = Enum.reverse(question.allowed_classes)

      %{
        criterion_id: question.criterion.id,
        classification: top_level,
        evidence_ids: ["turn-1"],
        actions:
          Enum.map(question.actions, fn action ->
            %{id: action.id, classification: "performed", evidence_ids: ["turn-1"]}
          end)
      }
    end
  end

  defmodule RefusingPatientJevDouble do
    @moduledoc """
    Refuses every patient reply and grades the rubric like `JevDouble`, so a
    learner turn kept after a refusal must reach the rubric evidence pool.
    """
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request), do: {:ok, %{status: :semantic_refusal, rationale: "refused"}}

    @impl true
    def decide_rubric(request), do: JevDouble.decide_rubric(request)

    @impl true
    def decide_rubric_batch(request), do: JevDouble.decide_rubric_batch(request, [])

    def decide_rubric_batch(request, opts), do: JevDouble.decide_rubric_batch(request, opts)
  end

  setup do
    previous =
      Map.new([:station_ai_adapter, :jev_decision_adapter], fn key ->
        {key, Application.fetch_env(:backend, key)}
      end)

    Application.put_env(:backend, :station_ai_adapter, PatientDouble)
    Application.put_env(:backend, :jev_decision_adapter, JevDouble)

    on_exit(fn -> Enum.each(previous, &restore_env/1) end)

    :ok
  end

  defp restore_env({key, {:ok, value}}), do: Application.put_env(:backend, key, value)
  defp restore_env({key, :error}), do: Application.delete_env(:backend, key)

  defp completed_session do
    session = Stations.create_session(%{audio_consent: true})

    {:ok, _reply} =
      Stations.create_message(session.session_id, %{
        role: "learner",
        modality: "text",
        text: @learner_text
      })

    {:ok, _completed} = Stations.complete_session(session.session_id, :user)

    session.session_id
  end

  describe "assess_session/2" do
    test "returns :not_found for an unknown session" do
      assert Stations.assess_session("unknown-id") == {:error, :not_found}
    end

    test "returns :session_not_finished for an active session" do
      session = Stations.create_session(%{audio_consent: true})

      assert Stations.assess_session(session.session_id) == {:error, :session_not_finished}
    end

    test "assesses a completed session end to end with one batched Jev call" do
      session_id = completed_session()

      assert {:ok, assessment} = Stations.assess_session(session_id, test_pid: self())

      assert_received {:batch_request, sent}
      refute_received {:batch_request, _}
      assert Enum.map(sent.questions, & &1.criterion.id) == [@criterion_id]

      assert [criterion] = assessment.criteria
      assert criterion.id == @criterion_id
      assert criterion.status == :assessed
      assert criterion.level == "adequado"
      assert criterion.points == 80
      assert criterion.evidence_ids == ["turn-1"]
      assert [%{id: "turn-1", text: @learner_text}] = criterion.evidence

      assert criterion.sub_actions == [
               %{id: "ask-onset", classification: "performed", evidence_ids: ["turn-1"]}
             ]

      assert assessment.estimates.total == 80
      assert assessment.estimates.unresolved == []
      assert assessment.calls == [%{question_count: 1, justification: :single_batch}]
    end

    test "a learner turn kept after a refused patient reply is in the evidence pool and can be cited" do
      Application.put_env(:backend, :jev_decision_adapter, RefusingPatientJevDouble)
      session = Stations.create_session(%{audio_consent: true})

      assert {:error, {:refused, :semantic_refusal, _learner_turn}} =
               Stations.create_message(session.session_id, %{
                 role: "learner",
                 modality: "text",
                 text: @learner_text
               })

      {:ok, _completed} = Stations.complete_session(session.session_id, :user)

      assert {:ok, assessment} = Stations.assess_session(session.session_id, test_pid: self())

      assert_received {:batch_request, sent}
      assert sent.evidence_pool == [%{id: "turn-1", role: "learner", text: @learner_text}]

      assert [criterion] = assessment.criteria
      assert criterion.status == :assessed
      assert criterion.evidence_ids == ["turn-1"]
      assert [%{id: "turn-1", text: @learner_text}] = criterion.evidence
    end

    test "the disabled default adapter invalidates the attempt" do
      session_id = completed_session()
      Application.put_env(:backend, :jev_decision_adapter, DisabledAdapter)

      assert {:error, {:invalid_attempt, {:adapter_disabled, message}}} =
               Stations.assess_session(session_id)

      assert is_binary(message)
    end

    test "get_session_result/1 keeps the legacy shape for the same session" do
      session_id = completed_session()

      assert {:ok, _assessment} = Stations.assess_session(session_id)
      assert {:ok, result} = Stations.get_session_result(session_id)

      assert result.session_id == session_id
      assert result.status == "completed"
      assert [criterion] = result.criteria
      assert Enum.sort(Map.keys(criterion)) == [:evidence, :id, :recommendation, :status]
      assert criterion.status in ["met", "omitted", "uncertain"]
      assert Enum.all?(criterion.evidence, &is_binary/1)
    end
  end
end
