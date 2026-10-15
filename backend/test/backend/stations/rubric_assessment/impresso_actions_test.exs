defmodule Backend.Stations.RubricAssessment.ImpressoActionsTest do
  @moduledoc """
  Issue #228, lever 2: a rubric action authored with the impresso ids it
  requests is `performed` when a verified Impressos request released one of
  them, citing that request, and no provider is asked about it.
  """
  use ExUnit.Case, async: true

  alias Backend.Stations.RubricAssessment

  @moduletag capture_log: true

  @package_path Path.expand(
                  "../../../../priv/stations/acute-appendicitis/package.json",
                  __DIR__
                )
  @labs "item-06"
  @lab_ids %{
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
  @t0 ~U[2026-10-15 12:00:00.000000Z]

  # ============================================================================
  # Doubles
  # ============================================================================

  defmodule Jev do
    @moduledoc """
    Reports each batch request to `opts[:test_pid]` and classifies every
    question `opts[:classification]` and every action
    `opts[:action_classification]`, both `"uncertain"` by default.
    """
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request), do: {:ok, %{status: :verified}}

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}

    @impl true
    def decide_rubric_batch(request), do: decide_rubric_batch(request, [])

    def decide_rubric_batch(request, opts) do
      send(opts[:test_pid], {:batch_request, request})

      decisions =
        for question <- request.questions do
          %{
            criterion_id: question.criterion.id,
            classification: opts[:classification] || "uncertain",
            evidence_ids: opts[:evidence_ids] || [],
            actions:
              for(
                action <- question.actions,
                do: %{
                  id: action.id,
                  classification: opts[:action_classification] || "uncertain",
                  evidence_ids: []
                }
              )
          }
        end

      {:ok, %{decisions: decisions}}
    end
  end

  defmodule Resolver do
    @moduledoc "Reports each request to `opts[:test_pid]` and decides nothing."
    @behaviour Backend.Stations.RubricAssessment.Resolver

    @impl true
    def resolve(request, opts) do
      send(opts[:test_pid], {:resolver_request, request})
      {:ok, %{actions: []}}
    end
  end

  # ============================================================================
  # Fixtures
  # ============================================================================

  defp package(ids \\ [@labs]) do
    package = @package_path |> File.read!() |> Jason.decode!()

    Map.update!(package, "rubric", fn rubric ->
      rubric |> Enum.filter(&(&1["id"] in ids)) |> Enum.map(&author_lab_ids/1)
    end)
  end

  # Authored here, so the assessment is tested apart from the package content.
  defp author_lab_ids(%{"id" => @labs} = criterion) do
    Map.update!(criterion, "actions", fn actions ->
      Enum.map(actions, &Map.put(&1, "impresso_ids", @lab_ids[&1["id"]]))
    end)
  end

  defp author_lab_ids(criterion), do: criterion

  defp update_criterion(package, id, fun) do
    Map.update!(package, "rubric", fn rubric ->
      Enum.map(rubric, fn
        %{"id" => ^id} = criterion -> fun.(criterion)
        criterion -> criterion
      end)
    end)
  end

  defp event(request_id, released_ids, overrides \\ %{}) do
    Map.merge(
      %{
        request_id: request_id,
        station_id: "acute-appendicitis",
        station_version: "2.0.0",
        order: 1,
        text: "Solicito exames.",
        released_ids: released_ids,
        at: DateTime.add(@t0, 2, :second)
      },
      overrides
    )
  end

  defp session(events) do
    %{
      messages: [
        %{role: :learner, modality: :text, text: "Bom dia, sou o médico.", at: @t0}
      ],
      impresso_requests: events
    }
  end

  defp assess(package, session, opts \\ []) do
    RubricAssessment.assess(
      package,
      session,
      [
        adapter: Jev,
        test_pid: self(),
        resolver_adapter: Resolver,
        resolver_opts: [test_pid: self()]
      ] ++ opts
    )
  end

  defp criterion(%{criteria: criteria}, id), do: Enum.find(criteria, &(&1.id == id))

  defp classifications(result), do: Map.new(result.sub_actions, &{&1.id, &1.classification})

  # ============================================================================
  # Tests
  # ============================================================================

  test "every lab action released by a verified request is performed with no provider call" do
    {:ok, assessment} = assess(package(), session([event("r1", @all_labs)]))

    assert %{status: :assessed, level: "adequado", points: 32, reason: nil} =
             result = criterion(assessment, @labs)

    assert result.evidence_ids == ["impresso-r1"]

    assert result.sub_actions == [
             %{id: "criterio-1", classification: "performed", evidence_ids: ["impresso-r1"]},
             %{id: "criterio-2", classification: "performed", evidence_ids: ["impresso-r1"]},
             %{id: "criterio-3", classification: "performed", evidence_ids: ["impresso-r1"]},
             %{id: "criterio-4", classification: "performed", evidence_ids: ["impresso-r1"]}
           ]

    assert assessment.calls == []
    refute_received {:batch_request, _request}
    refute_received {:resolver_request, _request}
  end

  test "one released id of an action's list is enough" do
    {:ok, assessment} =
      assess(package(), session([event("r1", @all_labs -- ["impresso-2-ureia"])]))

    assert classifications(criterion(assessment, @labs))["criterio-4"] == "performed"
  end

  test "every verified request that released an action's impresso is cited" do
    events = [
      event("r1", ["impresso-2-hemograma", "impresso-2-pcr"]),
      event("r2", ["impresso-2-urina-tipo-1", "impresso-2-ureia"], %{
        order: 2,
        at: DateTime.add(@t0, 3, :second)
      })
    ]

    {:ok, assessment} = assess(package(), session(events))
    result = criterion(assessment, @labs)

    assert result.status == :assessed
    assert result.evidence_ids == ["impresso-r1", "impresso-r2"]

    assert Enum.map(result.sub_actions, & &1.evidence_ids) == [
             ["impresso-r1"],
             ["impresso-r1"],
             ["impresso-r2"],
             ["impresso-r2"]
           ]
  end

  test "only the actions without a matching release reach Jev and the resolver" do
    {:ok, assessment} =
      assess(package(), session([event("r1", ["impresso-2-hemograma", "impresso-2-pcr"])]))

    assert_received {:batch_request, %{questions: [question]}}
    assert question.criterion.id == @labs
    assert Enum.map(question.actions, & &1.id) == ["criterio-3", "criterio-4"]

    assert_received {:resolver_request, %{criteria: [resolver_criterion]}}
    assert Enum.map(resolver_criterion.actions, & &1.id) == ["criterio-3", "criterio-4"]
    assert resolver_criterion.decidable_action_ids == ["criterio-3", "criterio-4"]

    # Two performed and two unresolved actions reach two levels; the first
    # unresolved action in authored order names the uncertainty.
    assert %{status: :uncertain, reason: {:uncertain_sub_action, "criterio-3"}} =
             criterion(assessment, @labs)
  end

  test "the decided actions join the provider's in authored order" do
    {:ok, assessment} =
      assess(
        package(),
        session([event("r1", ["impresso-2-pcr", "impresso-2-creatinina"])]),
        action_classification: "not_performed"
      )

    assert %{status: :assessed, level: "parcialmente_adequado"} =
             result = criterion(assessment, @labs)

    assert result.evidence_ids == ["impresso-r1"]

    assert result.sub_actions == [
             %{id: "criterio-1", classification: "not_performed", evidence_ids: []},
             %{id: "criterio-2", classification: "performed", evidence_ids: ["impresso-r1"]},
             %{id: "criterio-3", classification: "not_performed", evidence_ids: []},
             %{id: "criterio-4", classification: "performed", evidence_ids: ["impresso-r1"]}
           ]
  end

  test "without a matching release the actions go through the provider path unchanged" do
    {:ok, assessment} = assess(package(), session([event("r1", ["impresso-2-glicemia"])]))

    assert_received {:batch_request, %{questions: [question]}}
    assert length(question.actions) == 4
    assert criterion(assessment, @labs).status == :uncertain
  end

  test "an unverified request decides nothing" do
    {:ok, _assessment} =
      assess(package(), session([event("r1", @all_labs, %{station_version: "1.0.0"})]))

    assert_received {:batch_request, %{questions: [question]}}
    assert length(question.actions) == 4
  end

  test "a request that released nothing decides nothing" do
    {:ok, _assessment} = assess(package(), session([event("r1", [])]))

    assert_received {:batch_request, %{questions: [question]}}
    assert length(question.actions) == 4
  end

  test "a request the criterion's modality cannot accept decides nothing" do
    package = update_criterion(package(), @labs, &Map.put(&1, "modality_requirement", "verbal"))

    {:ok, _assessment} = assess(package, session([event("r1", @all_labs)]))

    assert_received {:batch_request, %{questions: [question]}}
    assert length(question.actions) == 4
  end

  # Without thresholds or a mandatory/forbidden role only Jev's level can
  # decide, so the criterion is still asked, with no action left to classify.
  test "a criterion whose level only Jev decides is still asked for its level" do
    package =
      update_criterion(package(), @labs, fn criterion ->
        Map.update!(criterion, "levels", fn levels ->
          Enum.map(levels, &Map.delete(&1, "min_actions"))
        end)
      end)

    {:ok, assessment} =
      assess(package, session([event("r1", @all_labs)]),
        classification: "adequado",
        evidence_ids: ["impresso-r1"]
      )

    assert_received {:batch_request, %{questions: [question]}}
    assert question.actions == []
    refute_received {:resolver_request, _request}

    result = criterion(assessment, @labs)

    assert %{status: :assessed, level: "adequado"} = result
    assert Enum.all?(result.sub_actions, &(&1.classification == "performed"))
  end

  # Jorge review of #228 (CD-C1): a mandatory or forbidden role without thresholds
  # still needs Jev's level when every action is performed, so the criterion is
  # asked instead of ending uncertain.
  test "a criterion with roles but no thresholds is still asked for its level" do
    package =
      update_criterion(package(), @labs, fn criterion ->
        criterion
        |> Map.update!("levels", fn levels ->
          Enum.map(levels, &Map.delete(&1, "min_actions"))
        end)
        |> Map.update!("actions", fn actions ->
          Enum.map(actions, &Map.put(&1, "role", "mandatory"))
        end)
      end)

    {:ok, assessment} =
      assess(package, session([event("r1", @all_labs)]),
        classification: "adequado",
        evidence_ids: ["impresso-r1"]
      )

    assert_received {:batch_request, %{questions: [question]}}
    assert question.actions == []

    assert %{status: :assessed, level: "adequado"} = criterion(assessment, @labs)
  end
end
