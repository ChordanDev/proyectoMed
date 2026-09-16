defmodule Backend.EvaluatorTest do
  use ExUnit.Case, async: true

  alias Backend.Evaluator

  @fixtures_path Path.expand("../../priv/stations/fixtures", __DIR__)

  defp load_fixture(name) do
    @fixtures_path
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
  end

  defp multi_criteria_package do
    %{
      "station_id" => "chest-pain-comprehensive",
      "version" => "1.0.0",
      "language" => "pt-BR",
      "display_title" => "Avaliação ampla de dor torácica",
      "patient_profile" => %{
        "persona" => "Paciente colaborativo e preocupado",
        "age" => 56,
        "presenting_context" => "Dor torácica iniciada há duas horas.",
        "tone" => "Ansioso"
      },
      "revealable_facts" => [
        %{"topic" => "onset", "content" => "A dor começou durante uma caminhada."},
        %{"topic" => "radiation", "content" => "A dor irradia para o braço esquerdo."}
      ],
      "response_rules" => [
        %{
          "id" => "unknown-fact",
          "instruction" => "Do not invent facts absent from this package."
        }
      ],
      "expected_actions" => [
        %{"id" => "ask-onset", "description" => "Ask when the chest pain began."},
        %{"id" => "ask-radiation", "description" => "Ask if the pain radiates to the arm."}
      ],
      "rubric" => [
        %{
          "id" => "onset-assessment",
          "description" => "Assesses the onset of chest pain.",
          "evidence_questions" => ["When did the pain begin?"],
          "practice_recommendation" =>
            "Practice opening chest pain assessments with onset questions.",
          "weight" => 2
        },
        %{
          "id" => "radiation-assessment",
          "description" => "Investigates whether the chest pain radiates to other areas.",
          "evidence_questions" => ["Does the pain radiate anywhere?"],
          "practice_recommendation" => "Practice inquiring about irradiation of chest pain.",
          "weight" => 2
        }
      ]
    }
  end

  describe "evaluate/2 output contract" do
    test "returns %{criteria: [%{id, status, evidence, recommendation}]}" do
      package = load_fixture("valid-package.json")

      transcript = [
        %{role: :learner, text: "Quando começou a dor no peito?"},
        %{role: :patient, text: "A dor começou durante uma caminhada há duas horas."}
      ]

      result = Evaluator.evaluate(package, transcript)

      assert %{criteria: criteria} = result
      assert is_list(criteria)
      assert length(criteria) == 1

      [criterion] = criteria
      assert criterion.id == "onset-assessment"
      assert criterion.status in [:met, :omitted, :uncertain]
      assert is_list(criterion.evidence)
      assert is_binary(criterion.recommendation)
    end

    test "never includes global score, readiness verdict, weight, or pass/fail claims" do
      package = multi_criteria_package()

      transcript = [
        %{role: :learner, text: "Quando começou a dor no peito?"},
        %{role: :patient, text: "Começou há duas horas."}
      ]

      result = Evaluator.evaluate(package, transcript)

      # Top-level keys must only be :criteria
      assert Map.keys(result) == [:criteria]
      refute Map.has_key?(result, :score)
      refute Map.has_key?(result, :total)
      refute Map.has_key?(result, :grade)
      refute Map.has_key?(result, :verdict)
      refute Map.has_key?(result, :revalida_ready)
      refute Map.has_key?(result, :readiness)
      refute Map.has_key?(result, :passed)
      refute Map.has_key?(result, :failed)

      # Criterion-level keys must strictly be [:evidence, :id, :recommendation, :status]
      for criterion <- result.criteria do
        assert Map.keys(criterion) |> Enum.sort() == [:evidence, :id, :recommendation, :status]
        refute Map.has_key?(criterion, :weight)
        refute Map.has_key?(criterion, :score)
        refute Map.has_key?(criterion, :points)
      end

      # Encoded JSON must not contain forbidden evaluative vocabulary
      encoded = Jason.encode!(result)
      refute encoded =~ "score"
      refute encoded =~ "verdict"
      refute encoded =~ "revalida"
      refute encoded =~ "readiness"
      refute encoded =~ "pass"
      refute encoded =~ "fail"
    end
  end

  describe "evaluate/2 clinical scenarios" do
    test "covers a fully-met station where all rubric criteria are satisfied" do
      package = multi_criteria_package()

      transcript = [
        %{role: :learner, text: "Bom dia, senhor. Quando começou a dor no peito?"},
        %{role: :patient, text: "A dor começou durante uma caminhada há duas horas."},
        %{role: :learner, text: "A dor irradia para o braço esquerdo ou para as costas?"},
        %{role: :patient, text: "Sim, irradia para o braço esquerdo."}
      ]

      result = Evaluator.evaluate(package, transcript)

      assert length(result.criteria) == 2

      onset = Enum.find(result.criteria, &(&1.id == "onset-assessment"))
      assert onset.status == :met
      assert length(onset.evidence) > 0

      assert Enum.all?(onset.evidence, fn e ->
               is_map(e) and Map.has_key?(e, :role) and Map.has_key?(e, :text)
             end)

      assert onset.recommendation ==
               "Practice opening chest pain assessments with onset questions."

      radiation = Enum.find(result.criteria, &(&1.id == "radiation-assessment"))
      assert radiation.status == :met
      assert length(radiation.evidence) > 0
      assert radiation.recommendation == "Practice inquiring about irradiation of chest pain."
    end

    test "covers a partially-omitted station where one criterion is met and another is omitted" do
      package = multi_criteria_package()

      # Only asks about onset; never inquires about radiation
      transcript = [
        %{role: :learner, text: "Olá. Desde quando você está sentindo essa dor?"},
        %{role: :patient, text: "Começou há duas horas."}
      ]

      result = Evaluator.evaluate(package, transcript)

      onset = Enum.find(result.criteria, &(&1.id == "onset-assessment"))
      assert onset.status == :met
      assert length(onset.evidence) > 0

      radiation = Enum.find(result.criteria, &(&1.id == "radiation-assessment"))
      assert radiation.status == :omitted
      assert radiation.evidence == []
      assert radiation.recommendation == "Practice inquiring about irradiation of chest pain."
    end

    test "covers an uncertain criterion when evidence is ambiguous or tentative" do
      package = load_fixture("valid-package.json")

      # Ambiguous / tentative inquiry: mentions uncertainty markers
      transcript = [
        %{role: :learner, text: "A dor começou talvez hoje cedo, não tenho certeza?"},
        %{role: :patient, text: "Mais ou menos há duas horas."}
      ]

      result = Evaluator.evaluate(package, transcript)

      [criterion] = result.criteria
      assert criterion.id == "onset-assessment"
      assert criterion.status == :uncertain
      assert length(criterion.evidence) > 0

      assert criterion.recommendation ==
               "Practice opening chest pain assessments with onset questions."
    end

    test "covers an uncertain criterion when evidence is partial (touches condition without specific inquiry)" do
      package = load_fixture("valid-package.json")

      # Touches chest pain complaint vaguely without actually asking about onset/timing
      transcript = [
        %{role: :learner, text: "Você está com dor no peito agora?"},
        %{role: :patient, text: "Sim, dói bastante."}
      ]

      result = Evaluator.evaluate(package, transcript)

      [criterion] = result.criteria
      assert criterion.id == "onset-assessment"
      assert criterion.status == :uncertain
      assert length(criterion.evidence) > 0

      assert criterion.recommendation ==
               "Practice opening chest pain assessments with onset questions."
    end

    test "covers a transcript with no evidence for a criterion (omitted with empty evidence)" do
      package = load_fixture("valid-package.json")

      transcript = [
        %{role: :learner, text: "Bom dia, senhor. Sou o médico de plantão."},
        %{role: :patient, text: "Bom dia, doutor."}
      ]

      result = Evaluator.evaluate(package, transcript)

      [criterion] = result.criteria
      assert criterion.id == "onset-assessment"
      assert criterion.status == :omitted
      assert criterion.evidence == []

      assert criterion.recommendation ==
               "Practice opening chest pain assessments with onset questions."
    end

    test "returns all criteria as omitted when transcript is empty" do
      package = multi_criteria_package()

      result = Evaluator.evaluate(package, [])

      assert length(result.criteria) == 2

      for criterion <- result.criteria do
        assert criterion.status == :omitted
        assert criterion.evidence == []
        assert is_binary(criterion.recommendation)
        assert criterion.recommendation != ""
      end
    end
  end

  describe "transcript and package flexibility" do
    test "accepts session map with :messages key" do
      package = load_fixture("valid-package.json")

      session = %{
        session_id: "test-session-123",
        messages: [
          %{role: :learner, text: "Quando começou a dor?"},
          %{role: :patient, text: "Há duas horas."}
        ]
      }

      result = Evaluator.evaluate(package, session)

      [criterion] = result.criteria
      assert criterion.status == :met
      assert length(criterion.evidence) > 0
    end

    test "accepts string-keyed transcript messages" do
      package = load_fixture("valid-package.json")

      transcript = [
        %{"role" => "learner", "text" => "Quando começou a dor no peito?"},
        %{"role" => "patient", "text" => "Há duas horas."}
      ]

      result = Evaluator.evaluate(package, transcript)

      [criterion] = result.criteria
      assert criterion.status == :met
      assert [%{role: "learner", text: "Quando começou a dor no peito?"}] = criterion.evidence
    end

    test "accepts atom-keyed package and rubric criteria" do
      package = %{
        station_id: "test-station",
        rubric: [
          %{
            id: "test-criterion",
            description: "Test criterion",
            evidence_questions: ["Did the student test?"],
            practice_recommendation: "Practice testing.",
            weight: 1
          }
        ]
      }

      result = Evaluator.evaluate(package, [])

      assert %{
               criteria: [
                 %{
                   id: "test-criterion",
                   status: :omitted,
                   evidence: [],
                   recommendation: "Practice testing."
                 }
               ]
             } = result
    end
  end

  describe "adapter extension" do
    defmodule CustomTestAdapter do
      @behaviour Backend.Evaluator

      @impl true
      def evaluate(_package, _transcript, _opts) do
        %{
          criteria: [
            %{
              id: "custom-id",
              status: :met,
              evidence: [%{role: :learner, text: "custom evidence"}],
              recommendation: "custom recommendation"
            }
          ]
        }
      end
    end

    test "delegates to configured adapter option" do
      package = load_fixture("valid-package.json")

      result = Evaluator.evaluate(package, [], adapter: CustomTestAdapter)

      assert result == %{
               criteria: [
                 %{
                   id: "custom-id",
                   status: :met,
                   evidence: [%{role: :learner, text: "custom evidence"}],
                   recommendation: "custom recommendation"
                 }
               ]
             }
    end
  end
end
