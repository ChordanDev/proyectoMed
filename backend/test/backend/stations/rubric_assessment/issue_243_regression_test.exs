defmodule Backend.Stations.RubricAssessment.Issue243RegressionTest do
  @moduledoc """
  Regression harness for issue #243: the learner turns of the 2026-10-19 live
  acute-appendicitis attempt graded through `RubricAssessment.assess/3` with
  the real TypeSafe adapter behind a `Req.Test` stub and a recorded rubric
  resolver, both answering from `fixtures/issue_243_session.json`.

  Live, items 7 (lab interpretation) and 10 (antibiotic and surgical referral)
  cited the opener "O que o trouxe aqui hoje? Onde começou a dor?". The live
  provider answers were not logged, so the harness reproduces the only path
  that could cite an unrelated item by construction: TypeSafe leaves some of
  their actions undecided on the turn that performs them and answers no for
  the opener, and the resolver cites the opener beside, or instead of, the
  performing turn. A TypeSafe yes for the opener itself would be a per-item
  provider error this harness does not cover.
  """
  use ExUnit.Case, async: true

  alias Backend.Stations.JevDecision.TypesafeAdapter
  alias Backend.Stations.Qualification
  alias Backend.Stations.RubricAssessment

  @moduletag capture_log: true

  @fixture_path Path.expand("fixtures/issue_243_session.json", __DIR__)
  @package_path Path.expand(
                  "../../../../priv/stations/acute-appendicitis/package.json",
                  __DIR__
                )
  @opener "O que o trouxe aqui hoje? Onde começou a dor?"
  @labs "item-07"
  @antibiotic "item-10"

  # ============================================================================
  # Recorded resolver
  # ============================================================================

  defmodule RecordedResolver do
    @moduledoc """
    Answers `"performed"` for each undecided action recorded in
    `opts[:citations]` (`criterion_id => %{action_id => [turn key]}`), citing
    the pool items whose text is the text of those fixture turns
    (`opts[:texts]`, `turn key => text`), and leaves every other action
    unanswered.
    """
    @behaviour Backend.Stations.RubricAssessment.Resolver

    @impl true
    def resolve(request, opts) do
      ids = Map.new(request.evidence_pool, &{&1.text, &1.id})

      actions =
        for criterion <- request.criteria,
            id <- criterion.decidable_action_ids,
            keys = get_in(opts[:citations], [criterion.id, id]),
            keys != nil do
          evidence_ids = Enum.map(keys, &Map.fetch!(ids, Map.fetch!(opts[:texts], &1)))

          %{
            criterion_id: criterion.id,
            id: id,
            classification: "performed",
            evidence_ids: evidence_ids
          }
        end

      {:ok, %{actions: actions}}
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp fixture, do: @fixture_path |> File.read!() |> Jason.decode!()

  defp package, do: @package_path |> File.read!() |> Jason.decode!()

  defp texts(fixture),
    do: Map.new(for(%{"key" => k, "text" => t} <- fixture["turns"], do: {k, t}))

  # Runs the assessment with the recorded TypeSafe answers and the resolver
  # citations recorded under `scenario`.
  defp assess(scenario, stub_name) do
    fixture = fixture()
    package = package()

    opts =
      [
        adapter: TypesafeAdapter,
        resolver_adapter: RecordedResolver,
        resolver_opts: [
          citations: fixture["recorded"]["resolver"][scenario],
          texts: texts(fixture)
        ]
      ] ++ stub_typesafe(stub_name, fixture, package)

    session = Qualification.session(fixture["turns"], package)
    {:ok, assessment} = RubricAssessment.assess(package, session, opts)
    {assessment, session}
  end

  # A `Req.Test` stub of the TypeSafe API answering every noul question from the
  # recorded `typesafe_noul` map (`criterion_id => action_id => turn key =>
  # noul`), with `typesafe_default_noul` for any pair not recorded.
  defp stub_typesafe(name, fixture, package) do
    recorded = fixture["recorded"]
    actions = actions_by_description(package)
    keys = Map.new(texts(fixture), fn {key, text} -> {text, key} end)

    Req.Test.stub(name, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(raw)
      texts = Map.new(payload["state"]["learner_items"], &{&1["item"], &1["text"]})

      answers =
        Map.new(payload["questions"], fn {id, %{"instructions" => instructions}} ->
          {criterion_id, action_id} = Map.fetch!(actions, instructions["action"])
          key = Map.fetch!(keys, Map.fetch!(texts, instructions["item"]))

          noul =
            get_in(recorded, ["typesafe_noul", criterion_id, action_id, key]) ||
              recorded["typesafe_default_noul"]

          {id, %{"type" => "noul", "noul" => noul}}
        end)

      Req.Test.json(conn, %{"answers" => answers})
    end)

    [api_key: "ts-test-key", plug: {Req.Test, name}]
  end

  defp actions_by_description(package) do
    Map.new(
      for %{"id" => criterion_id} = criterion <- package["rubric"],
          %{"id" => action_id, "description" => description} <- criterion["actions"] || [],
          do: {description, {criterion_id, action_id}}
    )
  end

  defp criterion(%{criteria: criteria}, id), do: Enum.find(criteria, &(&1.id == id))

  # The evidence id the session gives the learner turn with this text.
  defp turn_id(session, text) do
    index = Enum.find_index(session.messages, &(&1.text == text))
    "turn-#{index + 1}"
  end

  defp cited_ids(result) do
    Enum.uniq(result.evidence_ids ++ Enum.flat_map(result.sub_actions, & &1.evidence_ids))
  end

  # ============================================================================
  # The resolver cites the opener beside the performing turn
  # ============================================================================

  describe "a resolver citing the opener beside the performing turn" do
    setup do
      {assessment, session} = assess("opener_beside_performing_turn", Issue243BesideStub)
      %{assessment: assessment, session: session}
    end

    test "items 7 and 10 do not cite the opener", %{assessment: assessment, session: session} do
      opener = turn_id(session, @opener)

      for id <- [@labs, @antibiotic] do
        result = criterion(assessment, id)

        refute opener in cited_ids(result),
               "#{id} cites the opener: #{inspect(cited_ids(result))}"
      end
    end

    test "items 7 and 10 keep their top level, citing the performing turns",
         %{assessment: assessment, session: session} do
      labs = turn_id(session, fixture_text("lab-interpretation"))
      plan = turn_id(session, fixture_text("surgery-antibiotic"))

      assert %{status: :assessed, level: "adequado", points: 32, evidence_ids: [^labs]} =
               criterion(assessment, @labs)

      assert %{status: :assessed, level: "adequado", points: 48, evidence_ids: [^plan]} =
               criterion(assessment, @antibiotic)

      for {id, action_id, performing} <- [
            {@labs, "criterio-4", labs},
            {@antibiotic, "criterio-2", plan},
            {@antibiotic, "criterio-3", plan}
          ] do
        sub_action = Enum.find(criterion(assessment, id).sub_actions, &(&1.id == action_id))
        assert %{classification: "performed", evidence_ids: [^performing]} = sub_action
      end
    end
  end

  # ============================================================================
  # The resolver cites only the opener
  # ============================================================================

  describe "a resolver citing only the opener" do
    setup do
      {assessment, session} = assess("opener_only", Issue243OnlyStub)
      %{assessment: assessment, session: session}
    end

    test "never raises a level: item 10 stays uncertain", %{assessment: assessment} do
      result = criterion(assessment, @antibiotic)

      assert %{status: :uncertain} = result
      refute Map.has_key?(result, :points)

      for action_id <- ["criterio-2", "criterio-3"] do
        refute Enum.any?(
                 Map.get(result, :sub_actions, []),
                 &(&1.id == action_id and &1.classification == "performed")
               )
      end
    end

    test "item 7 keeps the level its performing turn earns, without the opener",
         %{assessment: assessment, session: session} do
      labs = turn_id(session, fixture_text("lab-interpretation"))
      result = criterion(assessment, @labs)

      assert %{status: :assessed, level: "adequado", evidence_ids: [^labs]} = result

      assert %{classification: "uncertain", evidence_ids: []} =
               Enum.find(result.sub_actions, &(&1.id == "criterio-4"))
    end
  end

  defp fixture_text(key), do: Map.fetch!(texts(fixture()), key)
end
