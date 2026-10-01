defmodule Backend.ConversationTest do
  use ExUnit.Case, async: false

  alias Backend.Stations.Conversation
  alias Backend.Conversation, as: LegacyConversation

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

  describe "voice turns and generation identity" do
    test "commit_voice_turn preserves base #118 return shape and advances state atomically" do
      session = Conversation.start()

      assert {:ok, :committed} =
               Conversation.commit_voice_turn(session.session_id, 1, "Olá doutor")

      assert {:ok, 1} = Conversation.active_generation(session.session_id)

      assert {:ok, session_state} = Conversation.fetch(session.session_id)
      assert session_state.last_voice_turn_id == 1
      assert session_state.active_generation_id == 1

      assert [%{role: :learner, modality: :voice, text: "Olá doutor"}] =
               session_state.messages

      assert {:ok, :duplicate} =
               Conversation.commit_voice_turn(session.session_id, 1, "Olá repetido")
    end

    test "begin_voice_turn assigns monotonic session-scoped generation identity" do
      session = Conversation.start()

      assert {:ok, :committed, 1} =
               Conversation.begin_voice_turn(session.session_id, 1, "Olá doutor")

      assert {:ok, 1} = Conversation.active_generation(session.session_id)

      assert {:ok, session_state} = Conversation.fetch(session.session_id)
      assert session_state.last_voice_turn_id == 1
      assert session_state.active_generation_id == 1

      assert [%{role: :learner, modality: :voice, text: "Olá doutor"}] =
               session_state.messages
    end

    test "begin_voice_turn and commit_voice_turn share atomic duplicate checks" do
      session = Conversation.start()

      assert {:ok, :committed, 1} =
               Conversation.begin_voice_turn(session.session_id, 2, "Segunda fala")

      assert {:ok, :duplicate} =
               Conversation.begin_voice_turn(session.session_id, 2, "Segunda fala repetida")

      assert {:ok, :duplicate} =
               Conversation.commit_voice_turn(session.session_id, 1, "Primeira fala atrasada")

      assert {:ok, 1} = Conversation.active_generation(session.session_id)

      assert {:ok, session_state} = Conversation.fetch(session.session_id)
      assert session_state.last_voice_turn_id == 2
      assert length(session_state.messages) == 1
    end

    test "generations are scoped to the individual session" do
      session_a = Conversation.start()
      session_b = Conversation.start()

      assert {:ok, :committed, 1} =
               Conversation.begin_voice_turn(session_a.session_id, 1, "Fala A1")

      assert {:ok, :committed, 1} =
               Conversation.begin_voice_turn(session_b.session_id, 1, "Fala B1")

      assert {:ok, :committed, 2} =
               Conversation.begin_voice_turn(session_a.session_id, 2, "Fala A2")

      assert {:ok, 2} = Conversation.active_generation(session_a.session_id)
      assert {:ok, 1} = Conversation.active_generation(session_b.session_id)
    end
  end

  describe "resolve_patient_reply" do
    test "resolves verified reply for the active generation and clears active generation" do
      session = Conversation.start()

      {:ok, :committed, 1} =
        Conversation.begin_voice_turn(session.session_id, 1, "Onde dói?")

      assert {:ok, updated} =
               Conversation.resolve_patient_reply(
                 session.session_id,
                 1,
                 "Dói no peito, doutor."
               )

      assert {:ok, nil} = Conversation.active_generation(session.session_id)

      assert [
               %{role: :learner, modality: :voice, text: "Onde dói?"},
               %{role: :patient, modality: :voice, text: "Dói no peito, doutor."}
             ] = updated.messages

      # Second resolve of the same generation is rejected as stale
      assert {:error, :stale_generation} =
               Conversation.resolve_patient_reply(
                 session.session_id,
                 1,
                 "Dói no peito, doutor."
               )
    end

    test "rejects invalid reply payloads without crashing GenServer and preserves pending generation" do
      session = Conversation.start()

      {:ok, :committed, 1} =
        Conversation.begin_voice_turn(session.session_id, 1, "Como começou?")

      server_pid = Process.whereis(Conversation)
      assert is_pid(server_pid) and Process.alive?(server_pid)

      invalid_payloads = [
        "",
        "   \t\n  ",
        nil,
        123,
        [:invalid],
        %{role: :learner, text: "Injeção de papel de estudante"},
        %{text: ""},
        %{role: :patient, text: "Mapa arbitrário"}
      ]

      for payload <- invalid_payloads do
        assert {:error, :invalid_reply} =
                 Conversation.resolve_patient_reply(session.session_id, 1, payload)

        assert Process.alive?(server_pid)
        assert {:ok, 1} = Conversation.active_generation(session.session_id)
      end

      # Valid text reply can still be resolved subsequently
      assert {:ok, updated} =
               Conversation.resolve_patient_reply(
                 session.session_id,
                 1,
                 "Começou de repente, doutor."
               )

      assert {:ok, nil} = Conversation.active_generation(session.session_id)
      last_message = List.last(updated.messages)
      assert last_message.role == :patient
      assert last_message.modality == :voice
      assert last_message.text == "Começou de repente, doutor."
    end

    test "refuses stale generations when superseded by a newer accepted turn" do
      session = Conversation.start()

      {:ok, :committed, 1} =
        Conversation.begin_voice_turn(session.session_id, 1, "Primeira pergunta")

      {:ok, :committed, 2} =
        Conversation.begin_voice_turn(session.session_id, 2, "Segunda pergunta interrompendo")

      assert {:ok, 2} = Conversation.active_generation(session.session_id)

      # Attempting to resolve generation 1 fails because generation 2 superseded it
      assert {:error, :stale_generation} =
               Conversation.resolve_patient_reply(
                 session.session_id,
                 1,
                 "Resposta para a primeira pergunta"
               )

      # Generation 2 can still resolve successfully
      assert {:ok, updated} =
               Conversation.resolve_patient_reply(
                 session.session_id,
                 2,
                 "Resposta para a segunda pergunta"
               )

      assert length(updated.messages) == 3

      assert Enum.map(updated.messages, & &1.text) == [
               "Primeira pergunta",
               "Segunda pergunta interrompendo",
               "Resposta para a segunda pergunta"
             ]
    end
  end

  describe "cancellation and race conditions" do
    test "cancel_generation invalidates pending generation and refuses late resolve" do
      session = Conversation.start()

      {:ok, :committed, 1} =
        Conversation.begin_voice_turn(session.session_id, 1, "Pergunta cancelada")

      assert {:ok, :cancelled} = Conversation.cancel_generation(session.session_id, 1)
      assert {:ok, nil} = Conversation.active_generation(session.session_id)

      assert {:error, :stale_generation} =
               Conversation.resolve_patient_reply(
                 session.session_id,
                 1,
                 "Resposta tardia após cancelamento"
               )
    end

    test "cancel_generation protects against cancellation race with newer turn" do
      session = Conversation.start()

      {:ok, :committed, 1} =
        Conversation.begin_voice_turn(session.session_id, 1, "Turno 1")

      {:ok, :committed, 2} =
        Conversation.begin_voice_turn(session.session_id, 2, "Turno 2")

      # Stale cancellation for turn 1 arrives late
      assert {:error, :stale_generation} =
               Conversation.cancel_generation(session.session_id, 1)

      # Active generation 2 remains untouched and can resolve
      assert {:ok, 2} = Conversation.active_generation(session.session_id)

      assert {:ok, _} =
               Conversation.resolve_patient_reply(session.session_id, 2, "Resposta do Turno 2")
    end

    test "cancel_generation without generation_id unconditionally clears active generation" do
      session = Conversation.start()

      {:ok, :committed, 1} =
        Conversation.begin_voice_turn(session.session_id, 1, "Pergunta")

      assert {:ok, :cancelled} = Conversation.cancel_generation(session.session_id)
      assert {:ok, nil} = Conversation.active_generation(session.session_id)
      assert {:ok, :cancelled} = Conversation.cancel_generation(session.session_id)
    end

    test "cancel_voice_turn cancels active generation when expected turn_id matches" do
      session = Conversation.start()

      {:ok, :committed, 1} =
        Conversation.begin_voice_turn(session.session_id, 1, "Pergunta turn 1")

      assert {:ok, :cancelled} = Conversation.cancel_voice_turn(session.session_id, 1)
      assert {:ok, nil} = Conversation.active_generation(session.session_id)

      assert {:error, :stale_generation} =
               Conversation.resolve_patient_reply(
                 session.session_id,
                 1,
                 "Resposta tardia após cancelamento"
               )
    end

    test "cancel_voice_turn protects newer turn against delayed cancellation of earlier turn" do
      session = Conversation.start()

      {:ok, :committed, 1} =
        Conversation.begin_voice_turn(session.session_id, 1, "Turno 1")

      {:ok, :committed, 2} =
        Conversation.begin_voice_turn(session.session_id, 2, "Turno 2")

      # Delayed cancellation for turn 1 arrives late
      assert {:error, :stale_generation} =
               Conversation.cancel_voice_turn(session.session_id, 1)

      # Active turn 2 generation remains active and can resolve
      assert {:ok, 2} = Conversation.active_generation(session.session_id)

      assert {:ok, _} =
               Conversation.resolve_patient_reply(session.session_id, 2, "Resposta do Turno 2")
    end

    test "cancel_voice_turn returns :stale_generation when turn has already resolved or session is idle" do
      session = Conversation.start()

      # Idle session: cancel by turn_id returns stale_generation
      assert {:error, :stale_generation} =
               Conversation.cancel_voice_turn(session.session_id, 1)

      {:ok, :committed, 1} =
        Conversation.begin_voice_turn(session.session_id, 1, "Turno 1")

      {:ok, _} =
        Conversation.resolve_patient_reply(session.session_id, 1, "Resposta 1")

      # Already resolved: late cancel returns stale_generation
      assert {:error, :stale_generation} =
               Conversation.cancel_voice_turn(session.session_id, 1)
    end

    test "cancel_voice_turn supports criteria keywords and maps" do
      session = Conversation.start()

      {:ok, :committed, 1} =
        Conversation.begin_voice_turn(session.session_id, 1, "Turno 1")

      # Cancel with matching keyword criteria
      assert {:ok, :cancelled} =
               Conversation.cancel_voice_turn(session.session_id, turn_id: 1, generation_id: 1)

      assert {:ok, nil} = Conversation.active_generation(session.session_id)
    end

    test "duplicate turn_id does not disrupt active voice turn or generation identity" do
      session = Conversation.start()

      {:ok, :committed, 1} =
        Conversation.begin_voice_turn(session.session_id, 1, "Turno 1")

      # Duplicate turn arrival
      assert {:ok, :duplicate} =
               Conversation.begin_voice_turn(session.session_id, 1, "Turno 1 repetido")

      # Older turn arrival
      assert {:ok, :duplicate} =
               Conversation.begin_voice_turn(session.session_id, 0, "Turno 0 antigo")

      # Active generation is still 1 and resolves normally
      assert {:ok, 1} = Conversation.active_generation(session.session_id)

      assert {:ok, updated} =
               Conversation.resolve_patient_reply(session.session_id, 1, "Resposta válida")

      assert length(updated.messages) == 2
    end
  end

  describe "deterministic append order and text interleaving" do
    test "preserves deterministic append order across voice and text turns" do
      session = Conversation.start()

      {:ok, _} =
        Conversation.append_message(session.session_id, %{
          role: :learner,
          modality: :text,
          text: "Mensagem de texto inicial"
        })

      {:ok, :committed, 1} =
        Conversation.begin_voice_turn(session.session_id, 1, "Voz 1")

      {:ok, _} =
        Conversation.resolve_patient_reply(session.session_id, 1, "Resposta voz 1")

      {:ok, _} =
        Conversation.append_message(session.session_id, %{
          role: :learner,
          modality: :text,
          text: "Mensagem de texto intermediária"
        })

      {:ok, :committed, 2} =
        Conversation.begin_voice_turn(session.session_id, 2, "Voz 2")

      {:ok, updated} =
        Conversation.resolve_patient_reply(session.session_id, 2, "Resposta voz 2")

      assert Enum.map(updated.messages, &{&1.role, &1.modality, &1.text}) == [
               {:learner, :text, "Mensagem de texto inicial"},
               {:learner, :voice, "Voz 1"},
               {:patient, :voice, "Resposta voz 1"},
               {:learner, :text, "Mensagem de texto intermediária"},
               {:learner, :voice, "Voz 2"},
               {:patient, :voice, "Resposta voz 2"}
             ]
    end
  end

  describe "lifecycle boundaries: completion, expiry, discard" do
    test "complete locks session and refuses voice turns, replies, cancellations, and generation queries" do
      session = Conversation.start()

      {:ok, :committed, 1} =
        Conversation.begin_voice_turn(session.session_id, 1, "Fala antes de completar")

      {:ok, _} = Conversation.complete(session.session_id, :user)

      assert {:error, :completed} =
               Conversation.begin_voice_turn(session.session_id, 2, "Nova fala")

      assert {:error, :completed} =
               Conversation.commit_voice_turn(session.session_id, 2, "Nova fala legacy")

      assert {:error, :completed} =
               Conversation.resolve_patient_reply(session.session_id, 1, "Resposta tardia")

      assert {:error, :completed} =
               Conversation.cancel_generation(session.session_id, 1)

      assert {:error, :completed} =
               Conversation.cancel_voice_turn(session.session_id, 1)

      assert {:error, :completed} =
               Conversation.active_generation(session.session_id)
    end

    test "complete race refuses resolve_patient_reply even with invalid payload" do
      session = Conversation.start()

      {:ok, :committed, 1} =
        Conversation.begin_voice_turn(session.session_id, 1, "Pergunta")

      {:ok, _} = Conversation.complete(session.session_id, :timeout)

      assert {:error, :completed} =
               Conversation.resolve_patient_reply(session.session_id, 1, "")

      assert {:error, :completed} =
               Conversation.resolve_patient_reply(session.session_id, 1, "Texto válido")
    end

    test "expiry refuses voice turns, replies, and cancellations" do
      original_timeout = Application.get_env(:backend, :conversation_timeout_ms)
      Application.put_env(:backend, :conversation_timeout_ms, 0)

      on_exit(fn ->
        if is_nil(original_timeout) do
          Application.delete_env(:backend, :conversation_timeout_ms)
        else
          Application.put_env(:backend, :conversation_timeout_ms, original_timeout)
        end
      end)

      # Each expired session returns :expired on first access and removes from ETS
      session1 = Conversation.start()

      assert {:error, :expired} =
               Conversation.begin_voice_turn(session1.session_id, 1, "Fala")

      session1b = Conversation.start()

      assert {:error, :expired} =
               Conversation.commit_voice_turn(session1b.session_id, 1, "Fala")

      session2 = Conversation.start()

      assert {:error, :expired} =
               Conversation.resolve_patient_reply(session2.session_id, 1, "Resposta")

      session3 = Conversation.start()

      assert {:error, :expired} =
               Conversation.cancel_generation(session3.session_id, 1)

      session3b = Conversation.start()

      assert {:error, :expired} =
               Conversation.cancel_voice_turn(session3b.session_id, 1)

      session4 = Conversation.start()

      assert {:error, :expired} =
               Conversation.active_generation(session4.session_id)
    end

    test "discard removes session and refuses voice operations with :not_found" do
      session = Conversation.start()

      {:ok, :committed, 1} =
        Conversation.begin_voice_turn(session.session_id, 1, "Fala")

      assert :ok = Conversation.discard(session.session_id)

      assert {:error, :not_found} =
               Conversation.begin_voice_turn(session.session_id, 2, "Fala 2")

      assert {:error, :not_found} =
               Conversation.commit_voice_turn(session.session_id, 2, "Fala 2 legacy")

      assert {:error, :not_found} =
               Conversation.resolve_patient_reply(session.session_id, 1, "Resposta")

      assert {:error, :not_found} =
               Conversation.cancel_generation(session.session_id, 1)

      assert {:error, :not_found} =
               Conversation.active_generation(session.session_id)
    end
  end

  describe "evaluation-visible role-labelled transcript" do
    test "transcript maintains evaluator-compatible role labelling and clean history" do
      session = Conversation.start()

      {:ok, :committed, 1} =
        Conversation.begin_voice_turn(session.session_id, 1, "Doutor, qual o diagnóstico?")

      {:ok, _} =
        Conversation.resolve_patient_reply(
          session.session_id,
          1,
          "Ainda estamos investigando."
        )

      # A superseded turn where patient reply is refused
      {:ok, :committed, 2} =
        Conversation.begin_voice_turn(session.session_id, 2, "Pergunta ignorada")

      {:ok, :committed, 3} =
        Conversation.begin_voice_turn(session.session_id, 3, "Pergunta definitiva")

      {:ok, _} =
        Conversation.resolve_patient_reply(session.session_id, 3, "Resposta definitiva")

      {:ok, fetched} = Conversation.fetch(session.session_id)

      # Evaluator extracts messages and normalizes roles: 3 learner turns + 2 patient replies
      assert length(fetched.messages) == 5

      roles = Enum.map(fetched.messages, & &1.role)
      assert roles == [:learner, :patient, :learner, :learner, :patient]

      # Verify each message has required attributes for evaluation
      for msg <- fetched.messages do
        assert msg.role in [:learner, :patient]
        assert is_binary(msg.text) and msg.text != ""
        assert msg.modality in [:voice, :text]
        assert %DateTime{} = msg.at
      end
    end

    test "legacy Backend.Conversation alias preserves base delegates and avoids leaking new surface" do
      session = LegacyConversation.start()
      assert {:ok, _} = LegacyConversation.fetch(session.session_id)

      assert {:ok, updated} =
               LegacyConversation.append_message(session.session_id, %{
                 role: :learner,
                 modality: :text,
                 text: "Texto via legado"
               })

      assert length(updated.messages) == 1
      assert {:ok, _} = LegacyConversation.complete(session.session_id, :normal)
      assert :ok = LegacyConversation.discard(session.session_id)

      # Ensure new voice generation APIs are not exposed on the legacy alias
      refute function_exported?(LegacyConversation, :commit_voice_turn, 3)
      refute function_exported?(LegacyConversation, :resolve_patient_reply, 3)
      refute function_exported?(LegacyConversation, :cancel_generation, 1)
      refute function_exported?(LegacyConversation, :cancel_generation, 2)
      refute function_exported?(LegacyConversation, :active_generation, 1)
    end
  end
end
