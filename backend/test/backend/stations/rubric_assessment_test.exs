defmodule Backend.Stations.RubricAssessmentTest do
  use ExUnit.Case, async: true

  alias Backend.Stations.RubricAssessment
  alias Backend.Stations.RubricAssessment.Points

  @moduletag capture_log: true

  # ============================================================================
  # Deterministic double
  # ============================================================================

  defmodule ScriptedDouble do
    @moduledoc """
    Deterministic batch adapter. Every received request is reported to
    `opts[:test_pid]`. The reply is `opts[:reply]` (a term or a one-arity
    function of the request) or, by default, one decision per question taken
    from `opts[:answers]` (`criterion_id => decision overrides`); a question
    without an answer is classified `"uncertain"`.
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

      case opts[:reply] do
        fun when is_function(fun, 1) -> fun.(request)
        nil -> {:ok, %{decisions: decisions(request, opts[:answers] || %{})}}
        reply -> reply
      end
    end

    @doc "Builds one decision per question from the scripted answers."
    def decisions(request, answers) do
      Enum.map(request.questions, fn question ->
        Map.merge(
          %{
            criterion_id: question.criterion.id,
            classification: "uncertain",
            evidence_ids: [],
            actions: Enum.map(question.actions, &action(&1.id, "uncertain", []))
          },
          Map.get(answers, question.criterion.id, %{})
        )
      end)
    end

    defp action(id, classification, evidence_ids) do
      %{id: id, classification: classification, evidence_ids: evidence_ids}
    end
  end

  # ============================================================================
  # Fixtures
  # ============================================================================

  @stations_path Path.expand("../../../priv/stations", __DIR__)

  @t0 ~U[2026-01-10 12:00:00.000000Z]
  @t1 ~U[2026-01-10 12:00:01.000000Z]
  @t2 ~U[2026-01-10 12:00:02.000000Z]
  @t3 ~U[2026-01-10 12:00:03.000000Z]

  @onset "onset-assessment"
  @symptom "symptom-characterization"
  @safety "safety-check"
  @note "teaching-note"
  @lab "lab-request"

  defp package(relative_path) do
    @stations_path |> Path.join(relative_path) |> File.read!() |> Jason.decode!()
  end

  # Four criteria: verbal (0/1, one action), any modality (0/0.125/0.25),
  # physical_exam with no authored impresso, and an authored exclusion.
  defp v2, do: package("fixtures/valid-package-v2.json")

  defp reconciliation, do: package("fixtures/valid-package-v2-partial-reconciliation.json")

  # Authors one impresso per category and a single verbal criterion (0/2).
  defp chest_pain, do: package("chest-pain-initial-assessment/package.json")

  defp update_rubric(package, fun), do: Map.update!(package, "rubric", fun)

  defp only(package, ids) do
    update_rubric(package, fn rubric -> Enum.filter(rubric, &(&1["id"] in ids)) end)
  end

  defp update_criterion(package, id, fun) do
    update_rubric(package, fn rubric -> Enum.map(rubric, &update_if(&1, id, fun)) end)
  end

  defp update_if(%{"id" => id} = criterion, id, fun), do: fun.(criterion)
  defp update_if(criterion, _id, _fun), do: criterion

  # The chest pain package plus a criterion that requires a laboratory impresso.
  defp chest_pain_with_lab do
    lab = %{
      "id" => @lab,
      "description" => "Requests cardiac enzymes.",
      "evidence_questions" => ["Were cardiac enzymes requested?"],
      "practice_recommendation" => "Request cardiac enzymes early.",
      "levels" => [
        %{"label" => "inadequado", "points" => 0, "description" => "Does not request them."},
        %{"label" => "adequado", "points" => 0.5, "description" => "Requests them."}
      ],
      "actions" => [],
      "order" => 2,
      "count_cap" => nil,
      "first_n" => nil,
      "veto" => false,
      "exclusion" => false,
      "modality_requirement" => "laboratory"
    }

    update_rubric(chest_pain(), &(&1 ++ [lab]))
  end

  defp turn(role, text, at), do: %{role: role, modality: :text, text: text, at: at}

  defp event(request_id, released_ids, at, overrides \\ %{}) do
    Map.merge(
      %{
        request_id: request_id,
        station_id: "chest-pain-initial-assessment",
        station_version: "2.0.0",
        order: 1,
        text: "request #{request_id}",
        matched_ids: released_ids,
        decision: :released,
        released_ids: released_ids,
        at: at
      },
      overrides
    )
  end

  # turn-1 learner, turn-2 patient, turn-3 learner.
  defp session(impresso_requests \\ []) do
    %{
      messages: [
        turn(:learner, "Quando começou a dor?", @t0),
        turn(:patient, "Começou há duas horas.", @t1),
        turn(:learner, "Como é a dor?", @t2)
      ],
      impresso_requests: impresso_requests
    }
  end

  defp answer(classification, evidence_ids, overrides \\ %{}) do
    Map.merge(%{classification: classification, evidence_ids: evidence_ids}, overrides)
  end

  defp assess(package, session, answers, opts \\ []) do
    RubricAssessment.assess(
      package,
      session,
      [adapter: ScriptedDouble, test_pid: self(), answers: answers] ++ opts
    )
  end

  defp assess!(package, session, answers, opts \\ []) do
    assert {:ok, assessment} = assess(package, session, answers, opts)
    assessment
  end

  defp criterion(assessment, id), do: Enum.find(assessment.criteria, &(&1.id == id))

  defp asked_ids(request), do: Enum.map(request.questions, & &1.criterion.id)

  defp assert_unscored(result) do
    refute Map.has_key?(result, :level)
    refute Map.has_key?(result, :points)
    assert result.evidence_ids == []
    assert result.evidence == []
  end

  defp assert_invalid_attempt(result, reason) do
    assert result == {:error, {:invalid_attempt, reason}}
  end

  # ============================================================================
  # Statuses
  # ============================================================================

  describe "assess/3 statuses" do
    test "a genuine omission is assessed at the zero-point level without evidence" do
      assessment =
        assess!(v2(), session(), %{
          @onset => answer("inadequado", []),
          @symptom => answer("adequado", ["turn-3"])
        })

      omitted = criterion(assessment, @onset)

      assert omitted.status == :assessed
      assert omitted.level == "inadequado"
      assert omitted.points == Points.zero()
      assert omitted.max_points == 8
      assert omitted.evidence_ids == []
      assert omitted.reason == nil

      assert assessment.estimates.scored_subtotal == 2
      assert assessment.estimates.scored_max == 10
    end

    test "classifier uncertainty leaves the criterion uncertain and the total open" do
      assessment =
        assess!(v2(), session(), %{@symptom => answer("adequado", ["turn-3"])})

      uncertain = criterion(assessment, @onset)

      assert uncertain.status == :uncertain
      assert uncertain.reason == :classifier_uncertain
      assert_unscored(uncertain)

      assert assessment.estimates.total == nil
      assert %{id: @onset, status: :uncertain} in assessment.estimates.unresolved
    end

    test "a modality the station cannot provide is not observable and never asked" do
      assessment = assess!(v2(), session(), %{})
      unobservable = criterion(assessment, @safety)

      assert unobservable.status == :not_observable
      assert unobservable.reason == :no_authored_impresso
      assert unobservable.max_points == 8
      assert_unscored(unobservable)

      assert %{id: @safety, status: :not_observable} in assessment.estimates.unresolved

      assert_received {:batch_request, sent}
      refute @safety in asked_ids(sent)
    end

    test "an authored exclusion is not applicable, outside both maxima and never asked" do
      assessment =
        assess!(v2(), session(), %{
          @onset => answer("adequado", ["turn-1"]),
          @symptom => answer("adequado", ["turn-3"])
        })

      excluded = criterion(assessment, @note)

      assert excluded.status == :not_applicable
      assert excluded.max_points == 4
      assert_unscored(excluded)

      # onset 1 + symptom 0.25 assessed; safety-check 1 eligible; the note's 0.5 nowhere.
      assert assessment.estimates.scored_max == 10
      assert assessment.estimates.eligible_max == 18
      refute Enum.any?(assessment.estimates.unresolved, &(&1.id == @note))

      assert_received {:batch_request, sent}
      assert asked_ids(sent) == [@onset, @symptom]
    end

    test "criteria are returned in rubric order with the authored recommendation" do
      assessment = assess!(v2(), session(), %{})

      assert Enum.map(assessment.criteria, & &1.id) == [@onset, @symptom, @safety, @note]

      assert criterion(assessment, @onset).recommendation ==
               "Practice opening chest pain assessments with onset questions."
    end
  end

  # ============================================================================
  # Evidence
  # ============================================================================

  describe "assess/3 evidence" do
    test "one learner turn may ground two criteria" do
      assessment =
        assess!(v2(), session(), %{
          @onset => answer("adequado", ["turn-1"]),
          @symptom => answer("parcialmente_adequado", ["turn-1"])
        })

      for id <- [@onset, @symptom] do
        result = criterion(assessment, id)
        assert result.status == :assessed
        assert result.evidence_ids == ["turn-1"]
        assert result.evidence == [%{id: "turn-1", role: :learner, text: "Quando começou a dor?"}]
      end
    end

    test "cited evidence is returned in pool order without duplicates" do
      assessment =
        assess!(v2(), session(), %{@symptom => answer("adequado", ["turn-3", "turn-1", "turn-3"])})

      assert criterion(assessment, @symptom).evidence_ids == ["turn-1", "turn-3"]
    end

    test "a cited patient turn fails closed with :wrong_role" do
      assessment = assess!(v2(), session(), %{@onset => answer("adequado", ["turn-1", "turn-2"])})
      result = criterion(assessment, @onset)

      assert result.status == :uncertain
      assert result.reason == {:invalid_evidence, :wrong_role, "turn-2"}
      assert_unscored(result)
    end

    test "a nonexistent evidence id fails closed" do
      assessment = assess!(v2(), session(), %{@onset => answer("adequado", ["turn-99"])})
      result = criterion(assessment, @onset)

      assert result.status == :uncertain
      assert result.reason == {:invalid_evidence, :nonexistent_evidence_id, "turn-99"}
      assert_unscored(result)
    end

    test "a turn cited for an Impressos-category criterion fails closed with :wrong_channel" do
      assessment =
        assess!(chest_pain_with_lab(), session(), %{@lab => answer("adequado", ["turn-1"])})

      result = criterion(assessment, @lab)

      assert result.status == :uncertain
      assert result.reason == {:invalid_evidence, :wrong_channel, "turn-1"}
      assert_unscored(result)
    end

    test "an event of another station version fails closed and is not offered to Jev" do
      stale =
        event("req-stale", ["laboratorio-sangue-enzimas"], @t3, %{station_version: "1.0.0"})

      assessment =
        assess!(chest_pain_with_lab(), session([stale]), %{
          @lab => answer("adequado", ["impresso-req-stale"])
        })

      result = criterion(assessment, @lab)

      assert result.status == :uncertain
      assert result.reason == {:invalid_evidence, :wrong_provenance, "impresso-req-stale"}
      assert_unscored(result)

      assert_received {:batch_request, sent}
      assert Enum.map(sent.evidence_pool, & &1.id) == ["turn-1", "turn-2", "turn-3"]
    end

    test "a verified impresso event grounds an Impressos-category criterion" do
      lab_event = event("req-lab", ["laboratorio-sangue-enzimas"], @t3)

      assessment =
        assess!(chest_pain_with_lab(), session([lab_event]), %{
          @lab => answer("adequado", ["impresso-req-lab"])
        })

      result = criterion(assessment, @lab)

      assert result.status == :assessed
      assert result.level == "adequado"
      assert Points.to_decimal_string(result.points) == "0.5"
      assert result.evidence_ids == ["impresso-req-lab"]

      assert result.evidence == [
               %{id: "impresso-req-lab", role: :learner, text: "request req-lab"}
             ]
    end

    test "a positive level without evidence is unsupported credit" do
      assessment = assess!(v2(), session(), %{@onset => answer("adequado", [])})
      result = criterion(assessment, @onset)

      assert result.status == :uncertain
      assert result.reason == :unsupported_credit
      assert_unscored(result)
    end

    test "a zero-point level may still carry validated evidence" do
      assessment = assess!(v2(), session(), %{@onset => answer("inadequado", ["turn-1"])})
      result = criterion(assessment, @onset)

      assert result.status == :assessed
      assert result.points == 0
      assert result.evidence_ids == ["turn-1"]
    end
  end

  # ============================================================================
  # Sub-actions
  # ============================================================================

  describe "assess/3 sub-actions" do
    defp onset_actions(classification, evidence_ids) do
      %{actions: [%{id: "ask-onset", classification: classification, evidence_ids: evidence_ids}]}
    end

    test "validated sub-action decisions are carried without changing the level" do
      assessment =
        assess!(v2(), session(), %{
          @onset => answer("adequado", ["turn-1"], onset_actions("not_performed", []))
        })

      result = criterion(assessment, @onset)

      assert result.status == :assessed
      assert result.level == "adequado"
      assert result.points == 8

      assert result.sub_actions == [
               %{id: "ask-onset", classification: "not_performed", evidence_ids: []}
             ]
    end

    test "invalid sub-action evidence fails the whole criterion closed" do
      assessment =
        assess!(v2(), session(), %{
          @onset => answer("adequado", ["turn-1"], onset_actions("performed", ["turn-2"]))
        })

      result = criterion(assessment, @onset)

      assert result.status == :uncertain
      assert result.reason == {:invalid_evidence, :wrong_role, "turn-2"}
      assert result.sub_actions == []
      assert_unscored(result)
    end
  end

  # ============================================================================
  # Authored rules
  # ============================================================================

  describe "assess/3 authored rules" do
    @history "history-taking"
    @treatment "treatment-plan"

    # history-taking: thresholds 0/2/3 for 0/0.5/1, `ask-onset` mandatory.
    # treatment-plan: 0/1 without thresholds, one counted and one forbidden action.
    defp rules do
      only(package("fixtures/valid-package-v2-authored-rules.json"), [@history, @treatment])
    end

    defp performed(id, evidence_ids \\ ["turn-1"]) do
      %{id: id, classification: "performed", evidence_ids: evidence_ids}
    end

    defp not_performed(id), do: %{id: id, classification: "not_performed", evidence_ids: []}

    defp uncertain(id), do: %{id: id, classification: "uncertain", evidence_ids: []}

    defp history_answer(classification, evidence_ids, actions) do
      %{@history => answer(classification, evidence_ids, %{actions: actions})}
    end

    defp treatment_answer(classification, evidence_ids, actions) do
      %{@treatment => answer(classification, evidence_ids, %{actions: actions})}
    end

    test "the count of performed actions decides the level, not Jev's class" do
      actions = [
        performed("ask-onset"),
        performed("ask-duration", ["turn-3"]),
        performed("ask-intensity", ["turn-1", "turn-3"]),
        not_performed("ask-relief")
      ]

      assessment =
        assess!(rules(), session(), history_answer("inadequado", ["turn-1"], actions))

      result = criterion(assessment, @history)

      assert result.status == :assessed
      assert result.level == "adequado"
      assert result.points == 8
      assert result.evidence_ids == ["turn-1"]
      assert result.sub_actions == actions
    end

    test "a missing mandatory action is assessed at the zero-point level" do
      actions = [
        not_performed("ask-onset"),
        performed("ask-duration"),
        performed("ask-intensity"),
        performed("ask-relief")
      ]

      result =
        rules()
        |> assess!(session(), history_answer("adequado", ["turn-1"], actions))
        |> criterion(@history)

      assert result.status == :assessed
      assert result.level == "inadequado"
      assert result.points == Points.zero()
      assert result.reason == nil
    end

    test "a performed forbidden action is assessed at the zero-point level" do
      actions = [
        performed("indicate-expected"),
        performed("indicate-contraindicated", ["turn-3"])
      ]

      result =
        rules()
        |> assess!(session(), treatment_answer("adequado", ["turn-1"], actions))
        |> criterion(@treatment)

      assert result.status == :assessed
      assert result.level == "inadequado"
      assert result.points == Points.zero()
      assert result.evidence_ids == ["turn-1"]
    end

    test "an uncertain sub-action that could change the level leaves the criterion uncertain" do
      actions = [
        performed("ask-onset"),
        performed("ask-duration"),
        uncertain("ask-intensity"),
        not_performed("ask-relief")
      ]

      assessment = assess!(rules(), session(), history_answer("adequado", ["turn-1"], actions))
      result = criterion(assessment, @history)

      assert result.status == :uncertain
      assert result.reason == {:uncertain_sub_action, "ask-intensity"}
      assert result.sub_actions == []
      assert_unscored(result)
      assert %{id: @history, status: :uncertain} in assessment.estimates.unresolved
    end

    test "an uncertain sub-action that cannot change the level leaves it assessed" do
      actions = [
        performed("ask-onset"),
        performed("ask-duration"),
        performed("ask-intensity"),
        uncertain("ask-relief")
      ]

      result =
        rules()
        |> assess!(session(), history_answer("inadequado", ["turn-1"], actions))
        |> criterion(@history)

      assert result.status == :assessed
      assert result.level == "adequado"
      assert result.sub_actions == actions
    end

    test "a missing mandatory action is certain whatever else is unresolved" do
      actions = [
        not_performed("ask-onset"),
        uncertain("ask-duration"),
        performed("ask-intensity", []),
        performed("ask-relief")
      ]

      result =
        rules()
        |> assess!(session(), history_answer("adequado", ["turn-1"], actions))
        |> criterion(@history)

      assert result.status == :assessed
      assert result.level == "inadequado"
      assert result.points == Points.zero()
    end

    test "a sub-action performed without evidence leaves the criterion uncertain" do
      actions = [
        performed("ask-onset", []),
        performed("ask-duration"),
        performed("ask-intensity"),
        performed("ask-relief")
      ]

      result =
        rules()
        |> assess!(session(), history_answer("adequado", ["turn-1"], actions))
        |> criterion(@history)

      assert result.status == :uncertain
      assert result.reason == {:unsupported_sub_action, "ask-onset"}
      assert_unscored(result)
    end

    test "sub-action evidence goes through the same validation as criterion evidence" do
      actions = [
        performed("indicate-expected"),
        performed("indicate-contraindicated", ["turn-2"])
      ]

      result =
        rules()
        |> assess!(session(), treatment_answer("adequado", ["turn-1"], actions))
        |> criterion(@treatment)

      assert result.status == :uncertain
      assert result.reason == {:invalid_evidence, :wrong_role, "turn-2"}
      assert_unscored(result)
    end

    test "a level earned by count still needs criterion-level evidence" do
      actions = [
        performed("ask-onset"),
        performed("ask-duration"),
        not_performed("ask-intensity"),
        not_performed("ask-relief")
      ]

      result =
        rules()
        |> assess!(session(), history_answer("inadequado", [], actions))
        |> criterion(@history)

      assert result.status == :uncertain
      assert result.reason == :unsupported_credit
      assert_unscored(result)
    end

    test "rule fields that cannot be applied invalidate the attempt before any call" do
      broken =
        update_criterion(rules(), @treatment, fn criterion ->
          put_in(criterion, ["levels", Access.at(0), "points"], 0.5)
        end)

      assert_invalid_attempt(
        assess(broken, session(), %{}),
        {:invalid_package, @treatment, :missing_zero_point_level}
      )

      refute_received {:batch_request, _}
    end
  end

  # ============================================================================
  # Exact arithmetic
  # ============================================================================

  describe "assess/3 exact arithmetic" do
    # onset (0/1) plus two copies of the 0/0.125/0.25 criterion; nothing else.
    defp eighths_package do
      v2()
      |> only([@onset, @symptom])
      |> update_rubric(fn [onset, symptom] ->
        [onset, symptom, Map.put(symptom, "id", "symptom-b")]
      end)
    end

    test "0.125 and 0.25 levels sum without drift" do
      assessment =
        assess!(eighths_package(), session(), %{
          @symptom => answer("parcialmente_adequado", ["turn-3"]),
          "symptom-b" => answer("adequado", ["turn-3"])
        })

      assert Points.to_decimal_string(criterion(assessment, @symptom).points) == "0.125"
      assert Points.to_decimal_string(criterion(assessment, "symptom-b").points) == "0.25"
      assert Points.to_decimal_string(assessment.estimates.scored_subtotal) == "0.375"
      assert Points.to_decimal_string(assessment.estimates.scored_max) == "0.5"
      assert assessment.estimates.total == nil
    end

    test "the reconciliation fixture yields 0.25 / 0.25 / 1.25 and no total" do
      assessment =
        assess!(reconciliation(), session(), %{
          "criterion-a" => answer("parcialmente_adequado", ["turn-1"])
        })

      estimates = assessment.estimates

      assert Points.to_decimal_string(estimates.scored_subtotal) == "0.25"
      assert Points.to_decimal_string(estimates.scored_max) == "0.25"
      assert Points.to_decimal_string(estimates.eligible_max) == "1.25"
      assert estimates.total == nil
      assert estimates.unresolved == [%{id: "criterion-b", status: :uncertain}]
    end

    test "a fully assessed rubric yields a numeric total" do
      assessment =
        assess!(eighths_package(), session(), %{
          @onset => answer("adequado", ["turn-1"]),
          @symptom => answer("parcialmente_adequado", ["turn-3"]),
          "symptom-b" => answer("inadequado", [])
        })

      assert assessment.estimates.unresolved == []
      assert Points.to_decimal_string(assessment.estimates.total) == "1.125"
      assert Points.to_decimal_string(assessment.estimates.eligible_max) == "1.5"
    end

    test "a level that is not an exact multiple of 0.125 invalidates the attempt" do
      broken =
        update_criterion(v2(), @symptom, fn criterion ->
          Map.put(criterion, "levels", [
            %{"label" => "adequado", "points" => 0.1, "description" => "Inexact."}
          ])
        end)

      assert_invalid_attempt(
        assess(broken, session(), %{}),
        {:invalid_package, @symptom, :not_a_multiple_of_one_eighth}
      )

      refute_received {:batch_request, _}
    end
  end

  # ============================================================================
  # Batching
  # ============================================================================

  describe "assess/3 batching" do
    test "all questions go in exactly one call with the pool sent once" do
      assessment = assess!(v2(), session(), %{})

      assert assessment.calls == [%{question_count: 2, justification: :single_batch}]

      assert_received {:batch_request, sent}
      refute_received {:batch_request, _}

      assert asked_ids(sent) == [@onset, @symptom]
      assert Enum.map(sent.evidence_pool, & &1.id) == ["turn-1", "turn-2", "turn-3"]
      refute Enum.any?(sent.questions, &Map.has_key?(&1, :evidence_pool))
    end

    test "a provider capacity limit splits the questions and records each justification" do
      assessment =
        assess!(
          v2(),
          session(),
          %{
            @onset => answer("adequado", ["turn-1"]),
            @symptom => answer("adequado", ["turn-3"])
          },
          max_questions_per_call: 1
        )

      assert assessment.calls == [
               %{question_count: 1, justification: :single_batch},
               %{question_count: 1, justification: :provider_capacity}
             ]

      assert_received {:batch_request, first}
      assert_received {:batch_request, second}
      refute_received {:batch_request, _}

      assert asked_ids(first) == [@onset]
      assert asked_ids(second) == [@symptom]
      assert length(first.evidence_pool) == 3
      assert length(second.evidence_pool) == 3

      assert criterion(assessment, @onset).status == :assessed
      assert criterion(assessment, @symptom).status == :assessed
    end

    test "a capacity limit that is not exceeded keeps a single call" do
      assessment = assess!(v2(), session(), %{}, max_questions_per_call: 2)

      assert assessment.calls == [%{question_count: 2, justification: :single_batch}]
    end

    test "nothing askable makes zero calls" do
      assessment = assess!(only(v2(), [@safety, @note]), session(), %{})

      assert assessment.calls == []
      assert Enum.map(assessment.criteria, & &1.status) == [:not_observable, :not_applicable]
      assert assessment.estimates.total == nil
      refute_received {:batch_request, _}
    end
  end

  # ============================================================================
  # Technical failure
  # ============================================================================

  describe "assess/3 technical failure" do
    defp failing(reply, opts \\ []), do: assess(v2(), session(), %{}, [reply: reply] ++ opts)

    test "a timeout invalidates the attempt" do
      slow = fn _request ->
        Process.sleep(500)
        {:ok, %{decisions: []}}
      end

      assert_invalid_attempt(failing(slow, deadline_ms: 30), :timeout)
    end

    test "an upstream 5xx invalidates the attempt" do
      assert_invalid_attempt(failing({:error, {:upstream_error, 503}}), {:upstream_5xx, 503})
    end

    test "malformed output invalidates the attempt" do
      assert_invalid_attempt(
        failing({:ok, %{decisions: "not a list"}}),
        {:malformed_output, :expected_decisions_list}
      )
    end

    test "a class outside the allowed set invalidates the attempt" do
      disallowed = fn request ->
        {:ok,
         %{
           decisions:
             ScriptedDouble.decisions(request, %{@onset => %{classification: "excelente"}})
         }}
      end

      assert_invalid_attempt(failing(disallowed), {:invalid_response, :disallowed_classification})
    end

    test "a failure on the second chunk discards the first chunk's criteria" do
      second_fails = fn request ->
        if @symptom in Enum.map(request.questions, & &1.criterion.id) do
          {:error, :network_error}
        else
          {:ok,
           %{
             decisions:
               ScriptedDouble.decisions(request, %{@onset => answer("adequado", ["turn-1"])})
           }}
        end
      end

      result = failing(second_fails, max_questions_per_call: 1)

      assert_invalid_attempt(result, :network_error)
      assert_received {:batch_request, _first}
      assert_received {:batch_request, _second}
    end
  end

  # ============================================================================
  # Question composition
  # ============================================================================

  describe "assess/3 question composition" do
    test "composes the description, the allowed classes and the authored actions" do
      assess!(v2(), session(), %{})

      assert_received {:batch_request, %{questions: [onset, symptom]}}

      assert onset == %{
               criterion: %{
                 id: @onset,
                 description: """
                 Assesses the onset of chest pain.
                 Evidence questions:
                 - When did the pain begin?
                 Levels:
                 - inadequado: Does not assess onset.
                 - adequado: Assesses onset clearly.\
                 """
               },
               allowed_classes: ["inadequado", "adequado", "uncertain"],
               actions: [%{id: "ask-onset", description: "Ask about onset."}]
             }

      assert symptom.allowed_classes ==
               ["inadequado", "parcialmente_adequado", "adequado", "uncertain"]

      assert symptom.actions == []
    end

    test "the evidence pool sent to Jev carries only id, role and text" do
      assess!(v2(), session(), %{})

      assert_received {:batch_request, sent}

      assert hd(sent.evidence_pool) ==
               %{id: "turn-1", role: "learner", text: "Quando começou a dor?"}
    end
  end

  # ============================================================================
  # Legacy projection
  # ============================================================================

  describe "to_legacy/1" do
    test "maps every status to the legacy vocabulary and drops excluded criteria" do
      package =
        update_rubric(v2(), fn [onset, symptom, safety, note] ->
          [onset, symptom, Map.put(symptom, "id", "symptom-b"), safety, note]
        end)

      assessment =
        assess!(package, session(), %{
          @onset => answer("adequado", ["turn-1"]),
          @symptom => answer("inadequado", [])
        })

      assert RubricAssessment.to_legacy(assessment) == %{
               criteria: [
                 %{
                   id: @onset,
                   status: :met,
                   evidence: [%{role: :learner, text: "Quando começou a dor?"}],
                   recommendation: "Practice opening chest pain assessments with onset questions."
                 },
                 %{
                   id: @symptom,
                   status: :omitted,
                   evidence: [],
                   recommendation: "Use a structured symptom description."
                 },
                 %{
                   id: "symptom-b",
                   status: :uncertain,
                   evidence: [],
                   recommendation: "Use a structured symptom description."
                 },
                 %{
                   id: @safety,
                   status: :uncertain,
                   evidence: [],
                   recommendation: "Prioritize immediate safety checks."
                 }
               ]
             }
    end
  end
end
