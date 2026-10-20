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
      assert request.response_rules == ["Responda apenas ao que foi perguntado."]
      assert is_integer(request.deadline_ms) and request.deadline_ms > 0
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
    test "never delivers a fact a clear-no asked label says was not requested" do
      decision =
        @decision
        |> Map.put(:not_asked_fact_ids, ["fact-key"])
        |> Map.update!(
          :undecided_labels,
          &[%{question: "fact_stated", fact_id: "fact-key", score: 0.4} | &1]
        )

      assert adjudicate(answer("deliver"), decision: decision) == {:regenerate, ["fact-key"]}

      assert adjudicate(answer("regenerate", ["pergunta-explicita-02"]), decision: decision) ==
               {:regenerate, ["pergunta-explicita-02", "fact-key"]}

      assert_received {:adjudication_request, %{not_asked_fact_ids: ["fact-key"]}}
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
