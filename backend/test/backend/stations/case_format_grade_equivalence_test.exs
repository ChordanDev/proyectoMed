defmodule Backend.Stations.CaseFormatGradeEquivalenceTest do
  @moduledoc """
  Grade equivalence of the reference case (issue #330): on the stored
  transcripts of the #228 and #243 regression harnesses, the package parsed
  from `case.md` yields the same criterion statuses, levels, points, evidence
  and estimates as the hand-tuned `package.json`.

  Both runs use the real TypeSafe adapter behind a `Req.Test` stub and a
  recorded rubric resolver, exactly as those harnesses do.
  """
  use ExUnit.Case, async: true

  alias Backend.Stations
  alias Backend.Stations.JevDecision.TypesafeAdapter
  alias Backend.Stations.Qualification
  alias Backend.Stations.RubricAssessment

  @moduletag capture_log: true

  @station_dir Path.expand("../../../priv/stations/acute-appendicitis", __DIR__)
  @fixtures_dir Path.expand("rubric_assessment/fixtures", __DIR__)

  # ============================================================================
  # Recorded resolvers
  # ============================================================================

  defmodule ClassificationResolver do
    @moduledoc """
    The #228 resolver: answers each recorded undecided action with its recorded
    classification (`opts[:decisions]`), without evidence.
    """
    @behaviour Backend.Stations.RubricAssessment.Resolver

    @impl true
    def resolve(request, opts) do
      actions =
        for criterion <- request.criteria,
            id <- criterion.decidable_action_ids,
            classification = get_in(opts[:decisions], [criterion.id, id]),
            classification != nil do
          %{criterion_id: criterion.id, id: id, classification: classification, evidence_ids: []}
        end

      {:ok, %{actions: actions}}
    end
  end

  defmodule CitationResolver do
    @moduledoc """
    The #243 resolver: answers `"performed"` for each recorded undecided action,
    citing the pool items whose text is that of the recorded turns.
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

  defp hand_tuned,
    do: @station_dir |> Path.join("package.json") |> File.read!() |> Jason.decode!()

  defp parsed do
    {:ok, package} = @station_dir |> Path.join("case.md") |> File.read!() |> Stations.parse_case()
    package
  end

  defp fixture(name), do: @fixtures_dir |> Path.join(name) |> File.read!() |> Jason.decode!()

  defp texts(fixture),
    do: Map.new(for(%{"key" => k, "text" => t} <- fixture["turns"], do: {k, t}))

  # The graded outcome of `fixture` under `package`: every criterion result and
  # the estimates.
  defp grade(package, fixture, resolver, stub_name, noul_key) do
    opts =
      [adapter: TypesafeAdapter, resolver_adapter: resolver.adapter, resolver_opts: resolver.opts] ++
        stub_typesafe(stub_name, fixture, package, noul_key)

    session = Qualification.session(fixture["turns"], package)
    {:ok, assessment} = RubricAssessment.assess(package, session, opts)
    Map.take(assessment, [:criteria, :estimates])
  end

  # A `Req.Test` stub of the TypeSafe API answering every noul question from the
  # recorded `noul_key` map, with `typesafe_default_noul` for any pair not
  # recorded.
  defp stub_typesafe(name, fixture, package, noul_key) do
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
            get_in(recorded, [noul_key, criterion_id, action_id, key]) ||
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

  defp assert_same_grades(fixture, resolver, noul_key, stub_names) do
    {hand_tuned_stub, parsed_stub} = stub_names
    expected = grade(hand_tuned(), fixture, resolver, hand_tuned_stub, noul_key)
    actual = grade(parsed(), fixture, resolver, parsed_stub, noul_key)

    assert length(expected.criteria) == 11

    for {want, got} <- Enum.zip(expected.criteria, actual.criteria) do
      assert got == want, "#{want.id} differs"
    end

    assert actual == expected
  end

  # ============================================================================
  # Stored transcripts
  # ============================================================================

  test "the #228 transcript grades the same under both packages" do
    fixture = fixture("issue_228_session.json")

    resolver = %{
      adapter: ClassificationResolver,
      opts: [decisions: fixture["recorded"]["resolver"]]
    }

    assert_same_grades(
      fixture,
      resolver,
      "typesafe_noul",
      {Equivalence228Hand, Equivalence228Parsed}
    )
  end

  for {scenario, noul_key} <- [
        {"none", "typesafe_noul"},
        {"opener_beside_performing_turn", "typesafe_noul"},
        {"opener_only", "typesafe_noul"},
        {"none", "typesafe_noul_issue_265"}
      ] do
    @scenario scenario
    @noul_key noul_key

    test "the #243 transcript grades the same under both packages (#{scenario}, #{noul_key})" do
      fixture = fixture("issue_243_session.json")

      resolver = %{
        adapter: CitationResolver,
        opts: [citations: fixture["recorded"]["resolver"][@scenario], texts: texts(fixture)]
      }

      stubs =
        {:"Equivalence243Hand.#{@scenario}.#{@noul_key}",
         :"Equivalence243Parsed.#{@scenario}.#{@noul_key}"}

      assert_same_grades(fixture, resolver, @noul_key, stubs)
    end
  end
end
