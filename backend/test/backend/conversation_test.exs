defmodule Backend.ConversationTest do
  use ExUnit.Case, async: false

  alias Backend.Conversation
  alias Backend.Stations.Conversation, as: StationConversation

  test "start creates an active session with a thirty-minute safety timeout and default station identity" do
    session = Conversation.start()

    assert is_binary(session.session_id)
    assert session.station_id == "chest-pain-initial-assessment"
    assert session.station_version == "2.0.0"
    assert session.audio_consent == false
    assert %DateTime{} = session.started_at
    assert %DateTime{} = session.expires_at
    assert DateTime.diff(session.expires_at, session.started_at, :second) == 30 * 60
    assert session.messages == []
    assert session.status == :active
  end

  test "start sets an authoritative ten-minute deadline_at, independent from the thirty-minute expires_at" do
    session = Conversation.start()

    assert %DateTime{} = session.deadline_at
    assert DateTime.diff(session.deadline_at, session.started_at, :second) == 10 * 60
    assert DateTime.compare(session.deadline_at, session.expires_at) == :lt
  end

  test "start accepts custom station_id, station_version, and audio_consent" do
    session =
      Conversation.start(%{
        station_id: "custom-station",
        station_version: "2.1.0",
        audio_consent: true
      })

    assert session.station_id == "custom-station"
    assert session.station_version == "2.1.0"
    assert session.audio_consent == true
  end

  test "append_message adds a timestamped message to an active session" do
    session = Conversation.start()

    assert {:ok, updated_session} =
             Conversation.append_message(session.session_id, %{
               role: :learner,
               modality: :text,
               text: "Bom dia"
             })

    assert [%{role: :learner, modality: :text, text: "Bom dia", at: %DateTime{}}] =
             updated_session.messages
  end

  test "complete locks a session and preserves its completion reason" do
    session = Conversation.start()

    assert {:ok, completed_session} = Conversation.complete(session.session_id, :user)

    assert completed_session.status == :completed
    assert completed_session.completion_reason == :user
    assert %DateTime{} = completed_session.completed_at

    assert {:error, :completed} =
             Conversation.append_message(session.session_id, %{
               role: :learner,
               modality: :text,
               text: "Late message"
             })
  end

  test "double complete is idempotent and keeps the original completion" do
    session = Conversation.start()

    assert {:ok, completed_session} = Conversation.complete(session.session_id, :user)
    assert {:ok, same_session} = Conversation.complete(session.session_id, :timer)

    assert same_session == completed_session
  end

  test "fetch returns a session and reports unknown session ids" do
    session = Conversation.start()

    assert {:ok, ^session} = Conversation.fetch(session.session_id)
    assert {:error, :not_found} = Conversation.fetch("unknown-session")
  end

  test "expired sessions are removed when fetched" do
    original_timeout = Application.get_env(:backend, :conversation_timeout_ms)
    Application.put_env(:backend, :conversation_timeout_ms, 0)

    on_exit(fn ->
      if is_nil(original_timeout) do
        Application.delete_env(:backend, :conversation_timeout_ms)
      else
        Application.put_env(:backend, :conversation_timeout_ms, original_timeout)
      end
    end)

    session = Conversation.start()

    assert {:error, :expired} = Conversation.fetch(session.session_id)
    assert {:error, :not_found} = Conversation.fetch(session.session_id)
  end

  test "pop_last_message removes the latest message matching expected role and text" do
    session = Conversation.start()

    {:ok, _} =
      Conversation.append_message(session.session_id, %{
        role: :learner,
        modality: :text,
        text: "Primeira mensagem"
      })

    {:ok, _} =
      Conversation.append_message(session.session_id, %{
        role: :learner,
        modality: :text,
        text: "Segunda mensagem"
      })

    assert {:ok, popped} =
             Conversation.pop_last_message(session.session_id, %{
               role: :learner,
               text: "Segunda mensagem"
             })

    assert length(popped.messages) == 1
    assert hd(popped.messages).text == "Primeira mensagem"

    assert {:error, :no_match} =
             Conversation.pop_last_message(session.session_id, %{
               role: :learner,
               text: "Outro texto"
             })
  end

  describe "record_impresso_request/4" do
    test "starts a session with empty impresso state" do
      session = Conversation.start()
      assert session.released_impressos == []
      assert session.impresso_requests == []
    end

    test "appends an event and releases newly matched ids in order" do
      session = Conversation.start()

      assert {:ok, %{event: event, session: updated}} =
               Backend.Stations.Conversation.record_impresso_request(
                 session.session_id,
                 "req-1",
                 ["ecg", "raio-x"],
                 "quero ecg e raio-x"
               )

      assert event.request_id == "req-1"
      assert event.station_id == session.station_id
      assert event.station_version == session.station_version
      assert event.order == 1
      assert event.matched_ids == ["ecg", "raio-x"]
      assert event.decision == :released
      assert event.released_ids == ["ecg", "raio-x"]
      assert %DateTime{} = event.at

      assert updated.released_impressos == ["ecg", "raio-x"]
      assert updated.impresso_requests == [event]
    end

    test "a second request only releases the newly matched ids and increments order" do
      session = Conversation.start()

      {:ok, _} =
        Backend.Stations.Conversation.record_impresso_request(
          session.session_id,
          "req-1",
          ["ecg"],
          "ecg"
        )

      assert {:ok, %{event: event, session: updated}} =
               Backend.Stations.Conversation.record_impresso_request(
                 session.session_id,
                 "req-2",
                 ["ecg", "raio-x"],
                 "ecg e raio-x"
               )

      assert event.order == 2
      assert event.decision == :released
      assert event.released_ids == ["raio-x"]
      assert updated.released_impressos == ["ecg", "raio-x"]
    end

    test "already-released matches produce an already_released event with no new releases" do
      session = Conversation.start()

      {:ok, _} =
        Backend.Stations.Conversation.record_impresso_request(
          session.session_id,
          "req-1",
          ["ecg"],
          "ecg"
        )

      assert {:ok, %{event: event, session: updated}} =
               Backend.Stations.Conversation.record_impresso_request(
                 session.session_id,
                 "req-2",
                 ["ecg"],
                 "ecg de novo"
               )

      assert event.decision == :already_released
      assert event.released_ids == []
      assert updated.released_impressos == ["ecg"]
    end

    test "no matched ids produce an unavailable event releasing nothing" do
      session = Conversation.start()

      assert {:ok, %{event: event, session: updated}} =
               Backend.Stations.Conversation.record_impresso_request(
                 session.session_id,
                 "req-1",
                 [],
                 "tomografia de cranio"
               )

      assert event.decision == :unavailable
      assert event.released_ids == []
      assert updated.released_impressos == []
    end

    test "a repeated request_id returns the original event without appending a new one" do
      session = Conversation.start()

      {:ok, %{event: first_event}} =
        Backend.Stations.Conversation.record_impresso_request(
          session.session_id,
          "req-1",
          ["ecg"],
          "ecg"
        )

      assert {:ok, %{event: replayed_event, session: updated}} =
               Backend.Stations.Conversation.record_impresso_request(
                 session.session_id,
                 "req-1",
                 ["ecg", "raio-x"],
                 "ecg (should be ignored)"
               )

      assert replayed_event == first_event
      assert length(updated.impresso_requests) == 1
    end

    test "returns not_found, expired and completed like the other session calls" do
      assert {:error, :not_found} =
               Backend.Stations.Conversation.record_impresso_request(
                 "unknown",
                 "req-1",
                 ["ecg"],
                 "ecg"
               )

      session = Conversation.start()
      {:ok, _} = Conversation.complete(session.session_id, :user)

      assert {:error, :completed} =
               Backend.Stations.Conversation.record_impresso_request(
                 session.session_id,
                 "req-1",
                 ["ecg"],
                 "ecg"
               )

      original_timeout = Application.get_env(:backend, :conversation_timeout_ms)
      Application.put_env(:backend, :conversation_timeout_ms, 0)

      expired_session =
        try do
          Conversation.start()
        after
          if is_nil(original_timeout) do
            Application.delete_env(:backend, :conversation_timeout_ms)
          else
            Application.put_env(:backend, :conversation_timeout_ms, original_timeout)
          end
        end

      assert {:error, :expired} =
               Backend.Stations.Conversation.record_impresso_request(
                 expired_session.session_id,
                 "req-1",
                 ["ecg"],
                 "ecg"
               )
    end

    test "discard removes released impressos and requests along with the session" do
      session = Conversation.start()

      {:ok, _} =
        Backend.Stations.Conversation.record_impresso_request(
          session.session_id,
          "req-1",
          ["ecg"],
          "ecg"
        )

      :ok = Conversation.discard(session.session_id)

      assert {:error, :not_found} = Conversation.fetch(session.session_id)
    end
  end

  describe "discard/1" do
    test "removes an active session from storage" do
      session = Conversation.start()
      assert {:ok, _} = Conversation.fetch(session.session_id)

      assert :ok = Conversation.discard(session.session_id)
      assert {:error, :not_found} = Conversation.fetch(session.session_id)
    end

    test "removes a completed session from storage" do
      session = Conversation.start()
      {:ok, _} = Conversation.complete(session.session_id, :user)

      assert :ok = Conversation.discard(session.session_id)
      assert {:error, :not_found} = Conversation.fetch(session.session_id)
    end

    test "is idempotent on repeated discard and non-existent sessions" do
      assert :ok = Conversation.discard("non-existent-session-id")

      session = Conversation.start()
      assert :ok = Conversation.discard(session.session_id)
      assert :ok = Conversation.discard(session.session_id)
      assert :ok = Conversation.discard(session.session_id)
    end

    test "removes an expired session" do
      original_timeout = Application.get_env(:backend, :conversation_timeout_ms)
      Application.put_env(:backend, :conversation_timeout_ms, 0)

      session =
        try do
          Conversation.start()
        after
          restore_env(:conversation_timeout_ms, original_timeout)
        end

      assert :ok = Conversation.discard(session.session_id)
      assert {:error, :not_found} = Conversation.fetch(session.session_id)
    end

    test "atomically releases in-flight turn, cancels grace timer, unblocks pending waiters, and clears turn state" do
      session = Conversation.start()

      assert {:ok, _session, token} =
               StationConversation.begin_turn(session.session_id, %{
                 role: :learner,
                 modality: :text,
                 text: "Em andamento"
               })

      waiter_task =
        Task.async(fn ->
          Conversation.complete(session.session_id, :user)
        end)

      Process.sleep(20)

      assert :ok = Conversation.discard(session.session_id)

      assert Task.await(waiter_task, 1_000) == {:error, :not_found}
      assert {:error, :not_found} = Conversation.fetch(session.session_id)

      assert {:error, :station_time_elapsed} =
               StationConversation.resolve_turn(
                 session.session_id,
                 token,
                 {:ok, %{role: :patient, modality: :text, text: "Resposta tardia"}}
               )
    end

    test "multiple completion waiters are all released when session is discarded" do
      session = Conversation.start()

      assert {:ok, _session, _token} =
               StationConversation.begin_turn(session.session_id, %{
                 role: :learner,
                 modality: :text,
                 text: "Em andamento"
               })

      waiter_1 = Task.async(fn -> Conversation.complete(session.session_id, :user) end)
      waiter_2 = Task.async(fn -> Conversation.complete(session.session_id, :timer) end)

      Process.sleep(20)

      assert :ok = Conversation.discard(session.session_id)

      assert Task.await(waiter_1, 1_000) == {:error, :not_found}
      assert Task.await(waiter_2, 1_000) == {:error, :not_found}
    end
  end

  describe "authoritative deadline and pending turns (Ticket 133)" do
    setup do
      original_duration = Application.get_env(:backend, :station_duration_ms)
      original_grace = Application.get_env(:backend, :turn_grace_ms)

      on_exit(fn ->
        restore_env(:station_duration_ms, original_duration)
        restore_env(:turn_grace_ms, original_grace)
      end)

      :ok
    end

    test "begin_turn rejects a turn at/after the deadline without touching the transcript" do
      Application.put_env(:backend, :station_duration_ms, 30)
      session = Conversation.start()

      Process.sleep(60)

      assert {:error, :station_time_elapsed} =
               StationConversation.begin_turn(session.session_id, %{
                 role: :learner,
                 modality: :text,
                 text: "Chegou tarde"
               })

      assert {:ok, %{messages: []}} = Conversation.fetch(session.session_id)
    end

    test "begin_turn/resolve_turn appends a patient reply for a turn accepted before the deadline" do
      session = Conversation.start()

      assert {:ok, _session, token} =
               StationConversation.begin_turn(session.session_id, %{
                 role: :learner,
                 modality: :text,
                 text: "Bom dia"
               })

      assert {:ok, resolved} =
               StationConversation.resolve_turn(
                 session.session_id,
                 token,
                 {:ok,
                  %{
                    role: :patient,
                    modality: :text,
                    text: "Resposta do paciente"
                  }}
               )

      assert resolved.status == :active
      assert length(resolved.messages) == 2
    end

    test "the deadline timer auto-completes an active session with reason :timer exactly once" do
      Application.put_env(:backend, :station_duration_ms, 30)
      session = Conversation.start()

      Process.sleep(120)

      assert {:ok, completed} = Conversation.fetch(session.session_id)
      assert completed.status == :completed
      assert completed.completion_reason == :timer
      completed_at = completed.completed_at

      # Idempotent: a manual finish afterwards does not change the recorded reason/time.
      assert {:ok, same} = Conversation.complete(session.session_id, :user)
      assert same.completion_reason == :timer
      assert same.completed_at == completed_at
    end

    test "an accepted pending turn defers timer auto-completion and resolves within the grace window" do
      Application.put_env(:backend, :station_duration_ms, 30)
      Application.put_env(:backend, :turn_grace_ms, 200)

      session = Conversation.start()

      assert {:ok, _session, token} =
               StationConversation.begin_turn(session.session_id, %{
                 role: :learner,
                 modality: :text,
                 text: "Pergunta antes do prazo"
               })

      # Let the deadline pass while the turn is still pending.
      Process.sleep(60)
      assert {:ok, %{status: :active}} = Conversation.fetch(session.session_id)

      assert {:ok, resolved} =
               StationConversation.resolve_turn(
                 session.session_id,
                 token,
                 {:ok,
                  %{
                    role: :patient,
                    modality: :text,
                    text: "Resposta dentro da graça"
                  }}
               )

      # The reply is appended, and completion (deferred by the timer) finalizes now.
      assert resolved.status == :completed
      assert resolved.completion_reason == :timer
      assert length(resolved.messages) == 2
    end

    test "a provider reply arriving after grace elapsed is discarded and the learner turn is rolled back" do
      Application.put_env(:backend, :station_duration_ms, 30)
      Application.put_env(:backend, :turn_grace_ms, 50)

      session = Conversation.start()

      assert {:ok, _session, token} =
               StationConversation.begin_turn(session.session_id, %{
                 role: :learner,
                 modality: :text,
                 text: "Pergunta antes do prazo"
               })

      # Let both the deadline and the grace window elapse without resolving.
      Process.sleep(200)

      assert {:ok, forced} = Conversation.fetch(session.session_id)
      assert forced.status == :completed
      assert forced.completion_reason == :timer
      assert forced.messages == []

      # The late provider reply must not be appended.
      assert {:error, :station_time_elapsed} =
               StationConversation.resolve_turn(
                 session.session_id,
                 token,
                 {:ok,
                  %{
                    role: :patient,
                    modality: :text,
                    text: "Resposta tardia demais"
                  }}
               )

      assert {:ok, %{messages: []}} = Conversation.fetch(session.session_id)
    end
  end

  describe "Conversation process restart" do
    test "a Conversation restart loses ephemeral ETS state; existing sessions become not_found" do
      session = Conversation.start()
      assert {:ok, _} = Conversation.fetch(session.session_id)

      pid = Process.whereis(Backend.Stations.Conversation)
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 1_000

      # Wait for the supervisor to restart the GenServer with a fresh ETS table.
      wait_until(fn -> Process.whereis(Backend.Stations.Conversation) not in [nil, pid] end)

      assert Conversation.fetch(session.session_id) == {:error, :not_found}
    end

    test "discard is safe and returns :ok after a process restart" do
      session = Conversation.start()
      pid = Process.whereis(Backend.Stations.Conversation)
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 1_000

      wait_until(fn -> Process.whereis(Backend.Stations.Conversation) not in [nil, pid] end)

      assert Conversation.discard(session.session_id) == :ok
      assert Conversation.discard("arbitrary-id") == :ok
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:backend, key)
  defp restore_env(key, value), do: Application.put_env(:backend, key, value)

  defp wait_until(fun, attempts \\ 50)

  defp wait_until(_fun, 0), do: flunk("condition not met in time")

  defp wait_until(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      wait_until(fun, attempts - 1)
    end
  end
end
