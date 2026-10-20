defmodule Backend.Stations.MultiturnVerificationTest do
  @moduledoc """
  Issue #286: patient replies stay verifiable as the conversation grows. The
  generator answers only the latest learner question, and a fact an earlier
  verified patient turn disclosed is not re-gated by Jev.
  """
  use ExUnit.Case, async: false

  alias Backend.Stations

  @reply "A dor começou ontem à noite."

  # Reports the conversation of every generation to the test process.
  defmodule RecordingAI do
    @behaviour Backend.Stations.StationAI

    @impl true
    def next_reply(_package, context) do
      send(Application.fetch_env!(:backend, :multiturn_test_pid), {:generation, context})
      {:ok, %{text: "A dor começou ontem à noite.", used_facts: []}}
    end
  end

  # Reports every patient request and answers with the scripted decision
  # (`:multiturn_jev_decision`, a map with at least `:status`).
  defmodule ScriptedJev do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(request) do
      send(Application.fetch_env!(:backend, :multiturn_test_pid), {:jev_patient, request})
      {:ok, Application.fetch_env!(:backend, :multiturn_jev_decision)}
    end

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  setup do
    keys = [
      :station_ai_adapter,
      :jev_decision_adapter,
      :multiturn_test_pid,
      :multiturn_jev_decision
    ]

    previous = Map.new(keys, &{&1, Application.fetch_env(:backend, &1)})

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, value} -> Application.put_env(:backend, key, value)
          :error -> Application.delete_env(:backend, key)
        end
      end
    end)

    Application.put_env(:backend, :station_ai_adapter, RecordingAI)
    Application.put_env(:backend, :jev_decision_adapter, ScriptedJev)
    Application.put_env(:backend, :multiturn_test_pid, self())

    session = Stations.create_session(%{audio_consent: true})
    %{session_id: session.session_id}
  end

  defp jev_answers(decision),
    do: Application.put_env(:backend, :multiturn_jev_decision, decision)

  defp ask(session_id, text), do: Stations.create_message(session_id, %{text: text})

  defp flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      0 -> :ok
    end
  end

  defp texts(turns), do: Enum.map(turns, & &1.text)

  describe "generator context" do
    test "omits a learner turn that never got a patient reply; Jev keeps it",
         %{session_id: id} do
      jev_answers(%{status: :semantic_refusal})
      assert {:error, {:refused, _status, _kept}} = ask(id, "Teve febre?")
      flush_mailbox()

      jev_answers(%{status: :verified})
      assert {:ok, %{reply_text: @reply}} = ask(id, "Quando a dor começou?")

      assert_received {:generation, %{conversation: generated}}
      assert texts(generated) == ["Quando a dor começou?"]

      assert_received {:jev_patient, %{conversation: judged}}
      assert texts(judged) == ["Teve febre?", "Quando a dor começou?"]
    end

    test "keeps answered turns and drops every stale question before the latest",
         %{session_id: id} do
      jev_answers(%{status: :verified})
      assert {:ok, _} = ask(id, "Qual é seu nome?")

      jev_answers(%{status: :semantic_refusal})
      assert {:error, {:refused, _, _}} = ask(id, "A dor vai para outro lugar?")
      assert {:error, {:refused, _, _}} = ask(id, "Teve febre?")
      flush_mailbox()

      jev_answers(%{status: :verified})
      assert {:ok, _} = ask(id, "Teve náusea ou vômito?")

      assert_received {:generation, %{conversation: generated}}
      assert texts(generated) == ["Qual é seu nome?", @reply, "Teve náusea ou vômito?"]
      assert Enum.map(generated, & &1.role) == [:student, :patient, :student]
    end
  end
end
