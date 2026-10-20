defmodule Backend.Stations.RubricAssessment.ResolverTest do
  use ExUnit.Case, async: true

  alias Backend.Stations.RubricAssessment
  alias Backend.Stations.RubricAssessment.Points
  alias Backend.Stations.RubricAssessment.Resolver

  @moduletag capture_log: true

  @history "history-taking"
  @treatment "treatment-plan"
  @stations_path Path.expand("../../../../priv/stations", __DIR__)

  @t0 ~U[2026-01-10 12:00:00.000000Z]
  @t1 ~U[2026-01-10 12:00:01.000000Z]
  @t2 ~U[2026-01-10 12:00:02.000000Z]

  # ============================================================================
  # Doubles
  # ============================================================================

  defmodule JevDouble do
    @moduledoc "Answers every rubric batch question from `opts[:answers]`."
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request), do: {:ok, %{status: :verified}}

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}

    @impl true
    def decide_rubric_batch(request), do: decide_rubric_batch(request, [])

    def decide_rubric_batch(request, opts) do
      answers = opts[:answers] || %{}

      decisions =
        Enum.map(request.questions, fn question ->
          Map.merge(
            %{
              criterion_id: question.criterion.id,
              classification: "uncertain",
              evidence_ids: [],
              actions:
                Enum.map(
                  question.actions,
                  &%{id: &1.id, classification: "uncertain", evidence_ids: []}
                )
            },
            Map.get(answers, question.criterion.id, %{})
          )
        end)

      {:ok, %{decisions: decisions}}
    end
  end

  defmodule ResolverDouble do
    @moduledoc """
    Reports every request to `opts[:test_pid]` and replies with `opts[:reply]`
    (a term or a one-arity function of the request).
    """
    @behaviour Backend.Stations.RubricAssessment.Resolver

    @impl true
    def resolve(request, opts) do
      if pid = opts[:test_pid], do: send(pid, {:resolver_request, request})

      case opts[:reply] do
        fun when is_function(fun, 1) -> fun.(request)
        reply -> reply
      end
    end
  end

  # ============================================================================
  # Fixtures
  # ============================================================================

  # history-taking: thresholds 0/2/3 for 0/0.5/1, `ask-onset` mandatory, verbal.
  # treatment-plan: 0/1 without thresholds, one counted and one forbidden action.
  defp rules do
    package =
      @stations_path
      |> Path.join("fixtures/valid-package-v2-authored-rules.json")
      |> File.read!()
      |> Jason.decode!()

    Map.update!(package, "rubric", fn rubric ->
      Enum.filter(rubric, &(&1["id"] in [@history, @treatment]))
    end)
  end

  # turn-1 learner, turn-2 patient, turn-3 learner.
  defp session do
    %{
      messages: [
        %{role: :learner, modality: :text, text: "Quando começou a dor?", at: @t0},
        %{role: :patient, modality: :text, text: "Começou há duas horas.", at: @t1},
        %{role: :learner, modality: :text, text: "A dor é forte?", at: @t2}
      ],
      impresso_requests: []
    }
  end

  defp performed(id, evidence_ids),
    do: %{id: id, classification: "performed", evidence_ids: evidence_ids}

  defp not_performed(id), do: %{id: id, classification: "not_performed", evidence_ids: []}
  defp uncertain(id), do: %{id: id, classification: "uncertain", evidence_ids: []}

  # Two actions performed with evidence, `ask-intensity` undecided and
  # `ask-relief` not performed: the count ranges from two to three, so the
  # criterion depends on `ask-intensity`.
  defp history_actions do
    [
      performed("ask-onset", ["turn-1"]),
      performed("ask-duration", ["turn-3"]),
      uncertain("ask-intensity"),
      not_performed("ask-relief")
    ]
  end

  # treatment-plan is decided clearly, so only history-taking has undecided
  # actions.
  defp jev_answers(actions \\ history_actions()) do
    %{
      @history => %{classification: "uncertain", evidence_ids: [], actions: actions},
      @treatment => %{
        classification: "inadequado",
        evidence_ids: [],
        actions: [not_performed("indicate-expected"), not_performed("indicate-contraindicated")]
      }
    }
  end

  defp resolved(decisions), do: {:ok, %{actions: decisions}}

  defp llm(id, classification, evidence_ids, criterion_id \\ @history) do
    %{
      criterion_id: criterion_id,
      id: id,
      classification: classification,
      evidence_ids: evidence_ids
    }
  end

  defp assess(reply, opts \\ []) do
    answers = Keyword.get(opts, :answers, jev_answers())

    assert {:ok, assessment} =
             RubricAssessment.assess(
               rules(),
               session(),
               [
                 adapter: JevDouble,
                 answers: answers,
                 resolver_adapter: Keyword.get(opts, :resolver_adapter, ResolverDouble),
                 resolver_opts: [test_pid: self(), reply: reply]
               ] ++ Keyword.drop(opts, [:answers, :resolver_adapter])
             )

    assessment
  end

  defp history(assessment), do: Enum.find(assessment.criteria, &(&1.id == @history))

  defp action(result, id), do: Enum.find(result.sub_actions, &(&1.id == id))

  defp assert_still_uncertain(assessment) do
    result = history(assessment)

    assert result.status == :uncertain
    assert result.reason == {:uncertain_sub_action, "ask-intensity"}
  end

  # ============================================================================
  # Request
  # ============================================================================

  describe "the resolver request" do
    test "carries only criteria with undecided actions, their decidable ids and learner evidence" do
      assess(resolved([]))

      assert_received {:resolver_request, request}

      assert [criterion] = request.criteria
      assert criterion.id == @history
      assert criterion.decidable_action_ids == ["ask-intensity"]

      assert Enum.map(criterion.actions, &{&1.id, &1.classification}) == [
               {"ask-onset", "performed"},
               {"ask-duration", "performed"},
               {"ask-intensity", "uncertain"},
               {"ask-relief", "not_performed"}
             ]

      assert Enum.find(criterion.actions, &(&1.id == "ask-intensity")).description ==
               "Ask about intensity."

      assert request.evidence_pool == [
               %{id: "turn-1", text: "Quando começou a dor?"},
               %{id: "turn-3", text: "A dor é forte?"}
             ]
    end

    test "is not sent when Jev left no action undecided" do
      actions = List.replace_at(history_actions(), 2, not_performed("ask-intensity"))

      assessment = assess(resolved([]), answers: jev_answers(actions))

      refute_received {:resolver_request, _request}
      assert history(assessment).level == "parcialmente_adequado"
    end
  end

  # ============================================================================
  # Merge
  # ============================================================================

  describe "merging the resolver decisions" do
    test "a performed action with a valid learner citation is credited" do
      result = assess(resolved([llm("ask-intensity", "performed", ["turn-3"])])) |> history()

      assert result.status == :assessed
      assert result.level == "adequado"
      assert result.points == 40
      assert action(result, "ask-intensity") == performed("ask-intensity", ["turn-3"])
    end

    test "a not performed action is taken without evidence" do
      result =
        assess(resolved([llm("ask-intensity", "not_performed", ["turn-3"])])) |> history()

      assert result.status == :assessed
      assert result.level == "parcialmente_adequado"
      assert result.points == 20
      assert action(result, "ask-intensity") == not_performed("ask-intensity")
    end

    test "an uncertain answer leaves the action undecided" do
      assess(resolved([llm("ask-intensity", "uncertain", [])])) |> assert_still_uncertain()
    end

    test "a performed action citing an unknown id stays uncertain" do
      assess(resolved([llm("ask-intensity", "performed", ["turn-99"])]))
      |> assert_still_uncertain()
    end

    test "a performed action citing a patient turn stays uncertain" do
      assess(resolved([llm("ask-intensity", "performed", ["turn-3", "turn-2"])]))
      |> assert_still_uncertain()
    end

    test "a performed action without a citation stays uncertain" do
      assess(resolved([llm("ask-intensity", "performed", [])])) |> assert_still_uncertain()
    end

    test "a decision on an action Jev decided clearly is ignored" do
      result =
        assess(
          resolved([
            llm("ask-relief", "performed", ["turn-3"]),
            llm("ask-onset", "not_performed", [])
          ])
        )
        |> history()

      assert result.reason == {:uncertain_sub_action, "ask-intensity"}

      # The uncertain criterion reports its actions (issue #291): Jev's clear
      # answers stand over the resolver's.
      assert Map.new(result.sub_actions, &{&1.id, &1.classification}) == %{
               "ask-onset" => "performed",
               "ask-duration" => "performed",
               "ask-intensity" => "uncertain",
               "ask-relief" => "not_performed"
             }
    end

    test "decisions on unknown actions or criteria are ignored" do
      result =
        assess(
          resolved([
            llm("ask-unknown", "performed", ["turn-3"]),
            llm("ask-intensity", "performed", ["turn-3"], @treatment),
            llm("ask-intensity", "not_performed", [])
          ])
        )
        |> history()

      assert result.status == :assessed
      assert result.level == "parcialmente_adequado"
    end

    test "an action decided twice stays uncertain" do
      assess(
        resolved([
          llm("ask-intensity", "performed", ["turn-3"]),
          llm("ask-intensity", "not_performed", [])
        ])
      )
      |> assert_still_uncertain()
    end
  end

  # ============================================================================
  # Citations related to the action (issue #243)
  # ============================================================================

  # Jev hands an undecided action the items it could not rule out for it (its
  # candidates). A resolver citation outside them is unrelated to the action.
  describe "a resolver citation must be an item Jev left undecided for the action" do
    defp with_candidates(candidate_ids) do
      jev_answers(
        List.replace_at(history_actions(), 2, %{
          id: "ask-intensity",
          classification: "uncertain",
          evidence_ids: candidate_ids
        })
      )
    end

    test "an unrelated citation is dropped and the supported one is kept" do
      result =
        assess(resolved([llm("ask-intensity", "performed", ["turn-1", "turn-3"])]),
          answers: with_candidates(["turn-3"])
        )
        |> history()

      assert %{status: :assessed, level: "adequado", points: 40} = result
      assert action(result, "ask-intensity") == performed("ask-intensity", ["turn-3"])
    end

    test "an unrelated citation alone never raises the level" do
      assess(resolved([llm("ask-intensity", "performed", ["turn-1"])]),
        answers: with_candidates(["turn-3"])
      )
      |> assert_still_uncertain()
    end

    test "an action Jev offered no candidates for keeps any valid citation" do
      result =
        assess(resolved([llm("ask-intensity", "performed", ["turn-1"])]),
          answers: with_candidates([])
        )
        |> history()

      assert %{status: :assessed, level: "adequado"} = result
      assert action(result, "ask-intensity") == performed("ask-intensity", ["turn-1"])
    end

    test "candidates are never reported as evidence of an action left uncertain" do
      actions = [
        performed("ask-onset", ["turn-1"]),
        performed("ask-duration", ["turn-1"]),
        %{id: "ask-intensity", classification: "uncertain", evidence_ids: ["turn-3"]},
        performed("ask-relief", ["turn-1"])
      ]

      result = assess(resolved([]), answers: jev_answers(actions)) |> history()

      assert %{status: :assessed, level: "adequado", evidence_ids: ["turn-1"]} = result
      assert action(result, "ask-intensity") == uncertain("ask-intensity")
    end

    test "candidates are dropped when the resolver fails" do
      actions = [
        performed("ask-onset", ["turn-1"]),
        performed("ask-duration", ["turn-1"]),
        %{id: "ask-intensity", classification: "uncertain", evidence_ids: ["turn-3"]},
        performed("ask-relief", ["turn-1"])
      ]

      result = assess({:error, :upstream_error}, answers: jev_answers(actions)) |> history()

      assert %{status: :assessed, evidence_ids: ["turn-1"]} = result
      assert action(result, "ask-intensity") == uncertain("ask-intensity")
    end
  end

  # ============================================================================
  # Failures
  # ============================================================================

  describe "a failing resolver never invalidates the attempt" do
    test "malformed output leaves every undecided action uncertain" do
      for reply <- [
            {:ok, %{actions: [%{id: "ask-intensity", classification: "performed"}]}},
            {:ok, %{actions: [llm("ask-intensity", "maybe", [])]}},
            {:ok, %{actions: [llm("ask-intensity", "performed", [3])]}},
            {:ok, %{}},
            :unexpected
          ] do
        assess(reply) |> assert_still_uncertain()
      end
    end

    test "a valid decision beside a malformed one is not applied" do
      assess(resolved([llm("ask-intensity", "performed", ["turn-3"]), %{id: "x"}]))
      |> assert_still_uncertain()
    end

    test "an error leaves every undecided action uncertain" do
      assess({:error, :upstream_error}) |> assert_still_uncertain()
    end

    test "a raise leaves every undecided action uncertain" do
      assess(fn _request -> raise "boom" end) |> assert_still_uncertain()
    end

    test "the resolver deadline leaves every undecided action uncertain" do
      slow = fn _request ->
        Process.sleep(500)
        resolved([llm("ask-intensity", "performed", ["turn-3"])])
      end

      assess(slow, rubric_resolver_deadline_ms: 20) |> assert_still_uncertain()
    end

    test "the disabled resolver is a no-op" do
      assess(nil, resolver_adapter: Resolver.DisabledAdapter) |> assert_still_uncertain()
    end
  end

  describe "configuration" do
    test "the resolver is disabled by default with its own ten second deadline" do
      assert Resolver.adapter([]) == Resolver.DisabledAdapter
      assert Resolver.deadline_ms([]) == 10_000
      assert Resolver.adapter(resolver_adapter: ResolverDouble) == ResolverDouble
      assert Resolver.deadline_ms(rubric_resolver_deadline_ms: 10) == 10
    end

    test "a zero-point result is unaffected by the resolver" do
      actions = [not_performed("ask-onset"), uncertain("ask-duration")]

      result =
        assess(resolved([llm("ask-duration", "performed", ["turn-3"])]),
          answers: jev_answers(actions ++ [uncertain("ask-intensity"), uncertain("ask-relief")])
        )
        |> history()

      assert result.status == :assessed
      assert result.points == Points.zero()
    end
  end

  # ============================================================================
  # No confident zero without proof (issue #228)
  # ============================================================================

  describe "a zero-point level resting on resolver not_performed answers" do
    test "a zero grounded only on Jev's not_performed answers stays assessed" do
      actions = [
        performed("ask-onset", ["turn-1"]),
        not_performed("ask-duration"),
        not_performed("ask-intensity"),
        not_performed("ask-relief")
      ]

      result = assess(resolved([]), answers: jev_answers(actions)) |> history()

      assert %{status: :assessed, level: "inadequado", reason: nil} = result
      assert result.points == Points.zero()
      assert result.sub_actions == actions
    end

    test "a zero only the resolver's not_performed answers reach is uncertain" do
      actions = [
        performed("ask-onset", ["turn-1"]),
        uncertain("ask-duration"),
        uncertain("ask-intensity"),
        not_performed("ask-relief")
      ]

      result =
        assess(
          resolved([
            llm("ask-duration", "not_performed", []),
            llm("ask-intensity", "not_performed", [])
          ]),
          answers: jev_answers(actions)
        )
        |> history()

      assert result.status == :uncertain
      assert result.reason == {:uncertain_sub_action, "ask-duration"}
      refute Map.has_key?(result, :level)
      refute Map.has_key?(result, :points)

      assert Enum.map(result.sub_actions, & &1.classification) ==
               ["performed", "not_performed", "not_performed", "not_performed"]
    end

    test "a missing mandatory action the resolver decided is uncertain" do
      actions = [
        uncertain("ask-onset"),
        performed("ask-duration", ["turn-3"]),
        not_performed("ask-intensity"),
        not_performed("ask-relief")
      ]

      result =
        assess(resolved([llm("ask-onset", "not_performed", [])]), answers: jev_answers(actions))
        |> history()

      assert result.status == :uncertain
      assert result.reason == {:uncertain_sub_action, "ask-onset"}
    end

    test "a zero Jev's answers decide whatever the resolver said stays assessed" do
      actions = [
        not_performed("ask-onset"),
        uncertain("ask-duration"),
        not_performed("ask-intensity"),
        not_performed("ask-relief")
      ]

      result =
        assess(resolved([llm("ask-duration", "not_performed", [])]),
          answers: jev_answers(actions)
        )
        |> history()

      assert %{status: :assessed, level: "inadequado", reason: nil} = result
      assert action(result, "ask-duration") == not_performed("ask-duration")
    end

    test "a level above zero reached with resolver not_performed answers stays assessed" do
      result =
        assess(resolved([llm("ask-intensity", "not_performed", [])])) |> history()

      assert %{status: :assessed, level: "parcialmente_adequado", points: 20} = result
    end
  end
end
