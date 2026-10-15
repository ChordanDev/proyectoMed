defmodule Backend.Stations.RubricAssessment.Issue228RegressionTest do
  @moduledoc """
  Regression harness for issue #228: an acute-appendicitis attempt graded
  through `RubricAssessment.assess/3` with the real TypeSafe adapter behind a
  `Req.Test` stub and a recorded rubric resolver, both answering from
  `fixtures/issue_228_session.json`.

  The recorded answers reproduce the mechanism observed live on 2026-10-15:
  TypeSafe answers middle noul values for actions the learner clearly
  performed in items 2, 5, 6 and 7, the resolver answers `not_performed`
  without evidence for most of them, and the `min_actions` range collapse turns
  the rest into a confident zero.
  """
  use ExUnit.Case, async: true

  alias Backend.Stations.JevDecision.TypesafeAdapter
  alias Backend.Stations.Qualification
  alias Backend.Stations.RubricAssessment
  alias Backend.Stations.RubricAssessment.Evidence

  @moduletag capture_log: true

  @fixture_path Path.expand("fixtures/issue_228_session.json", __DIR__)
  @package_path Path.expand(
                  "../../../../priv/stations/acute-appendicitis/package.json",
                  __DIR__
                )
  @learner_roles [:learner, :student, "learner", "student"]
  @wrongly_zeroed ["item-02", "item-05", "item-06", "item-07"]

  # ============================================================================
  # Recorded resolver
  # ============================================================================

  defmodule RecordedResolver do
    @moduledoc """
    Answers each undecided action with the classification recorded in
    `opts[:decisions]` (`criterion_id => %{action_id => classification}`),
    always without evidence, and leaves unrecorded actions unanswered. Every
    request is reported to `opts[:test_pid]`.
    """
    @behaviour Backend.Stations.RubricAssessment.Resolver

    @impl true
    def resolve(request, opts) do
      send(opts[:test_pid], {:resolver_request, request})
      decisions = opts[:decisions]

      actions =
        for criterion <- request.criteria,
            id <- criterion.decidable_action_ids,
            classification = get_in(decisions, [criterion.id, id]),
            classification != nil do
          %{criterion_id: criterion.id, id: id, classification: classification, evidence_ids: []}
        end

      {:ok, %{actions: actions}}
    end
  end

  # ============================================================================
  # Helpers (shared with the #228 follow-up tasks)
  # ============================================================================

  defp fixture, do: @fixture_path |> File.read!() |> Jason.decode!()

  defp package, do: @package_path |> File.read!() |> Jason.decode!()

  # The session the fixture turns leave, built as a live attempt would build it:
  # Impressos turns become request events decided by the real keyword match.
  defp session(fixture, package), do: Qualification.session(fixture["turns"], package)

  # Runs the assessment with the recorded TypeSafe and resolver answers. `opts`
  # override the assessment options.
  defp assess(fixture, package, stub_name, opts \\ []) do
    recorded = fixture["recorded"]

    base =
      [
        adapter: TypesafeAdapter,
        resolver_adapter: RecordedResolver,
        resolver_opts: [test_pid: self(), decisions: recorded["resolver"]]
      ] ++ stub_typesafe(stub_name, fixture, package)

    RubricAssessment.assess(package, session(fixture, package), Keyword.merge(base, opts))
  end

  # A `Req.Test` stub of the TypeSafe API that answers every noul question from
  # the recorded `typesafe_noul` map (`criterion_id => action_id => turn key =>
  # noul`), with `typesafe_default_noul` for any pair not recorded. The question's
  # action is matched to an authored action by its exact description, and its item
  # to a fixture turn by its exact text. Each request payload is reported to the
  # test process.
  defp stub_typesafe(name, fixture, package) do
    test_pid = self()
    recorded = fixture["recorded"]
    actions = actions_by_description(package)
    keys = Map.new(for(%{"key" => key, "text" => text} <- fixture["turns"], do: {text, key}))

    Req.Test.stub(name, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(raw)
      send(test_pid, {:typesafe_request, payload})
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

  # Authored action descriptions are unique in the package, so each question's
  # action text identifies exactly one `{criterion_id, action_id}`.
  defp actions_by_description(package) do
    pairs =
      for %{"id" => criterion_id} = criterion <- package["rubric"],
          %{"id" => action_id, "description" => description} <- criterion["actions"] || [] do
        {description, {criterion_id, action_id}}
      end

    by_description = Map.new(pairs)
    true = map_size(by_description) == length(pairs)
    by_description
  end

  defp criterion(%{criteria: criteria}, id), do: Enum.find(criteria, &(&1.id == id))

  # The learner inputs the fixture records, in order: typed or spoken learner
  # turns and Impressos requests.
  defp learner_inputs(fixture) do
    for %{"role" => "learner", "text" => text} <- fixture["turns"], do: text
  end

  # ============================================================================
  # Input completeness
  # ============================================================================

  describe "input completeness" do
    test "every learner turn and releasing Impressos request reaches the pool and TypeSafe" do
      fixture = fixture()
      package = package()
      session = session(fixture, package)

      assert length(session.impresso_requests) == 3
      assert Enum.all?(session.impresso_requests, &(&1.released_ids != []))

      offered =
        for item <- Evidence.build(session, package),
            item.role in @learner_roles and item.provenance != :unverified,
            do: item.text

      assert offered == learner_inputs(fixture)

      assert {:ok, _assessment} = assess(fixture, package, Issue228CompletenessStub)
      assert_received {:typesafe_request, payload}
      assert Enum.map(payload["state"]["learner_items"], & &1["text"]) == learner_inputs(fixture)
    end
  end

  # ============================================================================
  # Characterization baseline
  # ============================================================================

  # CURRENT (WRONG) BEHAVIOR. These assertions encode the grades issue #228
  # reports, so that its follow-up tasks change behavior test-first:
  #
  #   * T3 flips item 6: its lab actions become `performed` deterministically,
  #     citing the verified Impressos request that released them.
  #   * T4 flips items 2, 5, 6 and 7: a resolver-only `not_performed` can no
  #     longer collapse a criterion to an assessed zero-point level, so the
  #     criterion becomes `:uncertain`.
  #
  # Update these tests in those tasks instead of deleting them.
  describe "characterization baseline (wrong grades of issue #228)" do
    setup do
      fixture = fixture()
      {:ok, assessment} = assess(fixture, package(), Issue228BaselineStub)
      %{fixture: fixture, assessment: assessment}
    end

    test "items 2, 5, 6 and 7 are assessed at their zero-point level with no evidence",
         %{assessment: assessment} do
      for id <- @wrongly_zeroed do
        result = criterion(assessment, id)

        assert %{status: :assessed, level: "inadequado", points: 0, reason: nil} = result,
               "#{id}: #{inspect(Map.take(result, [:status, :level, :reason]))}"

        assert result.evidence_ids == []
        assert result.evidence == []
      end
    end

    test "the zeros rest on resolver not_performed decisions without evidence",
         %{fixture: fixture, assessment: assessment} do
      assert_received {:resolver_request, request}
      assert Enum.map(request.criteria, & &1.id) == @wrongly_zeroed

      for id <- @wrongly_zeroed do
        sub_actions = Map.new(criterion(assessment, id).sub_actions, &{&1.id, &1})

        for {action_id, "not_performed"} <- fixture["recorded"]["resolver"][id] do
          assert %{classification: "not_performed", evidence_ids: []} = sub_actions[action_id]
        end

        refute Enum.any?(Map.values(sub_actions), &(&1.classification == "performed"))
      end
    end
  end
end
