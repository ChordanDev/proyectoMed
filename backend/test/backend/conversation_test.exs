defmodule Backend.ConversationTest do
  use ExUnit.Case, async: false

  alias Backend.Conversation

  test "start creates an active session with a thirty-minute safety timeout and default station identity" do
    session = Conversation.start()

    assert is_binary(session.session_id)
    assert session.station_id == "chest-pain-initial-assessment"
    assert session.station_version == "1.0.0"
    assert session.audio_consent == false
    assert %DateTime{} = session.started_at
    assert %DateTime{} = session.expires_at
    assert DateTime.diff(session.expires_at, session.started_at, :second) == 30 * 60
    assert session.messages == []
    assert session.status == :active
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
end
