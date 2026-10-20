defmodule Backend.Stations.CandidateGateRefusalCausesTest do
  # async: false: the counts are node-wide, and the logger level is changed.
  use ExUnit.Case, async: false

  alias Backend.Stations
  alias Backend.Stations.CandidateGate

  # Every decision is keyed by the candidate text, so a test picks its cause.
  defmodule CauseAdapter do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(%{candidate_text: text}), do: {:ok, decision(text)}

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}

    defp decision("cause verified"), do: %{status: :verified}
    defp decision("cause risk"), do: %{status: :semantic_refusal}

    defp decision("cause unasked"),
      do: %{status: :semantic_refusal, unasked_fact_ids: ["fact-1"]}

    defp decision("cause undecided unasked"),
      do: %{status: :low_confidence, undecided_fact_ids: ["fact-1"]}

    defp decision("cause undecided other"), do: %{status: :low_confidence}
  end

  @package %{
    "station_id" => "station-1",
    "version" => "1.0.0",
    "language" => "pt-BR",
    "revealable_facts" => [
      %{"id" => "fact-1", "content" => "Nega alergias.", "disclosure_condition" => "on_request"}
    ],
    "response_rules" => []
  }

  setup do
    level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: level) end)
  end

  defp verify(text) do
    CandidateGate.verify_and_deliver(text, @package, [],
      adapter: CauseAdapter,
      can_retry?: false
    )
  end

  defp delta(before, cause), do: Stations.refusal_cause_counts()[cause] - before[cause]

  test "counts every Jev decision by cause, the verified ones included" do
    before = Stations.refusal_cause_counts()

    assert {:ok, "cause verified"} = verify("cause verified")
    assert {:error, {:refused, :semantic_refusal}} = verify("cause risk")
    assert {:error, {:refused, :semantic_refusal}} = verify("cause unasked")
    assert {:error, {:refused, :low_confidence}} = verify("cause undecided unasked")
    assert {:error, {:refused, :low_confidence}} = verify("cause undecided other")
    assert {:error, {:refused, :low_confidence}} = verify("cause undecided other")

    assert delta(before, :verified) == 1
    assert delta(before, :risk) == 1
    assert delta(before, :unasked_fact) == 1
    assert delta(before, :undecided_unasked_fact) == 1
    assert delta(before, :undecided_other) == 2
  end

  test "the regenerated candidate's decision is counted too" do
    before = Stations.refusal_cause_counts()

    assert {:ok, "cause verified"} =
             CandidateGate.verify_and_deliver("cause undecided unasked", @package, [],
               adapter: CauseAdapter,
               generator: fn -> {:ok, "cause verified"} end
             )

    assert delta(before, :undecided_unasked_fact) == 1
    assert delta(before, :verified) == 1
  end

  test "each refusal logs only its cause name and count, never text or ids" do
    log = ExUnit.CaptureLog.capture_log(fn -> verify("cause undecided unasked") end)

    assert log =~ ~r/\[CandidateGate\] refusal cause=undecided_unasked_fact count=\d+/
    refute log =~ "cause undecided unasked"
    refute log =~ "fact-1"
  end

  test "a verified decision logs nothing" do
    log = ExUnit.CaptureLog.capture_log(fn -> verify("cause verified") end)
    refute log =~ "[CandidateGate]"
  end
end
