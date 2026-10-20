defmodule Backend.Stations.RubricAssessment.InterpretationEvidenceTest do
  @moduledoc """
  Issue #265: a learner cannot interpret an exam before receiving it. An action
  authored with `interprets_impresso_ids` accepts as evidence only learner turns
  sent after a verified Impressos request released one of those impressos, for
  Jev's citations and the resolver's alike.
  """
  use ExUnit.Case, async: true

  alias Backend.Stations.RubricAssessment
  alias Backend.Stations.RubricAssessment.InterpretationEvidence

  @moduletag capture_log: true

  @package_path Path.expand(
                  "../../../../priv/stations/acute-appendicitis/package.json",
                  __DIR__
                )
  @history "item-04"
  @lab_request "item-06"
  @lab_interpretation "item-07"
  @interprets %{
    "criterio-1" => ["impresso-2-hemograma"],
    "criterio-2" => ["impresso-2-pcr"],
    "criterio-3" => ["impresso-2-urina-tipo-1"],
    "criterio-4" => ["impresso-2-ureia", "impresso-2-creatinina", "impresso-2-eletrolitos"]
  }
  @all_labs [
    "impresso-2-hemograma",
    "impresso-2-pcr",
    "impresso-2-urina-tipo-1",
    "impresso-2-ureia",
    "impresso-2-creatinina",
    "impresso-2-eletrolitos"
  ]
  @t0 ~U[2026-10-19 12:00:00.000000Z]

  @opener "O que o trouxe aqui hoje? Onde começou a dor?"
  @history_turn "Tem alguma doença crônica? Usa algum medicamento? Tem alergia?"
  @labs_turn "O hemograma mostra leucocitose com desvio à esquerda e a PCR está elevada."

  # ============================================================================
  # Doubles
  # ============================================================================

  defmodule Jev do
    @moduledoc """
    Answers every action from `opts[:answers]` (`criterion_id => action_id =>
    {classification, [learner text]}`), citing the pool items with those texts,
    and `"not_performed"` for any other action. The criterion is always
    `"uncertain"`, as the TypeSafe adapter answers.
    """
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request), do: {:ok, %{status: :verified}}

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}

    @impl true
    def decide_rubric_batch(request), do: decide_rubric_batch(request, [])

    def decide_rubric_batch(request, opts) do
      ids = Map.new(request.evidence_pool, &{&1.text, &1.id})

      decisions =
        for question <- request.questions do
          %{
            criterion_id: question.criterion.id,
            classification: "uncertain",
            evidence_ids: [],
            actions:
              for action <- question.actions do
                {classification, texts} =
                  get_in(opts[:answers], [question.criterion.id, action.id]) ||
                    {"not_performed", []}

                %{
                  id: action.id,
                  classification: classification,
                  evidence_ids: Enum.map(texts, &Map.fetch!(ids, &1))
                }
              end
          }
        end

      {:ok, %{decisions: decisions}}
    end
  end

  defmodule Resolver do
    @moduledoc """
    Answers `"performed"` for each undecided action recorded in
    `opts[:citations]` (`criterion_id => action_id => [learner text]`).
    """
    @behaviour Backend.Stations.RubricAssessment.Resolver

    @impl true
    def resolve(request, opts) do
      ids = Map.new(request.evidence_pool, &{&1.text, &1.id})

      actions =
        for criterion <- request.criteria,
            id <- criterion.decidable_action_ids,
            texts = get_in(opts[:citations] || %{}, [criterion.id, id]),
            texts != nil do
          %{
            criterion_id: criterion.id,
            id: id,
            classification: "performed",
            evidence_ids: Enum.map(texts, &Map.fetch!(ids, &1))
          }
        end

      {:ok, %{actions: actions}}
    end
  end

  # ============================================================================
  # Fixtures
  # ============================================================================

  # The station's rubric limited to `ids`. The dependencies are authored here,
  # so the rule is tested apart from the package content.
  defp package(opts \\ []) do
    ids = Keyword.get(opts, :ids, [@lab_interpretation])
    authored? = Keyword.get(opts, :authored, true)
    package = @package_path |> File.read!() |> Jason.decode!()

    Map.update!(package, "rubric", fn rubric ->
      rubric
      |> Enum.filter(&(&1["id"] in ids))
      |> Enum.map(&author(&1, authored?))
    end)
  end

  defp author(%{"id" => @lab_interpretation} = criterion, authored?) do
    Map.update!(criterion, "actions", fn actions -> Enum.map(actions, &declare(&1, authored?)) end)
  end

  defp author(criterion, _authored?), do: criterion

  defp declare(action, authored?) do
    action = Map.delete(action, "interprets_impresso_ids")

    case {authored?, @interprets[action["id"]]} do
      {true, [_ | _] = ids} -> Map.put(action, "interprets_impresso_ids", ids)
      _undeclared -> action
    end
  end

  defp turn(text, second), do: %{role: :learner, modality: :text, text: text, at: at(second)}

  defp at(second), do: DateTime.add(@t0, second, :second)

  defp release(released_ids, second, overrides \\ %{}) do
    Map.merge(
      %{
        request_id: "request-#{second}",
        station_id: "acute-appendicitis",
        station_version: "2.0.0",
        order: second,
        text: "Solicito exames laboratoriais.",
        released_ids: released_ids,
        at: at(second)
      },
      overrides
    )
  end

  # The opener and the history before the labs are released, the lab
  # interpretation after.
  defp session(releases \\ [release(@all_labs, 5)]) do
    %{
      messages: [
        turn(@opener, 1),
        %{role: :patient, modality: :text, text: "Estou com dor na barriga.", at: at(2)},
        turn(@history_turn, 3),
        turn(@labs_turn, 10)
      ],
      impresso_requests: releases
    }
  end

  defp assess(package, session, answers, citations \\ %{}) do
    {:ok, assessment} =
      RubricAssessment.assess(package, session,
        adapter: Jev,
        answers: answers,
        resolver_adapter: Resolver,
        resolver_opts: [citations: citations]
      )

    assessment
  end

  defp criterion(%{criteria: criteria}, id), do: Enum.find(criteria, &(&1.id == id))

  defp sub_action(result, id), do: Enum.find(result.sub_actions, &(&1.id == id))

  # turn-1 is the opener, turn-3 the history, turn-4 the lab interpretation.
  @opener_id "turn-1"
  @history_id "turn-3"
  @labs_id "turn-4"

  # ============================================================================
  # The rule at the evidence boundary
  # ============================================================================

  describe "Jev's citations of an interpretation action" do
    test "keep only the turns sent after the release, without changing the level" do
      answers = %{
        @lab_interpretation => %{
          "criterio-1" => {"performed", [@opener, @labs_turn]},
          "criterio-2" => {"performed", [@history_turn, @labs_turn]},
          "criterio-3" => {"performed", [@labs_turn]}
        }
      }

      result = package() |> assess(session(), answers) |> criterion(@lab_interpretation)

      assert %{status: :assessed, level: "adequado", evidence_ids: [@labs_id]} = result

      for id <- ["criterio-1", "criterio-2", "criterio-3"] do
        assert %{classification: "performed", evidence_ids: [@labs_id]} = sub_action(result, id)
      end
    end

    test "never raise a level with a turn sent before the release" do
      answers = %{
        @lab_interpretation => %{
          "criterio-1" => {"performed", [@labs_turn]},
          "criterio-2" => {"performed", [@labs_turn]},
          "criterio-3" => {"performed", [@opener]},
          "criterio-4" => {"performed", [@history_turn]}
        }
      }

      # Without the declared dependencies the early turns would earn the top level.
      assert %{level: "adequado"} =
               package(authored: false)
               |> assess(session(), answers)
               |> criterion(@lab_interpretation)

      result = package() |> assess(session(), answers) |> criterion(@lab_interpretation)

      assert %{status: :assessed, level: "parcialmente_adequado", evidence_ids: [@labs_id]} =
               result

      for id <- ["criterio-3", "criterio-4"] do
        assert %{classification: "not_performed", evidence_ids: []} = sub_action(result, id)
      end
    end

    test "do not count an interpretation turn sent before the impresso was released" do
      answers = %{
        @lab_interpretation => %{
          "criterio-1" => {"performed", [@labs_turn]},
          "criterio-2" => {"performed", [@labs_turn]},
          "criterio-3" => {"performed", [@labs_turn]}
        }
      }

      result =
        package()
        |> assess(session([release(@all_labs, 11)]), answers)
        |> criterion(@lab_interpretation)

      assert %{status: :assessed, level: "inadequado", points: 0, evidence_ids: []} = result
      assert Enum.all?(result.sub_actions, &(&1.classification == "not_performed"))
    end

    test "count only after a release of an impresso the action interprets" do
      answers = %{
        @lab_interpretation => %{
          "criterio-1" => {"performed", [@labs_turn]},
          "criterio-2" => {"performed", [@labs_turn]}
        }
      }

      result =
        package()
        |> assess(session([release(["impresso-2-hemograma"], 5)]), answers)
        |> criterion(@lab_interpretation)

      assert %{classification: "performed", evidence_ids: [@labs_id]} =
               sub_action(result, "criterio-1")

      assert %{classification: "not_performed", evidence_ids: []} =
               sub_action(result, "criterio-2")
    end

    test "do not count a release by an unverified request" do
      answers = %{@lab_interpretation => %{"criterio-1" => {"performed", [@labs_turn]}}}
      unverified = release(@all_labs, 5, %{station_version: "1.0.0"})

      result =
        package() |> assess(session([unverified]), answers) |> criterion(@lab_interpretation)

      assert %{classification: "not_performed", evidence_ids: []} =
               sub_action(result, "criterio-1")
    end
  end

  describe "the resolver's citations of an interpretation action" do
    test "keep only the turns sent after the release" do
      answers = %{
        @lab_interpretation => %{
          "criterio-1" => {"performed", [@labs_turn]},
          "criterio-2" => {"performed", [@labs_turn]},
          "criterio-3" => {"uncertain", [@opener, @labs_turn]},
          "criterio-4" => {"uncertain", [@history_turn]}
        }
      }

      citations = %{
        @lab_interpretation => %{
          "criterio-3" => [@opener, @labs_turn],
          "criterio-4" => [@history_turn]
        }
      }

      result =
        package() |> assess(session(), answers, citations) |> criterion(@lab_interpretation)

      assert %{status: :assessed, level: "adequado", evidence_ids: [@labs_id]} = result

      assert %{classification: "performed", evidence_ids: [@labs_id]} =
               sub_action(result, "criterio-3")

      assert %{classification: "not_performed", evidence_ids: []} =
               sub_action(result, "criterio-4")
    end
  end

  describe "actions that interpret nothing" do
    test "request actions and anamnesis items are unaffected" do
      answers = %{
        @history => %{
          "criterio-1" => {"performed", [@opener, @history_turn]},
          "criterio-3" => {"performed", [@history_turn]},
          "criterio-4" => {"performed", [@history_turn]}
        }
      }

      assessment =
        package(ids: [@history, @lab_request, @lab_interpretation])
        |> assess(session(), answers)

      history = criterion(assessment, @history)

      assert %{status: :assessed, level: "parcialmente_adequado"} = history

      assert %{classification: "performed", evidence_ids: [@opener_id, @history_id]} =
               sub_action(history, "criterio-1")

      requests = criterion(assessment, @lab_request)

      assert %{status: :assessed, level: "adequado", evidence_ids: ["impresso-request-5"]} =
               requests

      assert Enum.all?(requests.sub_actions, &(&1.classification == "performed"))
    end
  end

  # ============================================================================
  # The pure rule
  # ============================================================================

  describe "admissible/3" do
    test "keeps the cited ids of an action that interprets nothing" do
      pool = RubricAssessment.Evidence.build(session(), package())

      assert InterpretationEvidence.admissible(pool, [@opener_id, @labs_id], nil) ==
               [@opener_id, @labs_id]
    end

    test "keeps only learner turns after a release of a declared impresso, never the request" do
      pool = RubricAssessment.Evidence.build(session(), package())

      assert InterpretationEvidence.admissible(
               pool,
               [@opener_id, "impresso-request-5", @labs_id],
               ["impresso-2-pcr"]
             ) == [@labs_id]
    end
  end
end
