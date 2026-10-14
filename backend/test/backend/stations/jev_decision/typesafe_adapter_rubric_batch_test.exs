defmodule Backend.Stations.JevDecision.TypesafeAdapterRubricBatchTest do
  # async: false because the configuration tests change the application environment.
  use ExUnit.Case, async: false

  alias Backend.Stations.JevDecision
  alias Backend.Stations.JevDecision.TypesafeAdapter

  @patient_text "A dor começou ontem à noite, perto do umbigo."
  @asks_onset "Quando começou a dor?"
  @asks_vomiting "O senhor vomitou?"
  @greets "Bom dia, sou o estudante."

  @onset_action %{id: "act-onset", description: "Pergunta quando a dor começou."}
  @vomit_action %{id: "act-vomit", description: "Pergunta sobre vômitos."}
  @fever_action %{id: "act-fever", description: "Pergunta sobre febre."}

  # The adapter request the seam hands over: minimized, with the deadline attached.
  defp request(overrides \\ %{}) do
    Map.merge(
      %{
        questions: [
          %{
            criterion: %{id: "item-01", description: "Caracteriza a dor."},
            allowed_classes: ["adequado", "inadequado", "uncertain"],
            actions: [@onset_action, @fever_action]
          },
          %{
            criterion: %{id: "item-02", description: "Sintomas associados."},
            allowed_classes: ["adequado", "uncertain"],
            actions: [@vomit_action]
          }
        ],
        evidence_pool: [
          %{id: "turn-1", role: "student", text: @greets},
          %{id: "turn-2", role: "student", text: @asks_onset},
          %{id: "turn-3", role: "patient", text: @patient_text},
          %{id: "turn-4", role: "learner", text: @asks_vomiting}
        ],
        deadline_ms: 3_000,
        deadline_at_monotonic_ms: System.monotonic_time(:millisecond) + 3_000
      },
      overrides
    )
  end

  # Answers every question with `answer.(action_description, item_text)`, reading
  # the item and the action from the request itself, and reports each request.
  defp stub_answers(name, answer) do
    test_pid = self()

    Req.Test.stub(name, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(raw)
      send(test_pid, {:typesafe_request, payload})

      Req.Test.json(conn, %{"answers" => answers_for(payload, answer)})
    end)

    [api_key: "ts-test-key", plug: {Req.Test, name}]
  end

  defp answers_for(payload, answer) do
    texts = Map.new(payload["state"]["learner_items"], &{&1["item"], &1["text"]})

    Map.new(payload["questions"], fn {id, question} ->
      %{"item" => item, "action" => action} = question["instructions"]
      {id, %{"type" => "noul", "noul" => answer.(action, Map.fetch!(texts, item))}}
    end)
  end

  # Yes for (onset action, onset question) and (vomit action, vomit question).
  defp matching(action, text) do
    cond do
      action == @onset_action.description and text == @asks_onset -> 0.97
      action == @vomit_action.description and text == @asks_vomiting -> 0.91
      true -> 0.03
    end
  end

  defp never_called(name) do
    Req.Test.stub(name, fn _conn -> flunk("provider must not be called") end)
    [api_key: "ts-test-key", plug: {Req.Test, name}]
  end

  defp stub_response(name, fun) do
    Req.Test.stub(name, fun)
    [api_key: "ts-test-key", plug: {Req.Test, name}]
  end

  defp actions(decision), do: Map.new(decision.actions, &{&1.id, &1})

  describe "decide_rubric_batch/2 mapping" do
    test "classifies performed actions with their citations and the rest as not performed" do
      assert {:ok, %{decisions: [first, second]}} =
               TypesafeAdapter.decide_rubric_batch(request(), stub_answers(MapStub, &matching/2))

      assert first.criterion_id == "item-01"
      assert second.criterion_id == "item-02"

      assert actions(first)["act-onset"] == %{
               id: "act-onset",
               classification: "performed",
               evidence_ids: ["turn-2"]
             }

      assert actions(first)["act-fever"] == %{
               id: "act-fever",
               classification: "not_performed",
               evidence_ids: []
             }

      assert actions(second)["act-vomit"] == %{
               id: "act-vomit",
               classification: "performed",
               evidence_ids: ["turn-4"]
             }

      assert Enum.map(first.actions, & &1.id) == ["act-onset", "act-fever"]
    end

    test "cites every learner item answered yes, in pool order" do
      answer = fn action, text ->
        if action == @onset_action.description and text in [@asks_onset, @asks_vomiting],
          do: 0.85,
          else: 0.0
      end

      assert {:ok, %{decisions: [first, _second]}} =
               TypesafeAdapter.decide_rubric_batch(request(), stub_answers(CiteAllStub, answer))

      assert actions(first)["act-onset"].evidence_ids == ["turn-2", "turn-4"]
    end

    test "an action with an undecided item and no yes is uncertain, without citations" do
      answer = fn action, text ->
        if action == @fever_action.description and text == @asks_onset, do: 0.5, else: 0.1
      end

      assert {:ok, %{decisions: [first, _second]}} =
               TypesafeAdapter.decide_rubric_batch(request(), stub_answers(UndecidedStub, answer))

      assert actions(first)["act-fever"] == %{
               id: "act-fever",
               classification: "uncertain",
               evidence_ids: []
             }
    end

    test "thresholds are inclusive: 0.8 is a yes and 0.2 is a no" do
      answer = fn action, text ->
        cond do
          action == @onset_action.description and text == @asks_onset -> 0.8
          true -> 0.2
        end
      end

      assert {:ok, %{decisions: [first, second]}} =
               TypesafeAdapter.decide_rubric_batch(request(), stub_answers(EdgeStub, answer))

      assert actions(first)["act-onset"].classification == "performed"
      assert actions(first)["act-fever"].classification == "not_performed"
      assert actions(second)["act-vomit"].classification == "not_performed"
    end

    test "the criterion is always uncertain, without criterion evidence, so authored rules decide" do
      answer = fn _action, _text -> 0.99 end

      assert {:ok, %{decisions: decisions}} =
               TypesafeAdapter.decide_rubric_batch(request(), stub_answers(CriterionStub, answer))

      for decision <- decisions do
        assert decision.classification == "uncertain"
        assert decision.evidence_ids == []
        refute Map.has_key?(decision, :answers)
      end
    end

    test "with no citable learner item every action is not performed and nothing is sent" do
      pool = [%{id: "turn-1", role: "patient", text: @patient_text}]

      assert {:ok, %{decisions: decisions}} =
               TypesafeAdapter.decide_rubric_batch(
                 request(%{evidence_pool: pool}),
                 never_called(NoItemsStub)
               )

      for decision <- decisions, action <- decision.actions do
        assert action.classification == "not_performed"
        assert action.evidence_ids == []
      end
    end

    test "questions without actions need no call" do
      questions = [
        %{
          criterion: %{id: "item-09", description: "Global."},
          allowed_classes: ["adequado", "uncertain"],
          actions: []
        }
      ]

      assert TypesafeAdapter.decide_rubric_batch(
               request(%{questions: questions}),
               never_called(NoActionsStub)
             ) ==
               {:ok,
                %{
                  decisions: [
                    %{
                      criterion_id: "item-09",
                      classification: "uncertain",
                      evidence_ids: [],
                      rationale: nil,
                      actions: []
                    }
                  ]
                }}
    end

    test "an enumeration request fails closed before any call" do
      [first | rest] = request().questions

      assert TypesafeAdapter.decide_rubric_batch(
               request(%{questions: [Map.put(first, :enumerate_answers, true) | rest]}),
               never_called(EnumerationStub)
             ) == {:error, {:technical_failure, :rubric_enumeration_unsupported}}
    end
  end

  describe "decide_rubric_batch/2 request" do
    test "sends one request whose state holds only the citable learner items" do
      opts = stub_answers(StateStub, &matching/2)

      assert {:ok, _} = TypesafeAdapter.decide_rubric_batch(request(), opts)

      assert_receive {:typesafe_request, payload}
      refute_receive {:typesafe_request, _}

      assert payload["model"] == "jev-1.13.0"

      assert payload["state"] == %{
               "learner_items" => [
                 %{"item" => 1, "text" => @greets},
                 %{"item" => 2, "text" => @asks_onset},
                 %{"item" => 3, "text" => @asks_vomiting}
               ]
             }

      # One noul question per (action, learner item): 3 actions x 3 items.
      assert map_size(payload["questions"]) == 9

      for {id, question} <- payload["questions"] do
        assert question["type"] == "noul"
        refute id =~ "turn-"
        refute inspect(question) =~ @patient_text
      end
    end

    test "patient turns are never offered and never cited, even when every answer is yes" do
      opts = stub_answers(PatientStub, fn _action, _text -> 1.0 end)

      assert {:ok, %{decisions: decisions}} = TypesafeAdapter.decide_rubric_batch(request(), opts)

      assert_receive {:typesafe_request, payload}
      refute inspect(payload) =~ @patient_text

      for decision <- decisions, action <- decision.actions do
        assert action.evidence_ids == ["turn-1", "turn-2", "turn-4"]
      end
    end

    test "splits the actions into groups above the size budget; every group keeps the state" do
      long = String.duplicate("Pergunta detalhada sobre o sintoma. ", 60)

      questions = [
        %{
          criterion: %{id: "item-01", description: "Caracteriza a dor."},
          allowed_classes: ["adequado", "uncertain"],
          actions: [
            %{id: "act-a", description: "A " <> long},
            %{id: "act-b", description: "B " <> long}
          ]
        },
        %{
          criterion: %{id: "item-02", description: "Sintomas associados."},
          allowed_classes: ["adequado", "uncertain"],
          actions: [%{id: "act-c", description: "C " <> long}]
        }
      ]

      pool = [%{id: "turn-1", role: "student", text: @asks_onset}]

      answer = fn action, _text -> if String.starts_with?(action, "B "), do: 0.9, else: 0.1 end
      opts = stub_answers(SplitStub, answer) ++ [max_request_tokens: 1_000]

      assert {:ok, %{decisions: [first, second]}} =
               TypesafeAdapter.decide_rubric_batch(
                 request(%{questions: questions, evidence_pool: pool}),
                 opts
               )

      payloads = receive_all()
      assert length(payloads) == 3

      for payload <- payloads do
        assert payload["state"] == %{"learner_items" => [%{"item" => 1, "text" => @asks_onset}]}
        assert map_size(payload["questions"]) == 1
      end

      ids = Enum.flat_map(payloads, &Map.keys(&1["questions"]))
      assert length(Enum.uniq(ids)) == 3

      assert actions(first)["act-a"].classification == "not_performed"
      assert actions(first)["act-b"].evidence_ids == ["turn-1"]
      assert actions(second)["act-c"].classification == "not_performed"
    end

    test "a single action above the size budget fails closed before any call" do
      assert TypesafeAdapter.decide_rubric_batch(
               request(),
               never_called(TooLargeStub) ++ [max_request_tokens: 10]
             ) == {:error, {:technical_failure, :rubric_request_too_large}}
    end

    test "an invalid size budget fails closed" do
      for bad <- [0, -1, 1.5, "64000"] do
        assert TypesafeAdapter.decide_rubric_batch(
                 request(),
                 never_called(BadBudgetStub) ++ [max_request_tokens: bad]
               ) == {:error, {:technical_failure, :invalid_max_request_tokens}}
      end
    end

    test "configuration problems fail closed before any call" do
      base = never_called(ConfigStub)

      assert TypesafeAdapter.decide_rubric_batch(request(), Keyword.put(base, :api_key, "")) ==
               {:error, {:technical_failure, :missing_credentials}}

      assert TypesafeAdapter.decide_rubric_batch(request(), base ++ [base_url: "http://x.test"]) ==
               {:error, {:technical_failure, :invalid_base_url}}

      assert TypesafeAdapter.decide_rubric_batch(
               request(),
               base ++ [no_threshold: 0.6, yes_threshold: 0.9]
             ) == {:error, {:technical_failure, :invalid_thresholds}}
    end
  end

  describe "decide_rubric_batch/2 failures" do
    test "returns :timeout without calling the provider when no budget remains" do
      now = System.monotonic_time(:millisecond)

      assert TypesafeAdapter.decide_rubric_batch(
               request(%{deadline_at_monotonic_ms: now - 1}),
               never_called(ExhaustedStub)
             ) == {:error, :timeout}
    end

    test "a transport timeout fails the batch with :timeout" do
      opts =
        stub_response(TimeoutStub, fn conn -> Req.Test.transport_error(conn, :timeout) end)

      assert TypesafeAdapter.decide_rubric_batch(request(), opts) == {:error, :timeout}
    end

    test "a slow provider fails the batch with :timeout within the deadline" do
      opts =
        stub_response(SlowStub, fn conn ->
          Process.sleep(500)
          Req.Test.json(conn, %{})
        end)

      deadline = System.monotonic_time(:millisecond) + 300

      {elapsed_us, result} =
        :timer.tc(fn ->
          TypesafeAdapter.decide_rubric_batch(
            request(%{deadline_at_monotonic_ms: deadline}),
            opts
          )
        end)

      assert result == {:error, :timeout}
      assert elapsed_us < 450_000
    end

    test "any other transport error fails the batch with :network_error" do
      opts =
        stub_response(RefusedStub, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert TypesafeAdapter.decide_rubric_batch(request(), opts) == {:error, :network_error}
    end

    test "a non-200 status fails the batch, once, with no retry" do
      test_pid = self()

      opts =
        stub_response(Status500Stub, fn conn ->
          send(test_pid, :called)
          conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"error" => %{}})
        end)

      assert TypesafeAdapter.decide_rubric_batch(request(), opts) ==
               {:error, {:upstream_error, 500}}

      assert_receive :called
      refute_receive :called
    end

    test "a missing answer fails the batch" do
      opts =
        stub_response(MissingStub, fn conn ->
          {:ok, raw, conn} = Plug.Conn.read_body(conn)
          answers = answers_for(Jason.decode!(raw), &matching/2)
          Req.Test.json(conn, %{"answers" => Map.delete(answers, hd(Map.keys(answers)))})
        end)

      assert TypesafeAdapter.decide_rubric_batch(request(), opts) ==
               {:error, {:invalid_response, :missing_answer}}
    end

    test "an invalid probability fails the batch" do
      opts = stub_answers(OutOfRangeStub, fn _action, _text -> 1.5 end)

      assert TypesafeAdapter.decide_rubric_batch(request(), opts) ==
               {:error, {:invalid_response, :noul_out_of_range}}
    end

    test "one failing group fails the whole batch" do
      long = String.duplicate("Pergunta detalhada sobre o sintoma. ", 60)

      questions = [
        %{
          criterion: %{id: "item-01", description: "Caracteriza a dor."},
          allowed_classes: ["adequado", "uncertain"],
          actions: [
            %{id: "act-a", description: "A " <> long},
            %{id: "act-b", description: "B " <> long}
          ]
        }
      ]

      opts =
        stub_response(GroupFailStub, fn conn ->
          {:ok, raw, conn} = Plug.Conn.read_body(conn)
          payload = Jason.decode!(raw)
          [{_id, question}] = Map.to_list(payload["questions"])

          if String.starts_with?(question["instructions"]["action"], "B ") do
            conn |> Plug.Conn.put_status(503) |> Req.Test.json(%{})
          else
            Req.Test.json(conn, %{"answers" => answers_for(payload, fn _, _ -> 0.99 end)})
          end
        end) ++ [max_request_tokens: 1_000]

      assert TypesafeAdapter.decide_rubric_batch(
               request(%{
                 questions: questions,
                 evidence_pool: [%{id: "turn-1", role: "student", text: @asks_onset}]
               }),
               opts
             ) == {:error, {:upstream_error, 503}}
    end
  end

  describe "through the JevDecision seam" do
    test "returns validated decisions" do
      seam_request = %{
        questions: [
          %{
            criterion: %{id: "item-01", description: "Caracteriza a dor."},
            allowed_classes: ["adequado", "uncertain"],
            actions: [@onset_action]
          }
        ],
        evidence_pool: [
          %{id: "turn-1", role: "student", text: @asks_onset},
          %{id: "turn-2", role: "patient", text: @patient_text}
        ]
      }

      opts = [adapter: TypesafeAdapter] ++ stub_answers(SeamStub, &matching/2)

      assert JevDecision.decide_rubric_batch(seam_request, opts) ==
               {:ok,
                [
                  %{
                    criterion_id: "item-01",
                    classification: "uncertain",
                    evidence_ids: [],
                    rationale: nil,
                    actions: [
                      %{id: "act-onset", classification: "performed", evidence_ids: ["turn-1"]}
                    ]
                  }
                ]}
    end

    test "keeps the typed reason of an unsupported enumeration" do
      seam_request = %{
        questions: [
          %{
            criterion: %{id: "item-01", description: "Lista."},
            allowed_classes: ["adequado", "uncertain"],
            actions: [@onset_action],
            enumerate_answers: true
          }
        ],
        evidence_pool: []
      }

      opts = [adapter: TypesafeAdapter] ++ never_called(SeamEnumStub)

      assert JevDecision.decide_rubric_batch(seam_request, opts) ==
               {:error, {:technical_failure, :rubric_enumeration_unsupported}}
    end
  end

  defp receive_all(acc \\ []) do
    receive do
      {:typesafe_request, payload} -> receive_all([payload | acc])
    after
      100 -> Enum.reverse(acc)
    end
  end
end
