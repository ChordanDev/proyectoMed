defmodule Backend.Stations.RubricAssessment.Issue228RegressionTest do
  @moduledoc """
  Regression harness for issue #228: an acute-appendicitis attempt graded
  through `RubricAssessment.assess/3` with the real TypeSafe adapter behind a
  `Req.Test` stub and a recorded rubric resolver, both answering from
  `fixtures/issue_228_session.json`.

  The recorded answers reproduce the mechanism observed live on 2026-10-15:
  TypeSafe answers middle noul values for actions the learner clearly
  performed in items 2, 5, 6 and 7, the resolver answers `not_performed`
  without evidence for most of them, and the `min_actions` range collapse turned
  the rest into a confident zero. T3 grades item 6 from its lab request; T4
  reports items 2, 5 and 7 as uncertain, since their zero rests only on the
  resolver's `not_performed` answers.
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
  @wrongly_zeroed ["item-02", "item-05", "item-07"]
  @labs "item-06"
  @lab_request "impresso-qualification-request-2"

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

  # Every TypeSafe request payload received so far, in order.
  defp typesafe_payloads do
    receive do
      {:typesafe_request, payload} -> [payload | typesafe_payloads()]
    after
      0 -> []
    end
  end

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
  # No confident zero without proof (T4)
  # ============================================================================

  # Items 2, 5 and 7 used to be assessed `inadequado` (0 points) with no
  # evidence: the resolver answered `not_performed` without evidence for most of
  # their actions, and the `min_actions` range collapse turned the rest into a
  # confident zero. A zero-point level that only the resolver's `not_performed`
  # answers reach is reported as uncertain instead.
  describe "zeros resting on resolver not_performed answers" do
    setup do
      fixture = fixture()
      {:ok, assessment} = assess(fixture, package(), Issue228UnprovenZeroStub)
      %{fixture: fixture, assessment: assessment}
    end

    test "items 2, 5 and 7 are uncertain instead of assessed at zero",
         %{assessment: assessment} do
      for id <- @wrongly_zeroed do
        result = criterion(assessment, id)

        assert %{status: :uncertain, reason: {:uncertain_sub_action, _action_id}} = result,
               "#{id}: #{inspect(Map.take(result, [:status, :level, :reason]))}"

        refute Map.has_key?(result, :level)
        refute Map.has_key?(result, :points)
        assert result.evidence_ids == []
      end
    end

    test "the reason names an action the resolver answered not_performed",
         %{fixture: fixture, assessment: assessment} do
      assert_received {:resolver_request, request}
      assert Enum.map(request.criteria, & &1.id) == @wrongly_zeroed

      for id <- @wrongly_zeroed do
        {:uncertain_sub_action, action_id} = criterion(assessment, id).reason
        assert fixture["recorded"]["resolver"][id][action_id] == "not_performed"
      end
    end
  end

  # ============================================================================
  # Lever 2 (T3): lab requests decided by released impressos
  # ============================================================================

  describe "lab requests decided by released impressos" do
    setup do
      fixture = fixture()
      package = package()
      {:ok, assessment} = assess(fixture, package, Issue228LabsStub)
      %{package: package, assessment: assessment}
    end

    test "item 6 is assessed at its top level, citing the lab request",
         %{assessment: assessment} do
      result = criterion(assessment, @labs)

      assert %{status: :assessed, level: "adequado", points: 32, reason: nil} = result
      assert result.evidence_ids == [@lab_request]

      for sub_action <- result.sub_actions do
        assert %{classification: "performed", evidence_ids: [@lab_request]} = sub_action
      end
    end

    test "neither TypeSafe nor the resolver is asked about item 6",
         %{package: package} do
      actions = actions_by_description(package)
      payloads = typesafe_payloads()
      assert payloads != []

      asked =
        for payload <- payloads,
            {_id, %{"instructions" => %{"action" => action}}} <- payload["questions"],
            uniq: true,
            do: elem(Map.fetch!(actions, action), 0)

      assert "item-02" in asked
      refute @labs in asked

      assert_received {:resolver_request, request}
      refute @labs in Enum.map(request.criteria, & &1.id)
    end
  end
end
