defmodule Backend.Stations.TurnAddresseeEvidenceTest do
  @moduledoc """
  Issue #274 regression: deciding the addressee of a learner turn does not change
  grading evidence. The text turns of the #228 regression fixture are sent twice
  through `Stations.create_message/2`:

    * as before #274: no addressee check (an adapter without it), and the patient
      decision refuses the turns spoken to the examiner, so they are kept (#235);
    * with the check: the same turns are examiner-addressed and acknowledged with
      no generation.

  Both sessions yield the same evidence pool (apart from timestamps).
  """
  use ExUnit.Case, async: false

  alias Backend.Stations
  alias Backend.Stations.RubricAssessment.Evidence

  @fixture_path Path.expand("rubric_assessment/fixtures/issue_228_session.json", __DIR__)
  @examiner_keys ~w(exam-verbalization lab-interpretation imaging-hypothesis support-measures surgery-antibiotic)

  defmodule FixedAI do
    @behaviour Backend.Stations.StationAI

    @impl true
    def next_reply(_package, _context), do: {:ok, %{text: "Entendi, doutor.", used_facts: []}}
  end

  # Before #274: no addressee check; the patient decision refuses the reply to
  # a turn listed in `:evidence_test_examiner_texts`.
  defmodule BaselineJev do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(%{latest_learner_turn: %{text: text}}) do
      if text in Application.fetch_env!(:backend, :evidence_test_examiner_texts),
        do: {:ok, %{status: :semantic_refusal}},
        else: {:ok, %{status: :verified}}
    end

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  defmodule AddresseeJev do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_addressee(%{latest_learner_turn: %{text: text}}) do
      if text in Application.fetch_env!(:backend, :evidence_test_examiner_texts),
        do: {:ok, %{addressee: :examiner}},
        else: {:ok, %{addressee: :patient}}
    end

    @impl true
    def decide_patient(_request), do: {:ok, %{status: :verified}}

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  setup do
    keys = [:station_ai_adapter, :jev_decision_adapter, :evidence_test_examiner_texts]
    previous = Map.new(keys, &{&1, Application.fetch_env(:backend, &1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:backend, key, value)
        {key, :error} -> Application.delete_env(:backend, key)
      end)
    end)

    Application.put_env(:backend, :station_ai_adapter, FixedAI)
    :ok
  end

  defp learner_texts do
    @fixture_path
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("turns")
    |> Enum.filter(&(&1["role"] == "learner" and &1["modality"] == "text"))
  end

  defp run_attempt(jev_adapter) do
    Application.put_env(:backend, :jev_decision_adapter, jev_adapter)
    session = Stations.create_session(%{audio_consent: false})

    outcomes =
      for %{"text" => text} <- learner_texts() do
        case Stations.create_message(session.session_id, %{
               role: "learner",
               modality: "text",
               text: text
             }) do
          {:ok, %{outcome: outcome}} -> outcome
          {:error, {:refused, _reason, _turn}} -> :kept
        end
      end

    {:ok, stored} = Stations.get_session(session.session_id)

    pool =
      stored |> Evidence.build(Stations.get_active_package()) |> Enum.map(&Map.delete(&1, :at))

    {outcomes, pool}
  end

  test "examiner-addressed turns leave the same evidence as kept refusals did" do
    examiner_texts =
      for %{"key" => key, "text" => text} <- learner_texts(), key in @examiner_keys, do: text

    assert length(examiner_texts) == length(@examiner_keys)
    Application.put_env(:backend, :evidence_test_examiner_texts, examiner_texts)

    {baseline_outcomes, baseline_pool} = run_attempt(BaselineJev)
    {addressee_outcomes, addressee_pool} = run_attempt(AddresseeJev)

    assert Enum.count(baseline_outcomes, &(&1 == :kept)) == length(@examiner_keys)

    assert Enum.count(addressee_outcomes, &(&1 == :examiner_acknowledged)) ==
             length(@examiner_keys)

    assert addressee_pool == baseline_pool

    learner_items = Enum.filter(addressee_pool, &(&1.role == :learner))
    assert Enum.map(learner_items, & &1.text) == Enum.map(learner_texts(), & &1["text"])
  end
end
