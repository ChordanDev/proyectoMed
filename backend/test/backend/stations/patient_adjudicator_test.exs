defmodule Backend.Stations.PatientAdjudicatorTest do
  # async: false: one test changes the logger level.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Backend.Stations.JevDecision
  alias Backend.Stations.PatientAdjudicator

  # Replies with `opts[:reply]` (a term or a zero-arity function) after
  # `opts[:sleep_ms]`, and sends the request to `opts[:test_pid]`.
  defmodule StubAdapter do
    @behaviour Backend.Stations.PatientAdjudicator

    @impl true
    def adjudicate(request, opts) do
      if pid = opts[:test_pid], do: send(pid, {:adjudication_request, request})
      if ms = opts[:sleep_ms], do: Process.sleep(ms)

      case opts[:reply] do
        fun when is_function(fun, 0) -> fun.()
        reply -> reply
      end
    end
  end

  # The 2026-10-20 rehearsal case (issue #290): "Toma algum remédio?" against
  # three narrow negative medication facts, plus one key fact.
  @package %{
    "station_id" => "acute-appendicitis",
    "version" => "1.0.0",
    "language" => "pt-BR",
    "revealable_facts" => [
      %{
        "id" => "hda-06-antitermico",
        "content" => "Não tomou antitérmico.",
        "disclosure_condition" => "on_request"
      },
      %{
        "id" => "pergunta-explicita-02",
        "content" => "Não usou antibióticos nem anticoagulantes recentemente.",
        "disclosure_condition" => "on_request"
      },
      %{
        "id" => "pergunta-explicita-02-anti-inflamatorios",
        "content" => "Não usou anti-inflamatórios recentemente.",
        "disclosure_condition" => "on_request"
      },
      %{
        "id" => "fact-key",
        "content" => "Tem alergia a dipirona.",
        "disclosure_condition" => "on_request"
      },
      %{"id" => "fact-name", "content" => "Chama-se Ana.", "disclosure_condition" => "on_request"}
    ],
    "response_rules" => [
      %{"id" => "rule-1", "instruction" => "Responda apenas ao que foi perguntado."}
    ]
  }

  @candidate "Não, não tomei nenhum remédio, nem antitérmico, nem antibiótico."

  @conversation [
    %{role: :learner, text: "Qual é seu nome?"},
    %{role: :patient, text: "Ana."},
    %{role: :learner, text: "Toma algum remédio?"}
  ]

  @decision %{
    status: :low_confidence,
    used_fact_ids: [],
    undecided_labels: [
      %{question: "fact_asked", fact_id: "hda-06-antitermico", score: 0.45},
      %{question: "fact_stated", fact_id: "hda-06-antitermico", score: 0.39},
      %{question: "fact_stated", fact_id: "pergunta-explicita-02", score: 0.25},
      %{question: "fact_stated", fact_id: "pergunta-explicita-02-anti-inflamatorios", score: 0.3}
    ]
  }

  defp adjudicate(reply, opts \\ []) do
    {decision, opts} = Keyword.pop(opts, :decision, @decision)
    {candidate, opts} = Keyword.pop(opts, :candidate, @candidate)

    adapter_opts =
      [reply: reply, test_pid: self()] ++ Keyword.take(opts, [:sleep_ms])

    PatientAdjudicator.adjudicate(
      decision,
      candidate,
      @package,
      @conversation,
      Keyword.merge(
        [
          adjudicator_adapter: StubAdapter,
          adjudicator_opts: adapter_opts,
          deadline_at_monotonic_ms: JevDecision.monotonic_deadline_at(3_000),
          disclosed_fact_ids: ["fact-name"]
        ],
        Keyword.drop(opts, [:sleep_ms])
      )
    )
  end

  defp answer(decision, ids \\ []),
    do: {:ok, %{"decision" => decision, "withheld_fact_ids" => ids}}

  describe "decisions" do
    test "deliver delivers" do
      assert adjudicate(answer("deliver")) == :deliver
    end

    test "regenerate names the authored facts to withhold" do
      assert adjudicate(answer("regenerate", ["pergunta-explicita-02"])) ==
               {:regenerate, ["pergunta-explicita-02"]}
    end

    test "refuse refuses" do
      assert adjudicate(answer("refuse")) == {:refuse, :adjudicator}
    end

    test "the disabled adapter refuses without a decision" do
      assert PatientAdjudicator.adjudicate(@decision, @candidate, @package, @conversation,
               adjudicator_adapter: PatientAdjudicator.DisabledAdapter,
               deadline_at_monotonic_ms: JevDecision.monotonic_deadline_at(3_000)
             ) == {:refuse, :disabled}
    end
  end

  describe "the request" do
    test "carries the candidate, the conversation, the facts involved and Jev's scores" do
      adjudicate(answer("deliver"))
      assert_received {:adjudication_request, request}

      assert request.candidate_reply == @candidate
      assert request.latest_learner_message == "Toma algum remédio?"

      assert request.conversation == [
               %{speaker: "learner", text: "Qual é seu nome?"},
               %{speaker: "patient", text: "Ana."},
               %{speaker: "learner", text: "Toma algum remédio?"}
             ]

      assert Enum.map(request.facts, & &1.id) == [
               "hda-06-antitermico",
               "pergunta-explicita-02",
               "pergunta-explicita-02-anti-inflamatorios"
             ]

      assert hd(request.facts).content == "Não tomou antitérmico."
      assert request.disclosed_facts == [%{id: "fact-name", content: "Chama-se Ana."}]
      assert request.undecided_labels == @decision.undecided_labels
      assert request.not_asked_fact_ids == []
      assert request.asked_fact_ids == []
      assert request.fact_scores == []
      assert request.response_rules == ["Responda apenas ao que foi perguntado."]
      assert is_integer(request.deadline_ms) and request.deadline_ms > 0
    end

    test "marks the facts that require an explicit question" do
      adjudicate(answer("deliver"))
      assert_received {:adjudication_request, request}

      assert Map.new(request.facts, &{&1.id, &1.requires_explicit_question}) == %{
               "hda-06-antitermico" => false,
               "pergunta-explicita-02" => true,
               "pergunta-explicita-02-anti-inflamatorios" => true
             }
    end

    test "is not sent without undecided labels" do
      for decision <- [
            Map.delete(@decision, :undecided_labels),
            %{@decision | undecided_labels: []}
          ] do
        assert adjudicate(answer("deliver"), decision: decision) == {:refuse, :no_evidence}
        refute_received {:adjudication_request, _}
      end
    end

    test "is not sent when the turn has no budget left" do
      result =
        adjudicate(answer("deliver"),
          deadline_at_monotonic_ms: JevDecision.monotonic_now_ms() + 50
        )

      assert result == {:refuse, :no_budget}
      refute_received {:adjudication_request, _}
    end

    test "its deadline is the configured one, capped by the turn budget" do
      adjudicate(answer("deliver"), adjudicator_deadline_ms: 400)
      assert_received {:adjudication_request, %{deadline_ms: ms}}
      assert ms <= 400

      adjudicate(answer("deliver"),
        adjudicator_deadline_ms: 5_000,
        deadline_at_monotonic_ms: JevDecision.monotonic_deadline_at(800)
      )

      assert_received {:adjudication_request, %{deadline_ms: capped}}
      assert capped < 800
    end
  end

  describe "regeneration_extension_ms/1" do
    test "defaults to 1500 ms and reads options, then configuration" do
      previous = Application.fetch_env(:backend, :patient_adjudicator_regeneration_extension_ms)
      Application.delete_env(:backend, :patient_adjudicator_regeneration_extension_ms)

      on_exit(fn ->
        case previous do
          {:ok, value} ->
            Application.put_env(:backend, :patient_adjudicator_regeneration_extension_ms, value)

          :error ->
            Application.delete_env(:backend, :patient_adjudicator_regeneration_extension_ms)
        end
      end)

      assert PatientAdjudicator.regeneration_extension_ms() == 1_500
      assert PatientAdjudicator.regeneration_extension_ms(adjudicator_extension_ms: 0) == 0

      Application.put_env(:backend, :patient_adjudicator_regeneration_extension_ms, 900)
      assert PatientAdjudicator.regeneration_extension_ms() == 900
    end
  end

  describe "invalid output refuses" do
    test "anything but the schema is malformed" do
      invalid = [
        answer("maybe"),
        answer("regenerate", ["nonexistent-fact"]),
        answer("regenerate", "pergunta-explicita-02"),
        answer("regenerate", [1]),
        {:ok, %{"decision" => "deliver"}},
        {:ok, %{"decision" => "deliver", "withheld_fact_ids" => [], "reason" => "ok"}},
        {:ok, "deliver"},
        :deliver,
        # A deliver that names facts to withhold contradicts itself.
        answer("deliver", ["pergunta-explicita-02"])
      ]

      for reply <- invalid do
        assert adjudicate(reply) == {:refuse, :malformed_output}, inspect(reply)
      end
    end

    test "an error or a crash refuses" do
      assert adjudicate({:error, :upstream_error}) == {:refuse, :error}
      assert adjudicate(fn -> raise "boom" end) == {:refuse, :error}
    end

    test "a timeout refuses inside the deadline" do
      started = System.monotonic_time(:millisecond)

      assert adjudicate(answer("deliver"), sleep_ms: 1_000, adjudicator_deadline_ms: 200) ==
               {:refuse, :timeout}

      assert System.monotonic_time(:millisecond) - started < 800
    end
  end

  describe "hard limits" do
    test "never delivers a fact Jev found clearly stated and clearly not requested" do
      # stated 0.9 (clear yes) and asked 0.19 (clear no): the limit still applies.
      decision =
        @decision
        |> Map.put(:not_asked_fact_ids, ["fact-key"])
        |> Map.put(:stated_not_asked_fact_ids, ["fact-key"])
        |> Map.put(:fact_scores, [%{fact_id: "fact-key", stated: 0.9, asked: 0.19}])

      assert adjudicate(answer("deliver"), decision: decision) == {:regenerate, ["fact-key"]}

      assert adjudicate(answer("regenerate", ["pergunta-explicita-02"]), decision: decision) ==
               {:regenerate, ["pergunta-explicita-02", "fact-key"]}

      assert_received {:adjudication_request, %{not_asked_fact_ids: ["fact-key"]}}
    end

    test "an undecided stated fact that was clearly not requested is the adjudicator's call" do
      # The live turn-9 case: stated 0.31 (undecided), asked 0.19 (clear no).
      decision =
        @decision
        |> Map.put(:not_asked_fact_ids, ["pergunta-explicita-02"])
        |> Map.put(:fact_scores, [
          %{fact_id: "pergunta-explicita-02", stated: 0.31, asked: 0.19}
        ])

      assert adjudicate(answer("deliver"), decision: decision) == :deliver

      assert adjudicate(answer("regenerate", ["pergunta-explicita-02"]), decision: decision) ==
               {:regenerate, ["pergunta-explicita-02"]}

      assert adjudicate(answer("refuse"), decision: decision) == {:refuse, :adjudicator}

      assert_received {:adjudication_request,
                       %{
                         fact_scores: [
                           %{fact_id: "pergunta-explicita-02", stated: 0.31, asked: 0.19}
                         ]
                       }}
    end

    test "never withholds a fact a clear-yes asked label says was requested" do
      decision = Map.put(@decision, :asked_fact_ids, ["hda-06-antitermico"])

      assert adjudicate(
               answer("regenerate", ["hda-06-antitermico", "pergunta-explicita-02"]),
               decision: decision
             ) == {:regenerate, ["pergunta-explicita-02"]}

      assert_received {:adjudication_request, %{asked_fact_ids: ["hda-06-antitermico"]}}
    end

    test "never delivers a candidate the deterministic checks reject" do
      assert adjudicate(answer("deliver"), candidate: "Sou uma inteligência artificial.") ==
               {:refuse, :denied}
    end
  end

  describe "logging" do
    setup do
      level = Logger.level()
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: level) end)
    end

    test "logs the outcome and latency only, never text or fact ids" do
      log = capture_log(fn -> adjudicate(answer("regenerate", ["pergunta-explicita-02"])) end)

      assert log =~ ~r/\[PatientAdjudicator\] adjudication outcome=regenerate latency_ms=\d+/
      refute log =~ "remédio"
      refute log =~ "pergunta-explicita-02"

      log = capture_log(fn -> adjudicate({:error, :upstream_error}) end)
      assert log =~ ~r/outcome=refuse latency_ms=\d+ reason=error/
    end
  end
end
