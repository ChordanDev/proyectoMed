defmodule Backend.Stations.MultiturnVerificationTest do
  @moduledoc """
  Issue #286: patient replies stay verifiable as the conversation grows. The
  generator answers only the latest learner question, and a fact an earlier
  verified patient turn disclosed is not re-gated by Jev.
  """
  use ExUnit.Case, async: false

  alias Backend.Stations

  @reply "A dor começou ontem à noite."

  # Reports the conversation of every generation to the test process. Streams
  # the reply as two sentences when asked to.
  defmodule RecordingAI do
    @behaviour Backend.Stations.StationAI

    @impl true
    def next_reply(_package, context) do
      send(Application.fetch_env!(:backend, :multiturn_test_pid), {:generation, context})
      {:ok, %{text: "A dor começou ontem à noite.", used_facts: []}}
    end

    @impl true
    def stream_reply(_package, context, on_text) do
      send(Application.fetch_env!(:backend, :multiturn_test_pid), {:generation, context})
      on_text.("A dor começou ontem à noite. ")
      on_text.("Ainda dói.")
      {:ok, %{text: "A dor começou ontem à noite. Ainda dói."}}
    end
  end

  # Reports every patient request and answers with the scripted decision
  # (`:multiturn_jev_decision`: a map with at least `:status`, or a function of
  # the request returning one).
  defmodule ScriptedJev do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(request) do
      send(Application.fetch_env!(:backend, :multiturn_test_pid), {:jev_patient, request})

      case Application.fetch_env!(:backend, :multiturn_jev_decision) do
        decide when is_function(decide, 1) -> {:ok, decide.(request)}
        decision -> {:ok, decision}
      end
    end

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  # The acute-appendicitis package: the station of the rehearsal, with several
  # authored facts whose ids a verdict may name.
  setup do
    keys = [
      :station_ai_adapter,
      :jev_decision_adapter,
      :multiturn_test_pid,
      :multiturn_jev_decision,
      :active_station_id
    ]

    previous = Map.new(keys, &{&1, Application.fetch_env(:backend, &1)})

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, value} -> Application.put_env(:backend, key, value)
          :error -> Application.delete_env(:backend, key)
        end
      end

      restart_loader()
    end)

    Application.put_env(:backend, :active_station_id, "acute-appendicitis")
    restart_loader()

    Application.put_env(:backend, :station_ai_adapter, RecordingAI)
    Application.put_env(:backend, :jev_decision_adapter, ScriptedJev)
    Application.put_env(:backend, :multiturn_test_pid, self())

    session = Stations.create_session(%{audio_consent: true})
    %{session_id: session.session_id}
  end

  defp restart_loader do
    :ok = Supervisor.terminate_child(Backend.Supervisor, Backend.Stations.StationLoader)
    {:ok, _pid} = Supervisor.restart_child(Backend.Supervisor, Backend.Stations.StationLoader)
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

  defp fact_ids do
    Stations.get_active_package()
    |> Map.fetch!("revealable_facts")
    |> Enum.map(& &1["id"])
    |> Enum.take(3)
  end

  defp verified_with(ids), do: %{status: :verified, used_fact_ids: ids}

  # The `disclosed_fact_ids` of the next patient request Jev receives.
  defp next_disclosed do
    assert_receive {:jev_patient, %{disclosed_fact_ids: disclosed}}
    disclosed
  end

  defp voice_turn(id, turn_id, text), do: Stations.process_voice_turn(id, turn_id, text)

  defp stream_turn(id, turn_id, text) do
    {result, _acc} = Stations.stream_voice_turn(id, turn_id, text, [], &{:cont, [&1 | &2]})
    result
  end

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
      # The patient's earlier reply shows the addressee marker it was given with (#309).
      assert texts(generated) == [
               "Qual é seu nome?",
               "[PACIENTE] " <> @reply,
               "Teve náusea ou vômito?"
             ]

      assert Enum.map(generated, & &1.role) == [:student, :patient, :student]
    end
  end

  describe "facts disclosed by verified patient turns" do
    test "a text turn's verified facts reach every later Jev request", %{session_id: id} do
      [first, second | _] = fact_ids()

      jev_answers(verified_with([first]))
      assert {:ok, _} = ask(id, "Onde começou a dor?")
      assert next_disclosed() == []

      jev_answers(verified_with([second]))
      assert {:ok, _} = ask(id, "Há quanto tempo começou?")
      assert next_disclosed() == [first]

      jev_answers(verified_with([]))
      assert {:ok, _} = ask(id, "Ela piorou com o tempo?")
      assert next_disclosed() == [first, second]
    end

    test "a refused candidate's facts are not recorded and a kept turn keeps the set",
         %{session_id: id} do
      [first, second | _] = fact_ids()

      jev_answers(verified_with([first]))
      assert {:ok, _} = ask(id, "Onde começou a dor?")
      flush_mailbox()

      jev_answers(%{status: :semantic_refusal, used_fact_ids: [second]})
      assert {:error, {:refused, _, _}} = ask(id, "Teve febre?")
      flush_mailbox()

      jev_answers(verified_with([]))
      assert {:ok, _} = ask(id, "Teve náusea?")
      assert next_disclosed() == [first]
    end

    test "the set is kept in the session and shared by text and voice turns",
         %{session_id: id} do
      [first, second, third] = fact_ids()

      jev_answers(verified_with([first]))
      assert {:ok, _} = ask(id, "Onde começou a dor?")
      flush_mailbox()

      jev_answers(verified_with([second]))
      assert {:ok, %{reply_text: @reply}} = voice_turn(id, 1, "Há quanto tempo começou?")
      assert next_disclosed() == [first]

      jev_answers(verified_with([third]))
      assert {:ok, %{generation_id: _}} = stream_turn(id, 2, "Ela piorou com o tempo?")
      assert next_disclosed() == [first, second]
      flush_mailbox()

      jev_answers(verified_with([]))
      assert {:ok, _} = ask(id, "Teve febre?")
      assert next_disclosed() == [first, second, third]

      {:ok, session} = Stations.get_session(id)

      assert session.messages |> Enum.filter(&(&1.role == :patient)) |> length() == 4
    end

    test "a cancelled voice turn records nothing and keeps the set", %{session_id: id} do
      [first, second | _] = fact_ids()

      jev_answers(verified_with([first]))
      assert {:ok, _} = voice_turn(id, 1, "Onde começou a dor?")
      flush_mailbox()

      # The learner barges in while the reply is verified: the generation is
      # cancelled, so its verified facts never reach the session.
      jev_answers(fn _request ->
        {:ok, :cancelled} = Stations.cancel_voice_turn(id)
        verified_with([second])
      end)

      assert {:error, :stale_generation} = voice_turn(id, 2, "Teve febre?")
      flush_mailbox()

      jev_answers(verified_with([]))
      assert {:ok, _} = stream_turn(id, 3, "Teve náusea?")
      assert next_disclosed() == [first]
    end

    test "a streamed reply records the facts of its verified sentences", %{session_id: id} do
      [first, second | _] = fact_ids()

      jev_answers(fn %{candidate_text: candidate} ->
        if String.contains?(candidate, "Ainda dói"),
          do: verified_with([first, second]),
          else: verified_with([first])
      end)

      assert {:ok, _} = stream_turn(id, 1, "Onde começou a dor?")
      flush_mailbox()

      jev_answers(verified_with([]))
      assert {:ok, _} = ask(id, "Teve febre?")
      assert next_disclosed() == [first, second]
    end
  end
end
