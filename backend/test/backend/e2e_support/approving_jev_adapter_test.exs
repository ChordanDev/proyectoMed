defmodule Backend.E2ESupport.ApprovingJevAdapterTest do
  use ExUnit.Case, async: true

  alias Backend.E2ESupport.ApprovingJevAdapter
  alias Backend.Stations.JevDecision
  alias Backend.Stations.RubricAssessment

  # Every call goes through the `JevDecision` seam or the assessment pipeline, so
  # these tests prove the adapter's output survives the strict validation the
  # running application applies, not only its raw shape.
  @opts [adapter: ApprovingJevAdapter]

  @learner_turn %{id: "turn-1", role: "learner", text: "Quando começou a dor no peito?"}
  @patient_turn %{id: "turn-2", role: "patient", text: "A dor começou durante uma caminhada."}

  defp question(overrides \\ %{}) do
    Map.merge(
      %{
        criterion: %{id: "onset-assessment", description: "Assesses the onset of chest pain."},
        allowed_classes: ["inadequado", "adequado", "uncertain"],
        actions: [%{id: "ask-onset", description: "Ask about onset."}]
      },
      overrides
    )
  end

  describe "decide_patient/1" do
    test "verifies any candidate without consulting a provider" do
      request = %{
        candidate_text: "A dor começou durante uma caminhada.",
        package: %{"station_id" => "station", "version" => "2.0.0"},
        conversation: []
      }

      assert {:ok, %{status: :verified}} = JevDecision.decide_patient(request, @opts)
    end
  end

  describe "decide_rubric_batch/1" do
    test "awards the last authored class, grounded on the first learner item" do
      request = %{questions: [question()], evidence_pool: [@learner_turn, @patient_turn]}

      assert {:ok, [decision]} = JevDecision.decide_rubric_batch(request, @opts)

      assert decision.criterion_id == "onset-assessment"
      assert decision.classification == "adequado"
      assert decision.evidence_ids == ["turn-1"]

      assert decision.actions == [
               %{id: "ask-onset", classification: "performed", evidence_ids: ["turn-1"]}
             ]

      refute Map.has_key?(decision, :answers)
    end

    test "never cites a patient item" do
      request = %{questions: [question()], evidence_pool: [@patient_turn, @learner_turn]}

      assert {:ok, [%{evidence_ids: ["turn-1"]}]} =
               JevDecision.decide_rubric_batch(request, @opts)
    end

    test "stays uncertain and cites nothing without learner evidence" do
      request = %{questions: [question()], evidence_pool: [@patient_turn]}

      assert {:ok, [decision]} = JevDecision.decide_rubric_batch(request, @opts)

      assert decision.classification == "uncertain"
      assert decision.evidence_ids == []

      assert decision.actions == [
               %{id: "ask-onset", classification: "uncertain", evidence_ids: []}
             ]
    end

    test "answers every question of the batch" do
      second = question(%{criterion: %{id: "second", description: ""}, actions: []})
      request = %{questions: [question(), second], evidence_pool: [@learner_turn]}

      assert {:ok, [first_decision, second_decision]} =
               JevDecision.decide_rubric_batch(request, @opts)

      assert first_decision.criterion_id == "onset-assessment"
      assert second_decision.criterion_id == "second"
      assert second_decision.actions == []
    end

    test "enumerates one answer per performed action when requested" do
      request = %{
        questions: [question(%{enumerate_answers: true})],
        evidence_pool: [@learner_turn]
      }

      assert {:ok, [%{answers: [%{evidence_id: "turn-1", action_id: "ask-onset"}]}]} =
               JevDecision.decide_rubric_batch(request, @opts)
    end

    test "enumerates no answers without learner evidence" do
      request = %{questions: [question(%{enumerate_answers: true})], evidence_pool: []}

      assert {:ok, [%{answers: []}]} = JevDecision.decide_rubric_batch(request, @opts)
    end
  end

  describe "decide_rubric/1" do
    test "awards the last authored class, citing only an allowed learner item" do
      request = %{
        criterion: %{id: "onset-assessment"},
        allowed_classes: ["inadequado", "adequado", "uncertain"],
        allowed_evidence_ids: ["turn-3"],
        evidence_pool: [@learner_turn, @patient_turn, %{@learner_turn | id: "turn-3"}]
      }

      assert {:ok, %{classification: "adequado", evidence_ids: ["turn-3"]}} =
               JevDecision.decide_rubric(request, @opts)
    end

    test "stays uncertain and cites nothing without allowed learner evidence" do
      request = %{
        criterion: %{id: "onset-assessment"},
        allowed_classes: ["inadequado", "adequado", "uncertain"],
        allowed_evidence_ids: [],
        evidence_pool: [@learner_turn]
      }

      assert {:ok, %{classification: "uncertain", evidence_ids: []}} =
               JevDecision.decide_rubric(request, @opts)
    end
  end

  describe "assessment of the active station package" do
    test "yields a fully assessed, grounded result for a session with a learner turn" do
      package = Backend.Stations.get_active_package()

      session = %{
        messages: [
          %{role: :learner, modality: "text", text: "Quando começou a dor no peito?"},
          %{role: :patient, modality: "text", text: "A dor começou durante uma caminhada."}
        ]
      }

      assert {:ok, %{criteria: criteria, estimates: estimates}} =
               RubricAssessment.assess(package, session, @opts)

      assert criteria != []
      assert Enum.all?(criteria, &(&1.status == :assessed and &1.evidence_ids == ["turn-1"]))
      assert estimates.unresolved == []
    end
  end
end
