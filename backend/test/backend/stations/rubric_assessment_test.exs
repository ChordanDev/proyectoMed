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
    without an answer is classified `"uncertain"`, and enumerates no learner
    answers when the question requests the enumeration.
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
        %{
          criterion_id: question.criterion.id,
          classification: "uncertain",
          evidence_ids: [],
          actions: Enum.map(question.actions, &action(&1.id, "uncertain", []))
        }
        |> Map.merge(enumeration(question))
        |> Map.merge(Map.get(answers, question.criterion.id, %{}))
      end)
    end

    defp enumeration(%{enumerate_answers: true}), do: %{answers: []}
    defp enumeration(_question), do: %{}

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
      assert result.evidence_ids == ["turn-1", "turn-3"]
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
      assert result.evidence_ids == ["turn-1", "turn-3"]
    end

    test "a veto zero is grounded by the forbidden action even without criterion evidence" do
      actions = [
        not_performed("indicate-expected"),
        performed("indicate-contraindicated", ["turn-3", "turn-1", "turn-3"])
      ]

      result =
        rules()
        |> assess!(session(), treatment_answer("inadequado", [], actions))
        |> criterion(@treatment)

      assert result.status == :assessed
      assert result.points == Points.zero()
      assert result.evidence_ids == ["turn-1", "turn-3"]
      assert Enum.map(result.evidence, & &1.id) == ["turn-1", "turn-3"]
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

    test "a level earned by count is grounded by the actions that earned it" do
      actions = [
        performed("ask-onset", ["turn-3"]),
        performed("ask-duration", ["turn-1", "turn-3"]),
        not_performed("ask-intensity"),
        not_performed("ask-relief")
      ]

      result =
        rules()
        |> assess!(session(), history_answer("inadequado", [], actions))
        |> criterion(@history)

      assert result.status == :assessed
      assert result.level == "parcialmente_adequado"
      assert result.points == 4
      assert result.evidence_ids == ["turn-1", "turn-3"]

      assert result.evidence == [
               %{id: "turn-1", role: :learner, text: "Quando começou a dor?"},
               %{id: "turn-3", role: :learner, text: "Como é a dor?"}
             ]
    end

    test "without thresholds sub-action evidence does not ground the classifier's level" do
      actions = [performed("indicate-expected"), not_performed("indicate-contraindicated")]

      result =
        rules()
        |> assess!(session(), treatment_answer("adequado", [], actions))
        |> criterion(@treatment)

      assert result.status == :uncertain
      assert result.reason == :unsupported_credit
      assert_unscored(result)
    end

    test "an unresolved mandatory action is ignored when zero is the only outcome" do
      actions = [
        uncertain("ask-onset"),
        not_performed("ask-duration"),
        not_performed("ask-intensity"),
        not_performed("ask-relief")
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

    test "an unresolved forbidden action is ignored when zero is the only outcome" do
      actions = [not_performed("indicate-expected"), uncertain("indicate-contraindicated")]

      result =
        rules()
        |> assess!(session(), treatment_answer("inadequado", [], actions))
        |> criterion(@treatment)

      assert result.status == :assessed
      assert result.level == "inadequado"
      assert result.points == Points.zero()
    end

    test "an uncertain classifier does not stop thresholds from deciding the level" do
      actions = [
        performed("ask-onset"),
        performed("ask-duration", ["turn-3"]),
        performed("ask-intensity"),
        not_performed("ask-relief")
      ]

      result =
        rules()
        |> assess!(session(), history_answer("uncertain", [], actions))
        |> criterion(@history)

      assert result.status == :assessed
      assert result.level == "adequado"
      assert result.points == 8
      assert result.evidence_ids == ["turn-1", "turn-3"]
      assert result.sub_actions == actions
    end

    test "an uncertain classifier does not stop a missing mandatory action from scoring zero" do
      actions = [
        not_performed("ask-onset"),
        performed("ask-duration"),
        performed("ask-intensity"),
        performed("ask-relief")
      ]

      result =
        rules()
        |> assess!(session(), history_answer("uncertain", [], actions))
        |> criterion(@history)

      assert result.status == :assessed
      assert result.level == "inadequado"
      assert result.points == Points.zero()
    end

    test "an uncertain classifier leaves the criterion uncertain when its level is needed" do
      actions = [performed("indicate-expected"), not_performed("indicate-contraindicated")]

      result =
        rules()
        |> assess!(session(), treatment_answer("uncertain", ["turn-1"], actions))
        |> criterion(@treatment)

      assert result.status == :uncertain
      assert result.reason == :classifier_uncertain
      assert_unscored(result)
    end

    test "an uncertain classifier on a criterion without rule fields stays uncertain" do
      for evidence_ids <- [["turn-1"], ["turn-99"]] do
        result =
          v2()
          |> assess!(session(), %{
            @onset => answer("uncertain", evidence_ids, onset_actions("performed", ["turn-1"]))
          })
          |> criterion(@onset)

        assert result.status == :uncertain
        assert result.reason == :classifier_uncertain
        assert_unscored(result)
      end
    end

    test "an invalid sub-action citation fails the criterion closed even when not decisive" do
      # Three performed actions already earn the top level, so `ask-relief`
      # could not change it; the invalid citation still discredits the reading.
      actions = [
        performed("ask-onset"),
        performed("ask-duration"),
        performed("ask-intensity"),
        performed("ask-relief", ["turn-99"])
      ]

      result =
        rules()
        |> assess!(session(), history_answer("adequado", ["turn-1"], actions))
        |> criterion(@history)

      assert result.status == :uncertain
      assert result.reason == {:invalid_evidence, :nonexistent_evidence_id, "turn-99"}
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
  # Task order
  # ============================================================================

  describe "assess/3 task order" do
    @exams "exam-requests"
    @order "task-order"

    # history-taking (rank 1), treatment-plan (rank 2), exam-requests (rank 3)
    # and the task-order criterion (0/0.25), which is assessed in code.
    defp ordered, do: package("fixtures/valid-package-v2-authored-rules.json")

    # turn-1, turn-3 and turn-5 are learner turns.
    defp order_session do
      %{
        messages: [
          turn(:learner, "Quando começou?", @t0),
          turn(:patient, "Há duas horas.", @t1),
          turn(:learner, "Vou indicar o tratamento.", @t2),
          turn(:patient, "Está bem.", @t3),
          turn(:learner, "Solicito o exame A.", ~U[2026-01-10 12:00:04.000000Z])
        ],
        impresso_requests: []
      }
    end

    # An answer that assesses the step above zero, backed by `evidence_ids`.
    defp done(@history, evidence_ids) do
      actions = [
        performed("ask-onset", evidence_ids),
        performed("ask-duration", evidence_ids),
        not_performed("ask-intensity"),
        not_performed("ask-relief")
      ]

      answer("parcialmente_adequado", evidence_ids, %{actions: actions})
    end

    defp done(@treatment, evidence_ids) do
      actions = [
        performed("indicate-expected", evidence_ids),
        not_performed("indicate-contraindicated")
      ]

      answer("adequado", evidence_ids, %{actions: actions})
    end

    # exam-requests authors `first_n`, so its answer enumerates what was said.
    defp done(@exams, evidence_ids) do
      actions = [performed("request-exam-a", evidence_ids), not_performed("request-exam-b")]
      answers = [%{evidence_id: hd(evidence_ids), action_id: "request-exam-a"}]

      answer("adequado", evidence_ids, %{actions: actions, answers: answers})
    end

    # An answer that assesses the step at its zero-point level.
    defp skipped(id) do
      action_ids = %{
        @history => ["ask-onset", "ask-duration", "ask-intensity", "ask-relief"],
        @treatment => ["indicate-expected", "indicate-contraindicated"],
        @exams => ["request-exam-a", "request-exam-b"]
      }

      answer("inadequado", [], %{actions: Enum.map(action_ids[id], &not_performed/1)})
    end

    defp order_result(package \\ ordered(), answers) do
      package |> assess!(order_session(), answers) |> criterion(@order)
    end

    defp assert_order(result, level, points, evidence_ids) do
      assert result.status == :assessed
      assert result.level == level
      assert result.points == points
      assert result.evidence_ids == evidence_ids
      assert Enum.map(result.evidence, & &1.id) == evidence_ids
      assert Enum.all?(result.evidence, &(&1.role == :learner))
      assert result.reason == nil
      assert result.sub_actions == []
    end

    test "steps performed in rank order earn the top level, grounded in their earliest evidence" do
      result =
        order_result(%{
          @history => done(@history, ["turn-1", "turn-5"]),
          @treatment => done(@treatment, ["turn-3"]),
          @exams => done(@exams, ["turn-5"])
        })

      assert_order(result, "adequado", 2, ["turn-1", "turn-3", "turn-5"])
    end

    test "steps performed out of rank order score the zero-point level" do
      result =
        order_result(%{
          @history => done(@history, ["turn-3"]),
          @treatment => done(@treatment, ["turn-1"]),
          @exams => done(@exams, ["turn-5"])
        })

      assert_order(result, "inadequado", Points.zero(), ["turn-1", "turn-3", "turn-5"])
    end

    test "the earliest evidence of a step decides its position" do
      result =
        order_result(%{
          @history => done(@history, ["turn-3"]),
          @treatment => done(@treatment, ["turn-1", "turn-5"]),
          @exams => skipped(@exams)
        })

      assert_order(result, "inadequado", Points.zero(), ["turn-1", "turn-3"])
    end

    test "one turn may back two consecutive steps" do
      result =
        order_result(%{
          @history => done(@history, ["turn-1"]),
          @treatment => done(@treatment, ["turn-1"]),
          @exams => done(@exams, ["turn-3"])
        })

      assert_order(result, "adequado", 2, ["turn-1", "turn-3"])
    end

    test "equal ranks are unordered among themselves" do
      package = update_criterion(ordered(), @treatment, &Map.put(&1, "order", 1))

      result =
        order_result(package, %{
          @history => done(@history, ["turn-3"]),
          @treatment => done(@treatment, ["turn-1"]),
          @exams => done(@exams, ["turn-5"])
        })

      assert_order(result, "adequado", 2, ["turn-1", "turn-3", "turn-5"])
    end

    test "a step assessed at its zero-point level is skipped" do
      result =
        order_result(%{
          @history => done(@history, ["turn-1"]),
          @treatment => skipped(@treatment),
          @exams => done(@exams, ["turn-3"])
        })

      assert_order(result, "adequado", 2, ["turn-1", "turn-3"])
    end

    test "fewer than two performed steps score the zero-point level without evidence" do
      result =
        order_result(%{
          @history => done(@history, ["turn-1"]),
          @treatment => skipped(@treatment),
          @exams => skipped(@exams)
        })

      assert_order(result, "inadequado", Points.zero(), [])
    end

    test "an unresolved ranked criterion leaves the order uncertain" do
      assessment =
        assess!(ordered(), order_session(), %{
          @history => done(@history, ["turn-1"]),
          @exams => done(@exams, ["turn-3"])
        })

      result = criterion(assessment, @order)

      assert criterion(assessment, @treatment).status == :uncertain
      assert result.status == :uncertain
      assert result.reason == {:unresolved_ranked_criterion, @treatment}
      assert_unscored(result)
      assert %{id: @order, status: :uncertain} in assessment.estimates.unresolved
      assert assessment.estimates.total == nil
    end

    test "a ranked criterion that is not observable is skipped" do
      package =
        update_criterion(ordered(), @exams, &Map.put(&1, "modality_requirement", "laboratory"))

      assessment =
        assess!(package, order_session(), %{
          @history => done(@history, ["turn-1"]),
          @treatment => done(@treatment, ["turn-3"])
        })

      assert criterion(assessment, @exams).status == :not_observable
      assert_order(criterion(assessment, @order), "adequado", 2, ["turn-1", "turn-3"])
    end

    test "a step scored zero by a rule is skipped even though the learner attempted it" do
      # Known limitation: the missing mandatory action zeroes history-taking, so
      # its late attempt at turn-5 is not compared with the later steps.
      attempted_late =
        answer("adequado", ["turn-5"], %{
          actions: [
            not_performed("ask-onset"),
            performed("ask-duration", ["turn-5"]),
            performed("ask-intensity", ["turn-5"]),
            not_performed("ask-relief")
          ]
        })

      assessment =
        assess!(ordered(), order_session(), %{
          @history => attempted_late,
          @treatment => done(@treatment, ["turn-1"]),
          @exams => done(@exams, ["turn-3"])
        })

      assert criterion(assessment, @history).points == Points.zero()
      assert_order(criterion(assessment, @order), "adequado", 2, ["turn-1", "turn-3"])
    end

    test "a step grounded only by its actions is positioned by their evidence" do
      # history-taking earns its level by count and cites no criterion evidence.
      history = fn evidence_ids ->
        actions = [
          performed("ask-onset", evidence_ids),
          performed("ask-duration", evidence_ids),
          not_performed("ask-intensity"),
          not_performed("ask-relief")
        ]

        answer("uncertain", [], %{actions: actions})
      end

      held =
        order_result(%{
          @history => history.(["turn-1"]),
          @treatment => done(@treatment, ["turn-3"]),
          @exams => skipped(@exams)
        })

      assert_order(held, "adequado", 2, ["turn-1", "turn-3"])

      broken =
        order_result(%{
          @history => history.(["turn-5"]),
          @treatment => done(@treatment, ["turn-1"]),
          @exams => skipped(@exams)
        })

      assert_order(broken, "inadequado", Points.zero(), ["turn-1", "turn-5"])
    end

    test "an Impressos event positions the step it backs" do
      [_history, _treatment, _exams, order] = ordered()["rubric"]
      package = update_rubric(chest_pain_with_lab(), &(&1 ++ [order]))
      requested = fn at -> session([event("req-lab", ["laboratorio-sangue-enzimas"], at)]) end

      order_result = fn session, onset_evidence ->
        package
        |> assess!(session, %{
          @onset => answer("adequado", onset_evidence),
          @lab => answer("adequado", ["impresso-req-lab"])
        })
        |> criterion(@order)
      end

      assert_order(order_result.(requested.(@t3), ["turn-1"]), "adequado", 2, [
        "turn-1",
        "impresso-req-lab"
      ])

      assert_order(order_result.(requested.(@t1), ["turn-3"]), "inadequado", Points.zero(), [
        "impresso-req-lab",
        "turn-3"
      ])
    end

    test "a violation among resolved steps is certain whatever is unresolved" do
      result =
        order_result(%{
          @history => done(@history, ["turn-3"]),
          @exams => done(@exams, ["turn-1"])
        })

      assert_order(result, "inadequado", Points.zero(), ["turn-1", "turn-3"])
    end

    test "an excluded ranked criterion is not part of the order" do
      package = update_criterion(ordered(), @exams, &Map.put(&1, "exclusion", true))

      result =
        order_result(package, %{
          @history => done(@history, ["turn-1"]),
          @treatment => done(@treatment, ["turn-3"])
        })

      assert_order(result, "adequado", 2, ["turn-1", "turn-3"])
    end

    test "a criterion without a rank is not part of the order" do
      package = update_criterion(ordered(), @exams, &Map.put(&1, "order", nil))

      result =
        order_result(package, %{
          @history => done(@history, ["turn-3"]),
          @treatment => done(@treatment, ["turn-5"]),
          @exams => done(@exams, ["turn-1"])
        })

      assert_order(result, "adequado", 2, ["turn-3", "turn-5"])
    end

    test "the classifier never receives the task-order criterion" do
      assessment = assess!(ordered(), order_session(), %{})

      assert_received {:batch_request, request}
      assert asked_ids(request) == [@history, @treatment, @exams]
      assert assessment.calls == [%{question_count: 3, justification: :single_batch}]
    end

    test "a decision for the task-order criterion is unknown to the batch contract" do
      reply = fn request ->
        extra = %{criterion_id: @order, classification: "adequado", evidence_ids: []}
        {:ok, %{decisions: ScriptedDouble.decisions(request, %{}) ++ [extra]}}
      end

      # It was never asked, so its identifier is unknown rather than a duplicate.
      assert_invalid_attempt(
        assess(ordered(), order_session(), %{}, reply: reply),
        {:invalid_response, :unknown_criterion_id}
      )
    end

    test "a capacity split never carries the task-order criterion" do
      assessment =
        assess!(
          ordered(),
          order_session(),
          %{
            @history => done(@history, ["turn-1"]),
            @treatment => done(@treatment, ["turn-3"]),
            @exams => done(@exams, ["turn-5"])
          },
          max_questions_per_call: 2
        )

      assert assessment.calls == [
               %{question_count: 2, justification: :single_batch},
               %{question_count: 1, justification: :provider_capacity}
             ]

      assert_received {:batch_request, first}
      assert_received {:batch_request, second}
      refute_received {:batch_request, _}

      assert asked_ids(first) == [@history, @treatment]
      assert asked_ids(second) == [@exams]
      assert_order(criterion(assessment, @order), "adequado", 2, ["turn-1", "turn-3", "turn-5"])
    end

    test "a rubric whose only active question is the order makes no call" do
      package =
        Enum.reduce([@history, @treatment, @exams], ordered(), fn id, package ->
          update_criterion(package, id, &Map.put(&1, "exclusion", true))
        end)

      assessment = assess!(package, order_session(), %{})

      refute_received {:batch_request, _}
      assert assessment.calls == []
      assert_order(criterion(assessment, @order), "inadequado", Points.zero(), [])
    end

    test "totals and the legacy projection treat it like any other criterion" do
      assessment =
        assess!(ordered(), order_session(), %{
          @history => done(@history, ["turn-1"]),
          @treatment => done(@treatment, ["turn-3"]),
          @exams => done(@exams, ["turn-5"])
        })

      assert assessment.estimates == %{
               total: 16,
               scored_subtotal: 16,
               scored_max: 20,
               eligible_max: 20,
               unresolved: []
             }

      assert Enum.map(assessment.criteria, & &1.id) == [@history, @treatment, @exams, @order]

      assert %{status: :met, evidence: [_, _, _]} =
               assessment |> RubricAssessment.to_legacy() |> criterion(@order)
    end

    test "the legacy projection maps a broken order to omitted and an open one to uncertain" do
      legacy_order = fn answers ->
        ordered()
        |> assess!(order_session(), answers)
        |> RubricAssessment.to_legacy()
        |> criterion(@order)
      end

      broken =
        legacy_order.(%{
          @history => done(@history, ["turn-3"]),
          @treatment => done(@treatment, ["turn-1"]),
          @exams => skipped(@exams)
        })

      assert broken.status == :omitted

      assert broken.evidence == [
               %{role: :learner, text: "Quando começou?"},
               %{role: :learner, text: "Vou indicar o tratamento."}
             ]

      open =
        legacy_order.(%{
          @history => done(@history, ["turn-1"]),
          @exams => done(@exams, ["turn-3"])
        })

      assert open.status == :uncertain
      assert open.evidence == []
    end

    test "an excluded order criterion is not assessed and stays outside the totals" do
      package = update_criterion(ordered(), @order, &Map.put(&1, "exclusion", true))

      assessment =
        assess!(package, order_session(), %{
          @history => done(@history, ["turn-1"]),
          @treatment => done(@treatment, ["turn-3"]),
          @exams => done(@exams, ["turn-5"])
        })

      result = criterion(assessment, @order)

      assert result.status == :not_applicable
      assert result.reason == :authored_exclusion
      assert result.max_points == 2
      assert_unscored(result)

      assert assessment.estimates == %{
               total: 14,
               scored_subtotal: 14,
               scored_max: 18,
               eligible_max: 18,
               unresolved: []
             }

      legacy = RubricAssessment.to_legacy(assessment)
      assert Enum.map(legacy.criteria, & &1.id) == [@history, @treatment, @exams]
    end

    test "a task-order criterion without a zero-point level invalidates the attempt" do
      broken =
        update_criterion(ordered(), @order, fn criterion ->
          put_in(criterion, ["levels", Access.at(0), "points"], 0.125)
        end)

      assert_invalid_attempt(
        assess(broken, order_session(), %{}),
        {:invalid_package, @order, :missing_zero_point_level}
      )

      refute_received {:batch_request, _}
    end
  end

  # ============================================================================
  # First-N answers
  # ============================================================================

  describe "assess/3 first-N answers" do
    # turn-2 is the only patient turn; every other turn is a learner turn.
    defp answers_session do
      texts = ["Primeira.", "Resposta.", "Segunda.", "Terceira.", "Quarta.", "Quinta."]

      messages =
        for {text, index} <- Enum.with_index(texts) do
          role = if index == 1, do: :patient, else: :learner
          turn(role, text, DateTime.add(@t0, index, :second))
        end

      %{messages: messages, impresso_requests: []}
    end

    defp said(evidence_id, action_id \\ nil),
      do: %{evidence_id: evidence_id, action_id: action_id}

    # history-taking with `first_n: 3`: thresholds 0/2/3 for 0/0.5/1, capped at
    # three, `ask-onset` mandatory and three counted actions.
    defp first_three do
      ordered() |> only([@history]) |> update_criterion(@history, &Map.put(&1, "first_n", 3))
    end

    # treatment-plan with `first_n: 1` and thresholds 0/1: one counted and one
    # forbidden action.
    defp first_one do
      ordered()
      |> only([@treatment])
      |> update_criterion(@treatment, &(&1 |> Map.put("first_n", 1) |> thresholds([0, 1])))
    end

    # history-taking with thresholds 0/1/2 capped at two: `ask-onset` mandatory
    # and three counted actions.
    defp capped_history(first_n) do
      ordered()
      |> only([@history])
      |> update_criterion(@history, fn criterion ->
        criterion |> Map.merge(%{"first_n" => first_n, "count_cap" => 2}) |> thresholds([0, 1, 2])
      end)
    end

    defp thresholds(criterion, min_actions) do
      Map.update!(criterion, "levels", fn levels ->
        for {level, min} <- Enum.zip(levels, min_actions), do: Map.put(level, "min_actions", min)
      end)
    end

    defp capped_history_result(first_n, actions, answers) do
      decision = answer("adequado", [], %{actions: actions, answers: answers})

      first_n
      |> capped_history()
      |> assess!(answers_session(), %{@history => decision})
      |> criterion(@history)
    end

    # exam-requests as authored: `first_n: 2`, `count_cap: 1`, thresholds 0/1.
    defp first_two, do: only(ordered(), [@exams])

    defp history_result(actions, answers, classification \\ "inadequado") do
      decision = answer(classification, [], %{actions: actions, answers: answers})

      first_three() |> assess!(answers_session(), %{@history => decision}) |> criterion(@history)
    end

    defp exams_result(actions, answers) do
      decision = answer("uncertain", [], %{actions: actions, answers: answers})

      first_two() |> assess!(answers_session(), %{@exams => decision}) |> criterion(@exams)
    end

    defp all_history_performed do
      [
        performed("ask-onset", ["turn-1"]),
        performed("ask-duration", ["turn-3"]),
        performed("ask-intensity", ["turn-4"]),
        performed("ask-relief", ["turn-5"])
      ]
    end

    test "the enumeration is requested only where first_n and actions are both authored" do
      assess!(ordered(), order_session(), %{})
      assert_received {:batch_request, %{questions: [history, treatment, exams]}}

      refute Map.has_key?(history, :enumerate_answers)
      refute Map.has_key?(treatment, :enumerate_answers)
      assert exams.enumerate_answers == true

      # symptom-characterization authors `first_n: 1` and no action.
      assess!(v2(), session(), %{})
      assert_received {:batch_request, %{questions: questions}}

      refute Enum.any?(questions, &Map.has_key?(&1, :enumerate_answers))
    end

    test "first_n without actions behaves as before" do
      result =
        v2()
        |> assess!(session(), %{@symptom => answer("adequado", ["turn-3"])})
        |> criterion(@symptom)

      assert result.status == :assessed
      assert result.level == "adequado"
      assert result.points == 2
    end

    test "the N-th answer is scored" do
      actions = [
        performed("ask-onset", ["turn-1"]),
        performed("ask-duration", ["turn-3"]),
        performed("ask-intensity", ["turn-4"]),
        not_performed("ask-relief")
      ]

      answers = [
        said("turn-1", "ask-onset"),
        said("turn-3", "ask-duration"),
        said("turn-4", "ask-intensity")
      ]

      result = history_result(actions, answers)

      assert result.status == :assessed
      assert result.level == "adequado"
      assert result.points == 8
      assert result.evidence_ids == ["turn-1", "turn-3", "turn-4"]
    end

    test "the answer after the N-th is not scored and does not ground the level" do
      answers = [
        said("turn-1", "ask-onset"),
        said("turn-3", "ask-duration"),
        said("turn-4", "ask-intensity"),
        said("turn-5", "ask-relief")
      ]

      result = history_result(all_history_performed(), answers)

      assert result.status == :assessed
      assert result.level == "adequado"
      assert result.evidence_ids == ["turn-1", "turn-3", "turn-4"]
      # The classifier's reading is reported as it was given.
      assert result.sub_actions == all_history_performed()
    end

    test "an answer that matches no authored action consumes a slot" do
      actions = [
        performed("ask-onset", ["turn-1"]),
        performed("ask-duration", ["turn-3"]),
        performed("ask-intensity", ["turn-5"]),
        not_performed("ask-relief")
      ]

      answers = [
        said("turn-1", "ask-onset"),
        said("turn-3", "ask-duration"),
        said("turn-4"),
        said("turn-5", "ask-intensity")
      ]

      result = history_result(actions, answers, "adequado")

      assert result.status == :assessed
      assert result.level == "parcialmente_adequado"
      assert result.points == 4
      assert result.evidence_ids == ["turn-1", "turn-3"]
    end

    test "a mandatory action beyond the first N scores the zero-point level" do
      answers = [
        said("turn-1", "ask-duration"),
        said("turn-3", "ask-intensity"),
        said("turn-4", "ask-relief"),
        said("turn-5", "ask-onset")
      ]

      actions = [
        performed("ask-onset", ["turn-5"]),
        performed("ask-duration", ["turn-1"]),
        performed("ask-intensity", ["turn-3"]),
        performed("ask-relief", ["turn-4"])
      ]

      result = history_result(actions, answers, "adequado")

      assert result.status == :assessed
      assert result.level == "inadequado"
      assert result.points == Points.zero()
      assert result.reason == nil
    end

    test "a forbidden action beyond the first N still scores the zero-point level" do
      treatment = fn contraindicated, answers ->
        actions = [performed("indicate-expected", ["turn-1"]), contraindicated]
        decision = answer("adequado", ["turn-1"], %{actions: actions, answers: answers})

        first_one()
        |> assess!(answers_session(), %{@treatment => decision})
        |> criterion(@treatment)
      end

      vetoed =
        treatment.(
          performed("indicate-contraindicated", ["turn-3"]),
          [said("turn-1", "indicate-expected"), said("turn-3", "indicate-contraindicated")]
        )

      assert vetoed.status == :assessed
      assert vetoed.level == "inadequado"
      assert vetoed.points == Points.zero()
      assert vetoed.evidence_ids == ["turn-1", "turn-3"]

      kept =
        treatment.(not_performed("indicate-contraindicated"), [
          said("turn-1", "indicate-expected")
        ])

      assert kept.level == "adequado"
      assert kept.points == 8
    end

    test "thresholds and count_cap apply to the eligible answers only" do
      both = [performed("request-exam-a", ["turn-3"]), performed("request-exam-b", ["turn-4"])]

      one_eligible =
        exams_result(both, [
          said("turn-1"),
          said("turn-3", "request-exam-a"),
          said("turn-4", "request-exam-b")
        ])

      assert one_eligible.level == "adequado"
      assert one_eligible.points == 2
      assert one_eligible.evidence_ids == ["turn-3"]

      none_eligible =
        exams_result(both, [
          said("turn-1"),
          said("turn-1"),
          said("turn-3", "request-exam-a"),
          said("turn-4", "request-exam-b")
        ])

      assert none_eligible.status == :assessed
      assert none_eligible.level == "inadequado"
      assert none_eligible.points == Points.zero()
      assert none_eligible.evidence_ids == []

      # Two eligible actions are capped at one, and both ground the level.
      capped =
        exams_result(both, [said("turn-3", "request-exam-a"), said("turn-4", "request-exam-b")])

      assert capped.level == "adequado"
      assert capped.points == 2
      assert capped.evidence_ids == ["turn-3", "turn-4"]
    end

    test "an unsupported action stays unresolved within the first N and is certain beyond it" do
      actions = [
        performed("ask-onset", ["turn-1"]),
        performed("ask-duration", ["turn-3"]),
        performed("ask-intensity", []),
        not_performed("ask-relief")
      ]

      within =
        history_result(actions, [
          said("turn-1", "ask-onset"),
          said("turn-3", "ask-duration"),
          said("turn-4", "ask-intensity")
        ])

      assert within.status == :uncertain
      assert within.reason == {:unsupported_sub_action, "ask-intensity"}

      beyond =
        history_result(actions, [
          said("turn-1", "ask-onset"),
          said("turn-3", "ask-duration"),
          said("turn-4"),
          said("turn-5", "ask-intensity")
        ])

      assert beyond.status == :assessed
      assert beyond.level == "parcialmente_adequado"
    end

    test "an answer whose evidence fails validation fails the criterion closed" do
      cases = [
        {"turn-2", {:invalid_evidence, :wrong_role, "turn-2"}},
        {"turn-99", {:invalid_evidence, :nonexistent_evidence_id, "turn-99"}}
      ]

      for {evidence_id, reason} <- cases do
        answers = [
          said("turn-1", "ask-onset"),
          said(evidence_id),
          said("turn-3", "ask-duration"),
          said("turn-4", "ask-intensity"),
          said("turn-5", "ask-relief")
        ]

        result = history_result(all_history_performed(), answers)

        assert result.status == :uncertain
        assert result.reason == reason
        assert_unscored(result)
      end
    end

    test "answers listed against the evidence order fail the criterion closed" do
      answers = [
        said("turn-1", "ask-onset"),
        said("turn-4", "ask-intensity"),
        said("turn-3", "ask-duration"),
        said("turn-5", "ask-relief")
      ]

      result = history_result(all_history_performed(), answers)

      assert result.status == :uncertain
      assert result.reason == {:answer_out_of_order, "turn-3"}
      assert_unscored(result)
    end

    test "one turn may hold several answers" do
      actions = Enum.map(all_history_performed(), &%{&1 | evidence_ids: ["turn-1"]})

      answers = [
        said("turn-1", "ask-onset"),
        said("turn-1", "ask-duration"),
        said("turn-1", "ask-intensity"),
        said("turn-1", "ask-relief")
      ]

      result = history_result(actions, answers)

      assert result.status == :assessed
      assert result.level == "adequado"
      assert result.evidence_ids == ["turn-1"]
    end

    test "a performed action that is not enumerated fails the criterion closed" do
      answers = [
        said("turn-1", "ask-onset"),
        said("turn-3", "ask-duration"),
        said("turn-5", "ask-relief")
      ]

      result = history_result(all_history_performed(), answers)

      assert result.status == :uncertain
      assert result.reason == {:unlisted_performed_action, "ask-intensity"}
      assert_unscored(result)
    end

    test "an enumerated action that was not classified performed fails the criterion closed" do
      for unperformed <- [not_performed("ask-relief"), uncertain("ask-relief")] do
        actions = [
          performed("ask-onset", ["turn-1"]),
          performed("ask-duration", ["turn-3"]),
          performed("ask-intensity", ["turn-4"]),
          unperformed
        ]

        answers = [
          said("turn-1", "ask-onset"),
          said("turn-3", "ask-duration"),
          said("turn-4", "ask-intensity"),
          said("turn-5", "ask-relief")
        ]

        result = history_result(actions, answers)

        assert result.status == :uncertain
        assert result.reason == {:listed_unperformed_action, "ask-relief"}
        assert_unscored(result)
      end
    end

    test "an unresolved action may displace an eligible answer once the list is full" do
      # If `ask-intensity` was asked at turn-3, the mandatory `ask-onset` is the
      # third answer and the criterion scores zero.
      actions = [
        performed("ask-onset", ["turn-4"]),
        performed("ask-duration", ["turn-1"]),
        uncertain("ask-intensity"),
        not_performed("ask-relief")
      ]

      answers = [said("turn-1", "ask-duration"), said("turn-4", "ask-onset")]

      full = capped_history_result(2, actions, answers)

      assert full.status == :uncertain
      assert full.reason == {:uncertain_sub_action, "ask-intensity"}
      assert_unscored(full)

      # With a free slot the extra answer displaces nothing, and the capped
      # count is two either way.
      free = capped_history_result(3, actions, answers)

      assert free.status == :assessed
      assert free.level == "adequado"
      assert free.evidence_ids == ["turn-1", "turn-4"]
    end

    test "several unresolved actions may fill the free slots and displace an answer" do
      actions = [
        performed("ask-onset", ["turn-4"]),
        performed("ask-duration", ["turn-1"]),
        uncertain("ask-intensity"),
        uncertain("ask-relief")
      ]

      answers = [said("turn-1", "ask-duration"), said("turn-4", "ask-onset")]

      crowded = capped_history_result(3, actions, answers)

      assert crowded.status == :uncertain
      assert crowded.reason == {:uncertain_sub_action, "ask-intensity"}

      roomy = capped_history_result(4, actions, answers)

      assert roomy.status == :assessed
      assert roomy.level == "adequado"
    end

    test "a certain zero stands whatever an unresolved action could displace" do
      missing_mandatory =
        capped_history_result(
          2,
          [
            not_performed("ask-onset"),
            performed("ask-duration", ["turn-1"]),
            uncertain("ask-intensity"),
            performed("ask-relief", ["turn-4"])
          ],
          [said("turn-1", "ask-duration"), said("turn-4", "ask-relief")]
        )

      mandatory_beyond =
        capped_history_result(
          2,
          [
            performed("ask-onset", ["turn-5"]),
            performed("ask-duration", ["turn-1"]),
            uncertain("ask-intensity"),
            performed("ask-relief", ["turn-4"])
          ],
          [
            said("turn-1", "ask-duration"),
            said("turn-4", "ask-relief"),
            said("turn-5", "ask-onset")
          ]
        )

      for result <- [missing_mandatory, mandatory_beyond] do
        assert result.status == :assessed
        assert result.level == "inadequado"
        assert result.points == Points.zero()
      end

      vetoed_decision =
        answer("adequado", [], %{
          actions: [
            performed("indicate-expected", []),
            performed("indicate-contraindicated", ["turn-3"])
          ],
          answers: [
            said("turn-1", "indicate-expected"),
            said("turn-3", "indicate-contraindicated")
          ]
        })

      vetoed =
        first_one()
        |> assess!(answers_session(), %{@treatment => vetoed_decision})
        |> criterion(@treatment)

      assert vetoed.status == :assessed
      assert vetoed.level == "inadequado"
      assert vetoed.evidence_ids == ["turn-3"]
    end

    test "a classifier that is uncertain about the criterion does not stop the first N" do
      actions = [
        performed("ask-onset", ["turn-1"]),
        performed("ask-duration", ["turn-3"]),
        performed("ask-intensity", ["turn-5"]),
        not_performed("ask-relief")
      ]

      answers = [
        said("turn-1", "ask-onset"),
        said("turn-3", "ask-duration"),
        said("turn-4"),
        said("turn-5", "ask-intensity")
      ]

      result = history_result(actions, answers, "uncertain")

      assert result.status == :assessed
      assert result.level == "parcialmente_adequado"
      assert result.evidence_ids == ["turn-1", "turn-3"]
    end

    test "an answer must cite evidence of the action it names" do
      # The action is grounded at turn-4, the third answer; listing it at turn-1
      # would make it the first.
      mismatched =
        exams_result(
          [performed("request-exam-a", ["turn-4"]), not_performed("request-exam-b")],
          [said("turn-1", "request-exam-a")]
        )

      assert mismatched.status == :uncertain
      assert mismatched.reason == {:answer_evidence_mismatch, "request-exam-a"}
      assert_unscored(mismatched)

      # Any of the action's own evidence items is an acceptable position.
      matched =
        exams_result(
          [performed("request-exam-a", ["turn-3", "turn-4"]), not_performed("request-exam-b")],
          [said("turn-1"), said("turn-4", "request-exam-a")]
        )

      assert matched.status == :assessed
      assert matched.level == "adequado"
    end

    test "first_n with actions and no thresholds invalidates the attempt before any call" do
      # The classifier's holistic level cannot be limited to the first N answers.
      package =
        ordered()
        |> only([@treatment])
        |> update_criterion(@treatment, &Map.put(&1, "first_n", 1))

      decision =
        answer("adequado", ["turn-4"], %{
          actions: [
            performed("indicate-expected", ["turn-4"]),
            not_performed("indicate-contraindicated")
          ],
          answers: [said("turn-1"), said("turn-4", "indicate-expected")]
        })

      assert_invalid_attempt(
        assess(package, answers_session(), %{@treatment => decision}),
        {:invalid_package, @treatment, :first_n_without_thresholds}
      )

      refute_received {:batch_request, _request}
    end

    test "an Impressos event is an answer like any turn" do
      package =
        update_criterion(chest_pain_with_lab(), @lab, fn criterion ->
          action = %{"id" => "request-enzymes", "description" => "Requests cardiac enzymes."}

          criterion |> Map.merge(%{"actions" => [action], "first_n" => 1}) |> thresholds([0, 1])
        end)

      events = [
        event("req-other", ["laboratorio-sangue-enzimas"], @t1),
        event("req-lab", ["laboratorio-sangue-enzimas"], @t3, %{order: 2})
      ]

      lab_result = fn answers ->
        decision =
          answer("adequado", [], %{
            actions: [performed("request-enzymes", ["impresso-req-lab"])],
            answers: answers
          })

        package |> assess!(session(events), %{@lab => decision}) |> criterion(@lab)
      end

      first = lab_result.([said("impresso-req-lab", "request-enzymes")])

      assert first.status == :assessed
      assert first.level == "adequado"
      assert first.evidence_ids == ["impresso-req-lab"]

      second =
        lab_result.([said("impresso-req-other"), said("impresso-req-lab", "request-enzymes")])

      assert second.status == :assessed
      assert second.level == "inadequado"
      assert second.points == Points.zero()

      # A turn is not valid evidence for an Impressos-category criterion.
      wrong_channel = lab_result.([said("turn-1"), said("impresso-req-lab", "request-enzymes")])

      assert wrong_channel.status == :uncertain
      assert wrong_channel.reason == {:invalid_evidence, :wrong_channel, "turn-1"}
    end

    test "a structurally invalid enumeration invalidates the attempt" do
      exams = fn overrides ->
        actions = [performed("request-exam-a", ["turn-1"]), not_performed("request-exam-b")]
        decision = Map.merge(answer("adequado", ["turn-1"], %{actions: actions}), overrides)

        assess(first_two(), answers_session(), %{@exams => decision})
      end

      cases = [
        {%{answers: nil}, :missing_answers},
        {%{answers: "turn-1"}, :expected_answers_list},
        {%{answers: [said("turn-1", "request-exam-z")]}, :unknown_answer_action_id},
        {%{answers: [said("turn-1", "request-exam-a"), said("turn-3", "request-exam-a")]},
         :duplicate_answer_action_id}
      ]

      for {overrides, reason} <- cases do
        assert {:error, {:invalid_attempt, {_kind, ^reason}}} = exams.(overrides)
      end

      # symptom-characterization authors no action, so nothing was requested.
      unrequested = answer("adequado", ["turn-3"], %{answers: [said("turn-3")]})

      assert_invalid_attempt(
        assess(v2(), session(), %{@symptom => unrequested}),
        {:invalid_response, :unexpected_answers}
      )
    end

    test "a capacity split keeps the enumeration with its question" do
      beyond = [
        said("turn-1"),
        said("turn-3"),
        said("turn-5", "request-exam-a")
      ]

      assessment =
        assess!(
          ordered(),
          order_session(),
          %{
            @history => done(@history, ["turn-1"]),
            @treatment => done(@treatment, ["turn-3"]),
            @exams => Map.put(done(@exams, ["turn-5"]), :answers, beyond)
          },
          max_questions_per_call: 1
        )

      assert Enum.map(assessment.calls, & &1.justification) ==
               [:single_batch, :provider_capacity, :provider_capacity]

      assert_received {:batch_request, %{questions: [first]}}
      assert_received {:batch_request, %{questions: [second]}}
      assert_received {:batch_request, %{questions: [third]}}

      refute Map.has_key?(first, :enumerate_answers)
      refute Map.has_key?(second, :enumerate_answers)
      assert third.enumerate_answers == true

      result = criterion(assessment, @exams)

      assert result.status == :assessed
      assert result.level == "inadequado"
      assert result.points == Points.zero()
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
