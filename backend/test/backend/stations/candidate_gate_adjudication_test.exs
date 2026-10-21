defmodule Backend.Stations.CandidateGateAdjudicationTest do
  # Issue #290: a low-confidence Jev verdict is adjudicated instead of refused.
  use ExUnit.Case, async: true

  alias Backend.Stations.CandidateGate

  @medication "Não, não tomo nenhum remédio, nem antitérmico."
  @key_fact "Não tomo remédio, mas tenho alergia a dipirona."
  @regen_verified "Não tomo nenhum remédio."
  @regen_undecided "Não, nada de remédio."

  # Jev double keyed by the candidate text.
  defmodule Jev do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(%{candidate_text: text}), do: {:ok, decision(text)}

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}

    defp decision("Não, não tomo nenhum remédio, nem antitérmico.") do
      %{
        status: :low_confidence,
        used_fact_ids: ["hda-06-antitermico"],
        undecided_labels: [
          %{question: "fact_asked", fact_id: "hda-06-antitermico", score: 0.45},
          %{question: "fact_stated", fact_id: "hda-06-antitermico", score: 0.39},
          %{question: "fact_stated", fact_id: "pergunta-explicita-02", score: 0.25}
        ]
      }
    end

    # A key on-request fact the learner clearly did not ask for, clearly stated.
    defp decision("Não tomo remédio, mas tenho alergia a dipirona.") do
      %{
        status: :low_confidence,
        used_fact_ids: ["fact-key"],
        not_asked_fact_ids: ["fact-key"],
        stated_not_asked_fact_ids: ["fact-key"],
        fact_scores: [%{fact_id: "fact-key", stated: 0.9, asked: 0.19}],
        undecided_labels: [%{question: "risk:unsupported_information", score: 0.5}]
      }
    end

    # Live turn 9 (issue #290): a generic denial Jev thinks may state a narrow
    # explicit-question fact the learner clearly did not ask about.
    defp decision("Não tomo nenhum remédio regularmente, doutor.") do
      %{
        status: :low_confidence,
        used_fact_ids: [],
        not_asked_fact_ids: ["pergunta-explicita-02"],
        fact_scores: [%{fact_id: "pergunta-explicita-02", stated: 0.31, asked: 0.19}],
        undecided_labels: [
          %{question: "fact_stated", fact_id: "pergunta-explicita-02", score: 0.31}
        ]
      }
    end

    defp decision("Não tomo nenhum remédio."), do: %{status: :verified, used_fact_ids: []}

    defp decision("Não, nada de remédio.") do
      %{
        status: :low_confidence,
        used_fact_ids: [],
        undecided_labels: [%{question: "risk:unsupported_information", score: 0.5}]
      }
    end
  end

  # Adjudicator double: answers `opts[:answers][candidate]` and reports the call.
  defmodule Adjudicator do
    @behaviour Backend.Stations.PatientAdjudicator

    @impl true
    def adjudicate(request, opts) do
      send(opts[:test_pid], {:adjudicated, request.candidate_reply})
      Map.fetch!(opts[:answers], request.candidate_reply)
    end
  end

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
        "id" => "fact-key",
        "content" => "Tem alergia a dipirona.",
        "disclosure_condition" => "on_request"
      }
    ],
    "response_rules" => []
  }

  @conversation [%{role: :learner, text: "Toma algum remédio?"}]

  defp answer(decision, ids \\ []),
    do: {:ok, %{"decision" => decision, "withheld_fact_ids" => ids}}

  defp verify(candidate, answers, opts \\ []) do
    test_pid = self()

    generator =
      Keyword.get(opts, :generator, fn _package, _conversation, _remaining, guidance ->
        send(test_pid, {:regenerated, guidance.withheld_fact_ids})
        {:ok, Keyword.get(opts, :regen, @regen_verified)}
      end)

    CandidateGate.verify(
      candidate,
      @package,
      @conversation,
      [
        adapter: Jev,
        adjudicator_adapter: Adjudicator,
        adjudicator_opts: [answers: answers, test_pid: test_pid],
        generator: generator,
        deadline_ms: 3_000
      ] ++ Keyword.drop(opts, [:generator, :regen])
    )
  end

  test "the rehearsal medication question is delivered when the adjudicator says deliver" do
    assert verify(@medication, %{@medication => answer("deliver")}) ==
             {:ok, %{text: @medication, used_fact_ids: ["hda-06-antitermico"]}}

    assert_received {:adjudicated, @medication}
    refute_received {:regenerated, _}
  end

  test "regenerate runs the single regeneration withholding the adjudicator's facts" do
    assert verify(@medication, %{@medication => answer("regenerate", ["pergunta-explicita-02"])}) ==
             {:ok, %{text: @regen_verified, used_fact_ids: []}}

    assert_received {:regenerated, ["pergunta-explicita-02"]}
  end

  test "only a regeneration the adjudicator asked for gets the extended budget" do
    test_pid = self()

    generator = fn _package, _conversation, remaining_ms, _guidance ->
      send(test_pid, {:remaining_ms, remaining_ms})
      {:ok, @regen_verified}
    end

    opts = [generator: generator, adjudicator_extension_ms: 1_500]

    assert {:ok, _} =
             verify(@medication, %{@medication => answer("regenerate", ["fact-key"])}, opts)

    assert_received {:remaining_ms, extended}
    assert extended > 3_000 and extended <= 4_500

    # A refusal keeps today's path and today's budget.
    assert {:ok, _} = verify(@medication, %{@medication => answer("refuse")}, opts)
    assert_received {:remaining_ms, normal}
    assert normal <= 3_000
  end

  test "refuse keeps today's low-confidence path" do
    assert verify(@medication, %{@medication => answer("refuse")}) ==
             {:ok, %{text: @regen_verified, used_fact_ids: []}}

    # Jev named no undecided fact, so the regeneration withholds nothing.
    assert_received {:regenerated, []}

    assert verify(@medication, %{@medication => answer("refuse")}, can_retry?: false) ==
             {:error, {:refused, :low_confidence}}
  end

  test "an adjudicator failure keeps today's low-confidence path" do
    for failure <- [{:error, :timeout}, {:ok, %{"decision" => "maybe"}}, {:error, :refused}] do
      assert verify(@medication, %{@medication => failure}, can_retry?: false) ==
               {:error, {:refused, :low_confidence}}
    end
  end

  test "a generic denial that may state an unrequested fact is delivered on deliver" do
    denial = "Não tomo nenhum remédio regularmente, doutor."

    assert verify(denial, %{denial => answer("deliver")}) ==
             {:ok, %{text: denial, used_fact_ids: []}}

    refute_received {:regenerated, _}
  end

  test "a key fact Jev found clearly unrequested is never delivered" do
    assert verify(@key_fact, %{@key_fact => answer("deliver")}) ==
             {:ok, %{text: @regen_verified, used_fact_ids: []}}

    assert_received {:regenerated, ["fact-key"]}

    assert verify(@key_fact, %{@key_fact => answer("deliver")}, can_retry?: false) ==
             {:error, {:refused, :low_confidence}}
  end

  test "the regenerated candidate is adjudicated too, without a second regeneration" do
    answers = %{
      @medication => answer("regenerate", ["pergunta-explicita-02"]),
      @regen_undecided => answer("deliver")
    }

    assert verify(@medication, answers, regen: @regen_undecided) ==
             {:ok, %{text: @regen_undecided, used_fact_ids: []}}

    answers = %{answers | @regen_undecided => answer("regenerate", ["fact-key"])}

    assert verify(@medication, answers, regen: @regen_undecided) ==
             {:error, {:refused, :low_confidence}}

    assert_received {:regenerated, ["pergunta-explicita-02"]}
    refute_received {:regenerated, ["fact-key"]}
  end

  test "a candidate the deterministic checks deny never reaches Jev or the adjudicator" do
    assert {:error, {:denied, _reason}} =
             verify("Sou uma inteligência artificial.", %{})

    refute_received {:adjudicated, _}
  end

  test "a voice sentence after the first one is delivered or refused, never regenerated" do
    assert verify(@medication, %{@medication => answer("deliver")}, can_retry?: false) ==
             {:ok, %{text: @medication, used_fact_ids: ["hda-06-antitermico"]}}

    assert verify(@medication, %{@medication => answer("regenerate", [])}, can_retry?: false) ==
             {:error, {:refused, :low_confidence}}

    refute_received {:regenerated, _}
  end

  test "the turn deadline still bounds the adjudication" do
    # 150 ms left: below the adjudicator's minimum budget once the margin is kept.
    assert verify(@medication, %{@medication => answer("deliver")},
             can_retry?: false,
             deadline_at_monotonic_ms: System.monotonic_time(:millisecond) + 150
           ) == {:error, {:refused, :low_confidence}}

    refute_received {:adjudicated, _}
  end
end
