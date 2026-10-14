defmodule Backend.Stations.JevDecision.RubricBatchTest do
  use ExUnit.Case, async: true

  alias Backend.Stations.JevDecision
  alias Backend.Stations.JevDecision.DisabledAdapter

  @moduletag capture_log: true

  # ============================================================================
  # Deterministic doubles
  # ============================================================================

  defmodule ScriptedDouble do
    @moduledoc """
    Deterministic batch adapter. The reply is scripted per test through
    `opts[:reply]` (a term or a one-arity function of the received request) and
    every received request is reported to `opts[:test_pid]`.
    """
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request), do: {:ok, %{status: :verified}}

    @impl true
    def decide_rubric(request) do
      {:ok, %{classification: hd(request.allowed_classes), evidence_ids: []}}
    end

    @impl true
    def decide_rubric_batch(request), do: decide_rubric_batch(request, [])

    def decide_rubric_batch(request, opts) do
      if pid = opts[:test_pid], do: send(pid, {:batch_request, request})

      case opts[:reply] do
        fun when is_function(fun, 1) -> fun.(request)
        nil -> {:ok, %{decisions: Enum.map(request.questions, &first_class_decision/1)}}
        reply -> reply
      end
    end

    defp first_class_decision(question) do
      %{
        criterion_id: question.criterion.id,
        classification: hd(question.allowed_classes),
        evidence_ids: [],
        actions:
          Enum.map(question.actions, fn action ->
            %{id: action.id, classification: "uncertain", evidence_ids: []}
          end)
      }
    end
  end

  defmodule SingleOnlyDouble do
    @moduledoc "Adapter that predates the batch callback."
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request), do: {:ok, %{status: :verified}}

    @impl true
    def decide_rubric(request) do
      send(self(), :serial_fallback_used)
      {:ok, %{classification: hd(request.allowed_classes), evidence_ids: []}}
    end
  end

  # ============================================================================
  # Fixtures
  # ============================================================================

  @classes ["adequado", "inadequado", "uncertain"]

  defp question(id, overrides \\ %{}) do
    Map.merge(
      %{criterion: %{id: id, description: "Description of #{id}"}, allowed_classes: @classes},
      overrides
    )
  end

  defp pool do
    [
      %{id: "turn-1", role: "student", text: "Bom dia, sou o estudante."},
      %{id: "turn-2", role: "patient", text: "Bom dia, doutor."},
      %{id: "impresso-req-1", role: "student", text: "Solicitou ECG."}
    ]
  end

  defp request(questions, overrides \\ %{}) do
    Map.merge(%{questions: questions, evidence_pool: pool()}, overrides)
  end

  defp decision(id, overrides \\ %{}) do
    Map.merge(
      %{criterion_id: id, classification: "adequado", evidence_ids: ["turn-1"]},
      overrides
    )
  end

  defp decide(request, reply, opts \\ []) do
    JevDecision.decide_rubric_batch(
      request,
      [adapter: ScriptedDouble, test_pid: self(), reply: reply] ++ opts
    )
  end

  defp reply_with(decisions), do: {:ok, %{decisions: decisions}}

  defp actions_question do
    question("crit-1", %{
      actions: [
        %{id: "act-a", description: "Washes hands"},
        %{id: "act-b", description: "Introduces self"}
      ]
    })
  end

  defp action_decision(id, overrides \\ %{}) do
    Map.merge(%{id: id, classification: "performed", evidence_ids: ["turn-1"]}, overrides)
  end

  # ============================================================================
  # Batching
  # ============================================================================

  describe "decide_rubric_batch/2 batching" do
    test "classifies several questions with one adapter call and one shared pool" do
      questions = [question("crit-1"), question("crit-2"), question("crit-3")]

      assert {:ok, decisions} = decide(request(questions), nil)
      assert Enum.map(decisions, & &1.criterion_id) == ["crit-1", "crit-2", "crit-3"]

      assert_received {:batch_request, sent}
      refute_received {:batch_request, _}

      assert length(sent.questions) == 3
      assert length(sent.evidence_pool) == 3
      refute Enum.any?(sent.questions, &Map.has_key?(&1, :evidence_pool))
    end

    test "sends a minimized request and tolerates string keys" do
      request = %{
        "questions" => [
          %{
            "criterion" => %{
              "id" => "crit-1",
              "description" => "Presents self",
              "points" => 1.25,
              "levels" => [%{"id" => "adequado"}]
            },
            "allowed_classes" => ["adequado", "inadequado"],
            "actions" => [%{"id" => "act-a", "description" => "Says name", "mandatory" => true}],
            "veto" => true
          },
          %{
            criterion: %{id: "crit-2", description: "Asks about pain", order: 2},
            allowed_classes: ["adequado", "uncertain"]
          }
        ],
        "evidence_pool" => [
          %{
            "id" => "turn-1",
            "role" => "student",
            "text" => "Olá",
            "session_id" => "s-1",
            "provenance" => "transcript"
          }
        ],
        "session_id" => "s-1"
      }

      assert {:ok, [_first, _second]} = decide(request, nil, deadline_ms: 500)
      assert_received {:batch_request, sent}

      assert Map.keys(sent) |> Enum.sort() ==
               [:deadline_at_monotonic_ms, :deadline_ms, :evidence_pool, :questions]

      assert sent.deadline_ms == 500
      assert is_integer(sent.deadline_at_monotonic_ms)

      assert sent.questions == [
               %{
                 criterion: %{id: "crit-1", description: "Presents self"},
                 allowed_classes: ["adequado", "inadequado"],
                 actions: [%{id: "act-a", description: "Says name"}]
               },
               %{
                 criterion: %{id: "crit-2", description: "Asks about pain"},
                 allowed_classes: ["adequado", "uncertain"],
                 actions: []
               }
             ]

      assert sent.evidence_pool == [%{id: "turn-1", role: "student", text: "Olá"}]
    end

    test "returns normalized decisions in question order, not adapter order" do
      questions = [question("crit-1"), question("crit-2"), question("crit-3")]

      reply =
        reply_with([
          decision("crit-3", %{classification: "uncertain", evidence_ids: []}),
          %{
            "criterion_id" => "crit-1",
            "classification" => "adequado",
            "evidence_ids" => ["turn-1"],
            "rationale" => "Greeted the patient"
          },
          decision("crit-2", %{classification: "inadequado", evidence_ids: ["turn-1"]})
        ])

      assert {:ok, decisions} = decide(request(questions), reply)

      assert decisions == [
               %{
                 criterion_id: "crit-1",
                 classification: "adequado",
                 evidence_ids: ["turn-1"],
                 rationale: "Greeted the patient",
                 actions: []
               },
               %{
                 criterion_id: "crit-2",
                 classification: "inadequado",
                 evidence_ids: ["turn-1"],
                 rationale: nil,
                 actions: []
               },
               %{
                 criterion_id: "crit-3",
                 classification: "uncertain",
                 evidence_ids: [],
                 rationale: nil,
                 actions: []
               }
             ]
    end

    test "tolerates a string-keyed decisions envelope" do
      reply = {:ok, %{"decisions" => [decision("crit-1")]}}

      assert {:ok, [%{criterion_id: "crit-1"}]} = decide(request([question("crit-1")]), reply)
    end

    test "accepts an empty evidence pool" do
      request = request([question("crit-1")], %{evidence_pool: []})
      reply = reply_with([decision("crit-1", %{classification: "uncertain", evidence_ids: []})])

      assert {:ok, [%{classification: "uncertain", evidence_ids: []}]} = decide(request, reply)
      assert_received {:batch_request, %{evidence_pool: []}}
    end

    test "defaults missing evidence_ids to an empty list" do
      reply = reply_with([%{criterion_id: "crit-1", classification: "adequado"}])

      assert {:ok, [%{evidence_ids: []}]} = decide(request([question("crit-1")]), reply)
    end

    test "returns evidence IDs absent from the pool verbatim for the caller to validate" do
      reply = reply_with([decision("crit-1", %{evidence_ids: ["turn-1", "turn-999", "turn-2"]})])

      assert {:ok, [%{evidence_ids: ["turn-1", "turn-999", "turn-2"]}]} =
               decide(request([question("crit-1")]), reply)
    end
  end

  # ============================================================================
  # Request validation
  # ============================================================================

  describe "decide_rubric_batch/2 request validation" do
    defp assert_invalid_request(request, reason) do
      assert {:error, {:invalid_request, ^reason}} = decide(request, nil)
      refute_received {:batch_request, _}
    end

    test "rejects a non-map request" do
      assert_invalid_request([question("crit-1")], :expected_map)
    end

    test "rejects a missing or non-list questions field" do
      assert_invalid_request(%{evidence_pool: pool()}, :invalid_questions)
      assert_invalid_request(request("crit-1"), :invalid_questions)
    end

    test "rejects an empty question list" do
      assert_invalid_request(request([]), :empty_questions)
    end

    test "rejects a question that is not a map" do
      assert_invalid_request(request(["crit-1"]), :invalid_question)
    end

    test "rejects a missing, blank or non-binary criterion ID" do
      assert_invalid_request(request([%{allowed_classes: @classes}]), :invalid_criterion)
      assert_invalid_request(request([question("  ")]), :invalid_criterion)
      assert_invalid_request(request([question(42)]), :invalid_criterion)
    end

    test "rejects duplicate criterion IDs" do
      assert_invalid_request(
        request([question("crit-1"), question("crit-2"), question("crit-1")]),
        :duplicate_criterion_ids
      )
    end

    test "rejects missing, empty or blank allowed classes" do
      for classes <- [nil, [], "adequado", ["adequado", ""], ["adequado", :uncertain]] do
        assert_invalid_request(
          request([question("crit-1", %{allowed_classes: classes})]),
          :invalid_allowed_classes
        )
      end
    end

    test "rejects malformed actions" do
      for actions <- ["act-a", ["act-a"], [%{description: "No id"}], [%{id: " "}]] do
        assert_invalid_request(
          request([question("crit-1", %{actions: actions})]),
          :invalid_actions
        )
      end
    end

    test "rejects duplicate action IDs within a question" do
      actions = [%{id: "act-a", description: "One"}, %{id: "act-a", description: "Two"}]

      assert_invalid_request(
        request([question("crit-1", %{actions: actions})]),
        :duplicate_action_ids
      )
    end

    test "allows the same action ID in different questions" do
      actions = [%{id: "act-a", description: "One"}]

      questions = [
        question("crit-1", %{actions: actions}),
        question("crit-2", %{actions: actions})
      ]

      assert {:ok, [_first, _second]} = decide(request(questions), nil)
    end

    test "rejects a malformed evidence pool" do
      for pool <- ["turn-1", ["turn-1"], [%{role: "student", text: "No id"}], [%{id: ""}]] do
        assert_invalid_request(
          request([question("crit-1")], %{evidence_pool: pool}),
          :invalid_evidence_pool
        )
      end
    end

    test "rejects duplicate evidence pool IDs" do
      pool = [
        %{id: "turn-1", role: "student", text: "A"},
        %{id: "turn-1", role: "student", text: "B"}
      ]

      assert_invalid_request(
        request([question("crit-1")], %{evidence_pool: pool}),
        :duplicate_evidence_ids
      )
    end

    test "rejects an invalid deadline" do
      assert_invalid_request(request([question("crit-1")], %{deadline_ms: 0}), :invalid_deadline)
    end
  end

  # ============================================================================
  # Response validation: criterion structure
  # ============================================================================

  describe "decide_rubric_batch/2 response validation" do
    defp assert_response_error(decisions, error, questions \\ nil) do
      questions = questions || [question("crit-1"), question("crit-2")]

      assert {:error, ^error} = decide(request(questions), reply_with(decisions))
      assert JevDecision.technical_failure?(error)
    end

    test "rejects a missing decision" do
      assert_response_error(
        [decision("crit-1")],
        {:invalid_response, :missing_criterion_decision}
      )
    end

    test "rejects a duplicated criterion ID" do
      assert_response_error(
        [decision("crit-1"), decision("crit-2"), decision("crit-1")],
        {:invalid_response, :duplicate_criterion_id}
      )
    end

    test "rejects an unknown criterion ID" do
      assert_response_error(
        [decision("crit-1"), decision("crit-2"), decision("crit-9")],
        {:invalid_response, :unknown_criterion_id}
      )
    end

    test "rejects a missing or non-binary criterion ID" do
      assert_response_error(
        [decision("crit-1"), %{classification: "adequado", evidence_ids: []}],
        {:invalid_response, :invalid_criterion_id}
      )

      assert_response_error(
        [decision("crit-1"), decision(:"crit-2")],
        {:invalid_response, :invalid_criterion_id}
      )
    end

    test "rejects a classification outside that question's allowed classes" do
      questions = [
        question("crit-1", %{allowed_classes: ["adequado", "inadequado"]}),
        question("crit-2", %{allowed_classes: ["parcial", "uncertain"]})
      ]

      assert_response_error(
        [decision("crit-1"), decision("crit-2", %{classification: "adequado"})],
        {:invalid_response, :disallowed_classification},
        questions
      )
    end

    test "rejects a missing or non-binary classification" do
      assert_response_error(
        [decision("crit-1"), %{criterion_id: "crit-2", evidence_ids: []}],
        {:invalid_response, :missing_classification}
      )

      assert_response_error(
        [decision("crit-1"), decision("crit-2", %{classification: :adequado})],
        {:invalid_response, :invalid_classification_type}
      )
    end

    test "rejects evidence IDs that are not a list of binaries" do
      for evidence_ids <- ["turn-1", ["turn-1", 2], %{id: "turn-1"}] do
        assert_response_error(
          [decision("crit-1"), decision("crit-2", %{evidence_ids: evidence_ids})],
          {:invalid_response, :invalid_evidence_ids}
        )
      end
    end

    test "rejects a non-binary rationale" do
      assert_response_error(
        [decision("crit-1"), decision("crit-2", %{rationale: %{text: "nested"}})],
        {:invalid_response, :invalid_rationale}
      )
    end

    test "does not leak a disallowed classification in the error" do
      leaked = "LEAKED_SENSITIVE_STUDENT_PROSE_CLASSIFICATION"
      reply = reply_with([decision("crit-1", %{classification: leaked})])

      assert {:error, error} = decide(request([question("crit-1")]), reply)
      refute inspect(error) =~ leaked
    end
  end

  # ============================================================================
  # Response validation: malformed output
  # ============================================================================

  describe "decide_rubric_batch/2 malformed output" do
    defp assert_malformed(reply, reason) do
      error = {:malformed_output, reason}

      assert {:error, ^error} = decide(request([question("crit-1")]), reply)
      assert JevDecision.technical_failure?(error)
    end

    test "rejects a response that is not a map" do
      assert_malformed({:ok, [decision("crit-1")]}, :expected_map)
      assert_malformed({:ok, 42}, :expected_map)
    end

    test "rejects a reply that is not an ok/error tuple" do
      assert_malformed(:ok, :expected_map)
    end

    test "rejects a missing or non-list decisions field" do
      assert_malformed({:ok, %{}}, :expected_decisions_list)
      assert_malformed({:ok, %{decisions: decision("crit-1")}}, :expected_decisions_list)
    end

    test "rejects a decision that is not a map" do
      assert_malformed(reply_with(["crit-1"]), :expected_decision_map)
    end

    test "rejects action decisions that are not a list of maps" do
      request = request([actions_question()])

      assert {:error, {:malformed_output, :expected_actions_list}} =
               decide(request, reply_with([decision("crit-1", %{actions: "act-a"})]))

      assert {:error, {:malformed_output, :expected_action_map}} =
               decide(request, reply_with([decision("crit-1", %{actions: ["act-a", "act-b"]})]))
    end
  end

  # ============================================================================
  # Action decisions
  # ============================================================================

  describe "decide_rubric_batch/2 action decisions" do
    defp decide_actions(actions) do
      decide(request([actions_question()]), reply_with([decision("crit-1", %{actions: actions})]))
    end

    test "returns one normalized action decision per authored action, in authored order" do
      actions = [
        %{"id" => "act-b", "classification" => "not_performed"},
        action_decision("act-a", %{evidence_ids: ["turn-1", "turn-404"]})
      ]

      assert {:ok, [decision]} = decide_actions(actions)

      assert decision.actions == [
               %{id: "act-a", classification: "performed", evidence_ids: ["turn-1", "turn-404"]},
               %{id: "act-b", classification: "not_performed", evidence_ids: []}
             ]
    end

    test "accepts every closed action class" do
      for class <- ["performed", "not_performed", "uncertain"] do
        actions = [
          action_decision("act-a", %{classification: class}),
          action_decision("act-b", %{classification: class})
        ]

        assert {:ok, [%{actions: [%{classification: ^class}, %{classification: ^class}]}]} =
                 decide_actions(actions)
      end
    end

    test "rejects a missing action decision" do
      assert {:error, {:invalid_response, :missing_action_decision}} =
               decide_actions([action_decision("act-a")])

      assert {:error, {:invalid_response, :missing_action_decision}} =
               decide(request([actions_question()]), reply_with([decision("crit-1")]))
    end

    test "rejects a duplicated action ID" do
      assert {:error, {:invalid_response, :duplicate_action_id}} =
               decide_actions([
                 action_decision("act-a"),
                 action_decision("act-b"),
                 action_decision("act-a")
               ])
    end

    test "rejects an unknown action ID" do
      assert {:error, {:invalid_response, :unknown_action_id}} =
               decide_actions([
                 action_decision("act-a"),
                 action_decision("act-b"),
                 action_decision("act-z")
               ])
    end

    test "rejects a missing or non-binary action ID" do
      assert {:error, {:invalid_response, :invalid_action_id}} =
               decide_actions([action_decision("act-a"), %{classification: "performed"}])
    end

    test "rejects an action class outside the closed set" do
      for class <- ["adequado", nil, :performed] do
        assert {:error, {:invalid_response, :disallowed_action_classification}} =
                 decide_actions([
                   action_decision("act-a"),
                   action_decision("act-b", %{classification: class})
                 ])
      end
    end

    test "rejects action evidence IDs that are not a list of binaries" do
      assert {:error, {:invalid_response, :invalid_action_evidence_ids}} =
               decide_actions([
                 action_decision("act-a"),
                 action_decision("act-b", %{evidence_ids: "turn-1"})
               ])
    end

    test "rejects action decisions for a question that authored none" do
      reply = reply_with([decision("crit-1", %{actions: [action_decision("act-a")]})])

      assert {:error, {:invalid_response, :unexpected_action_decisions}} =
               decide(request([question("crit-1")]), reply)
    end

    test "accepts an empty action list for a question that authored none" do
      reply = reply_with([decision("crit-1", %{actions: []})])

      assert {:ok, [%{actions: []}]} = decide(request([question("crit-1")]), reply)
    end
  end

  # ============================================================================
  # Answer enumeration
  # ============================================================================

  describe "decide_rubric_batch/2 answer enumeration" do
    defp enumerating_question, do: Map.put(actions_question(), :enumerate_answers, true)

    defp answer_entry(evidence_id, action_id) do
      %{evidence_id: evidence_id, action_id: action_id}
    end

    defp performed_actions, do: [action_decision("act-a"), action_decision("act-b")]

    defp decide_answers(answers) do
      decide(
        request([enumerating_question()]),
        reply_with([decision("crit-1", %{actions: performed_actions(), answers: answers})])
      )
    end

    test "carries the enumeration flag only on the questions that request it" do
      questions = [
        enumerating_question(),
        question("crit-2", %{"enumerate_answers" => true}),
        question("crit-3", %{enumerate_answers: false}),
        question("crit-4")
      ]

      reply = fn request ->
        decisions =
          Enum.map(request.questions, fn question ->
            decision(question.criterion.id, %{
              actions: Enum.map(question.actions, &action_decision(&1.id)),
              answers: if(question[:enumerate_answers], do: [])
            })
          end)

        reply_with(decisions)
      end

      assert {:ok, [first, second, third, fourth]} = decide(request(questions), reply)
      assert_received {:batch_request, sent}

      assert Enum.map(sent.questions, &Map.get(&1, :enumerate_answers, :absent)) ==
               [true, true, :absent, :absent]

      assert first.answers == []
      assert second.answers == []
      refute Map.has_key?(third, :answers)
      refute Map.has_key?(fourth, :answers)
    end

    test "rejects an enumeration flag that is not a boolean" do
      assert_invalid_request(
        request([question("crit-1", %{enumerate_answers: "yes"})]),
        :invalid_enumerate_answers
      )
    end

    test "returns the normalized answers in the order the adapter listed them" do
      answers = [
        answer_entry("turn-1", "act-b"),
        %{"evidence_id" => "turn-1"},
        %{"evidence_id" => "impresso-req-1", "action_id" => "act-a"},
        answer_entry("turn-404", nil)
      ]

      assert {:ok, [decision]} = decide_answers(answers)

      assert decision.answers == [
               %{evidence_id: "turn-1", action_id: "act-b"},
               %{evidence_id: "turn-1", action_id: nil},
               %{evidence_id: "impresso-req-1", action_id: "act-a"},
               %{evidence_id: "turn-404", action_id: nil}
             ]
    end

    test "rejects a missing answers list when it was requested" do
      error = {:invalid_response, :missing_answers}

      assert {:error, ^error} =
               decide(
                 request([enumerating_question()]),
                 reply_with([decision("crit-1", %{actions: performed_actions()})])
               )

      assert JevDecision.technical_failure?(error)
    end

    test "an adapter that does not enumerate fails the batch" do
      assert {:error, {:invalid_response, :missing_answers}} =
               decide(
                 request([question("crit-1"), enumerating_question() |> put_id("crit-2")]),
                 nil
               )
    end

    test "rejects answers that are not a list of maps" do
      for answers <- ["turn-1", %{evidence_id: "turn-1"}] do
        assert {:error, {:malformed_output, :expected_answers_list}} = decide_answers(answers)
      end

      assert {:error, {:malformed_output, :expected_answer_map}} = decide_answers(["turn-1"])
    end

    test "rejects an answer without a binary evidence ID" do
      for entry <- [%{action_id: "act-a"}, answer_entry(1, "act-a"), answer_entry(nil, nil)] do
        assert {:error, {:invalid_response, :invalid_answer_evidence_id}} =
                 decide_answers([entry])
      end
    end

    test "rejects an answer whose action ID is unknown or not a binary" do
      assert {:error, {:invalid_response, :unknown_answer_action_id}} =
               decide_answers([answer_entry("turn-1", "act-a"), answer_entry("turn-1", "act-z")])

      assert {:error, {:invalid_response, :invalid_answer_action_id}} =
               decide_answers([answer_entry("turn-1", :"act-a")])
    end

    test "rejects an action ID that appears in two answers" do
      error = {:invalid_response, :duplicate_answer_action_id}

      assert {:error, ^error} =
               decide_answers([
                 answer_entry("turn-1", "act-a"),
                 answer_entry("turn-1", nil),
                 answer_entry("impresso-req-1", "act-a")
               ])

      assert JevDecision.technical_failure?(error)
    end

    test "accepts several answers that match no authored action" do
      answers = [answer_entry("turn-1", nil), answer_entry("turn-1", nil)]

      assert {:ok, [%{answers: ^answers}]} = decide_answers(answers)
    end

    test "rejects answers for a question that did not request them" do
      for answers <- [[answer_entry("turn-1", nil)], "turn-1"] do
        reply = reply_with([decision("crit-1", %{answers: answers})])

        assert {:error, {:invalid_response, :unexpected_answers}} =
                 decide(request([question("crit-1")]), reply)
      end
    end

    test "accepts an empty answers list for a question that did not request them" do
      reply = reply_with([decision("crit-1", %{answers: []})])

      assert {:ok, [decision]} = decide(request([question("crit-1")]), reply)
      refute Map.has_key?(decision, :answers)
    end

    defp put_id(question, id), do: put_in(question, [:criterion, :id], id)
  end

  # ============================================================================
  # Technical failures
  # ============================================================================

  describe "decide_rubric_batch/2 technical failures" do
    defp assert_technical(reply, error, opts \\ []) do
      assert {:error, ^error} =
               decide(request([question("crit-1"), question("crit-2")]), reply, opts)

      assert JevDecision.technical_failure?(error)
    end

    test "one deadline covers the whole batch and expiry returns :timeout" do
      slow = fn _request ->
        Process.sleep(500)
        reply_with([decision("crit-1"), decision("crit-2")])
      end

      started = System.monotonic_time(:millisecond)
      assert_technical(slow, :timeout, deadline_ms: 30)
      assert System.monotonic_time(:millisecond) - started < 400

      assert_received {:batch_request, %{deadline_ms: 30}}
    end

    test "an already exhausted budget returns :timeout without calling the adapter" do
      assert {:error, :timeout} =
               decide(request([question("crit-1")]), nil, remaining_budget_ms: 0)

      refute_received {:batch_request, _}
    end

    test "an adapter-reported timeout is a typed technical failure" do
      assert_technical({:error, :timeout}, :timeout)
    end

    test "upstream 5xx is normalized" do
      assert_technical({:error, {:upstream_error, 503}}, {:upstream_5xx, 503})
      assert_technical({:error, {:upstream_5xx, 500}}, {:upstream_5xx, 500})
    end

    test "a raw upstream body is sanitized" do
      assert_technical({:error, {:upstream_error, "LEAKED_UPSTREAM_BODY"}}, :upstream_error)
    end

    test "a raised exception is contained" do
      crash = fn _request -> raise "Boom with LEAKED_LEARNER_TEXT" end

      assert_technical(crash, {:technical_failure, :adapter_crashed})
    end

    test "a throw is contained" do
      assert_technical(fn _request -> throw(:boom) end, {:technical_failure, :adapter_threw})
    end

    test "an adapter-reported malformed output is normalized" do
      assert_technical({:error, {:malformed_output, "raw body"}}, :malformed_output)
    end

    test "an unknown adapter error is sanitized" do
      assert_technical({:error, %{body: "LEAKED"}}, {:technical_failure, :adapter_error})
    end

    test "the disabled adapter returns its typed failure" do
      assert {:error, {:adapter_disabled, message} = error} =
               JevDecision.decide_rubric_batch(request([question("crit-1")]),
                 adapter: DisabledAdapter
               )

      assert message =~ "disabled"
      assert JevDecision.technical_failure?(error)
    end

    test "the default adapter is the disabled adapter" do
      assert {:error, {:adapter_disabled, _message}} =
               JevDecision.decide_rubric_batch(request([question("crit-1")]))
    end

    test "an adapter without the batch callback fails instead of falling back to serial calls" do
      error = {:technical_failure, :rubric_batch_unsupported}

      assert {:error, ^error} =
               JevDecision.decide_rubric_batch(
                 request([question("crit-1"), question("crit-2")]),
                 adapter: SingleOnlyDouble
               )

      refute_received :serial_fallback_used
      assert JevDecision.technical_failure?(error)
    end

    test "invalid requests are classified as technical failures" do
      assert {:error, error} = decide(request([]), nil)
      assert JevDecision.technical_failure?(error)
    end
  end

  describe "total context size cap" do
    defp pool_characters, do: pool() |> Enum.map(&String.length(&1.text)) |> Enum.sum()

    test "an evidence pool over the cap fails closed before the adapter is called" do
      assert {:error, {:invalid_request, :context_limit_exceeded} = error} =
               decide(request([question("crit-1")]), nil,
                 max_context_characters: pool_characters() - 1
               )

      refute_received {:batch_request, _}
      assert JevDecision.technical_failure?(error)
    end

    test "an evidence pool over the default cap fails closed" do
      oversized = [%{id: "turn-1", role: "student", text: String.duplicate("a", 24_001)}]

      assert {:error, {:invalid_request, :context_limit_exceeded}} =
               decide(request([question("crit-1")], %{evidence_pool: oversized}), nil)

      refute_received {:batch_request, _}
    end

    test "an evidence pool at the cap reaches the adapter unchanged" do
      assert {:ok, [_decision]} =
               decide(request([question("crit-1")]), nil,
                 max_context_characters: pool_characters()
               )

      assert_received {:batch_request, received}
      assert received.evidence_pool == pool()
    end
  end
end
