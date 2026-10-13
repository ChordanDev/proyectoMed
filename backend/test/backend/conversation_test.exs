defmodule Backend.ConversationTest do
  use ExUnit.Case, async: false

  alias Backend.Conversation, as: LegacyConversation
  alias Backend.Stations.Conversation
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

  describe "voice turns and generation identity" do
    test "failed outcome is bounded to the latest accepted turn and preserves legacy duplicates" do
      session = Conversation.start()
      assert {:ok, :committed, 1} = Conversation.begin_voice_turn(session.session_id, 4, "First")

      assert {:ok, :failed} =
               Conversation.fail_generation(session.session_id, 1, :station_ai_unavailable)

      assert {:error, :station_ai_unavailable} =
               Conversation.begin_voice_turn(session.session_id, 4, "First")

      assert {:ok, :duplicate} = Conversation.commit_voice_turn(session.session_id, 4, "First")
      assert {:ok, :duplicate} = Conversation.begin_voice_turn(session.session_id, 3, "Older")
      assert {:ok, :committed, 2} = Conversation.begin_voice_turn(session.session_id, 5, "Newer")
      assert {:ok, stored} = Conversation.fetch(session.session_id)
      assert stored.failed_voice_turn == nil

      assert {:error, :stale_generation} =
               Conversation.fail_generation(session.session_id, 1, :station_ai_unavailable)

      assert {:ok, 2} = Conversation.active_generation(session.session_id)
      assert {:ok, :duplicate} = Conversation.begin_voice_turn(session.session_id, 4, "First")
      assert {:ok, _} = Conversation.resolve_patient_reply(session.session_id, 2, "Patient reply")
      assert {:ok, :duplicate} = Conversation.begin_voice_turn(session.session_id, 5, "Newer")
    end

    test "completion clears failure outcome and expiry or discard removes the session" do
      for boundary <- [:completed, :expired, :discarded] do
        session = Conversation.start()

        assert {:ok, :committed, 1} =
                 Conversation.begin_voice_turn(session.session_id, 1, "Question")

        assert {:ok, :failed} =
                 Conversation.fail_generation(session.session_id, 1, :station_ai_unavailable)

        case boundary do
          :completed ->
            assert {:ok, completed} = Conversation.complete(session.session_id, :user)
            assert completed.failed_voice_turn == nil

            assert {:error, :completed} =
                     Conversation.begin_voice_turn(session.session_id, 1, "Question")

            assert {:error, :completed} =
                     Conversation.fail_generation(session.session_id, 1, :station_ai_unavailable)

          :expired ->
            {:ok, stored} = Conversation.fetch(session.session_id)

            :ets.insert(
              Conversation,
              {session.session_id, %{stored | expires_at: session.started_at}}
            )

            assert {:error, :expired} =
                     Conversation.begin_voice_turn(session.session_id, 1, "Question")

            assert {:error, :not_found} = Conversation.fetch(session.session_id)

          :discarded ->
            assert :ok = Conversation.discard(session.session_id)

            assert {:error, :not_found} =
                     Conversation.begin_voice_turn(session.session_id, 1, "Question")
        end
      end
    end

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

  describe "voice generation authority after message rollback" do
    for entrypoint <- [:commit_voice_turn, :begin_voice_turn] do
      test "#{entrypoint} origin removal invalidates its pending generation" do
        session = Conversation.start()
        result = apply(Conversation, unquote(entrypoint), [session.session_id, 1, "probe"])
        assert result in [{:ok, :committed}, {:ok, :committed, 1}]
        assert {:ok, 1} = Conversation.active_generation(session.session_id)

        assert {:ok, popped} =
                 Conversation.pop_last_message(session.session_id, %{
                   role: :learner,
                   text: "probe"
                 })

        assert popped.messages == []
        assert popped.active_generation_id == nil
        assert popped.active_voice_turn_id == nil
        assert popped.active_generation_message_index == nil

        assert {:error, :stale_generation} =
                 Conversation.resolve_patient_reply(session.session_id, 1, "orphan")

        assert {:ok, ^popped} = Conversation.fetch(session.session_id)
        assert {:ok, nil} = Conversation.active_generation(session.session_id)
        assert popped.last_voice_turn_id == 1
        assert popped.next_generation_id == 2
        assert {:ok, :duplicate} = Conversation.begin_voice_turn(session.session_id, 1, "retry")
        assert {:ok, :committed, 2} = Conversation.begin_voice_turn(session.session_id, 2, "next")
      end
    end
  end

  describe "rollback preserves unrelated generation authority" do
    for modality <- [:text, :voice] do
      test "popping an unrelated same-text #{modality} message preserves the pending voice turn" do
        session = Conversation.start()

        assert {:ok, :committed, 1} =
                 Conversation.begin_voice_turn(session.session_id, 1, "probe")

        assert {:ok, pending} = Conversation.fetch(session.session_id)

        assert {:ok, _} =
                 Conversation.append_message(session.session_id, %{
                   role: :learner,
                   modality: unquote(modality),
                   text: "probe"
                 })

        assert {:ok, ^pending} =
                 Conversation.pop_last_message(session.session_id, %{
                   role: :learner,
                   text: "probe"
                 })

        assert {:ok, 1} = Conversation.active_generation(session.session_id)
        assert {:ok, _} = Conversation.resolve_patient_reply(session.session_id, 1, "reply")
      end
    end

    test "failed pops leave the full empty or pending session unchanged" do
      session = Conversation.start()
      assert {:error, :no_match} = Conversation.pop_last_message(session.session_id)
      assert {:ok, ^session} = Conversation.fetch(session.session_id)
      assert {:ok, :committed, 1} = Conversation.begin_voice_turn(session.session_id, 1, "probe")
      assert {:ok, pending} = Conversation.fetch(session.session_id)

      for expected <- [%{role: :patient, text: "probe"}, %{role: :learner, text: "other"}] do
        assert {:error, :no_match} = Conversation.pop_last_message(session.session_id, expected)
        assert {:ok, ^pending} = Conversation.fetch(session.session_id)
      end

      assert {:ok, _} = Conversation.resolve_patient_reply(session.session_id, 1, "reply")
    end

    test "same-text text rollback removing a newer voice origin leaves no reply authority" do
      session = Conversation.start()
      text_message = %{role: :learner, modality: :text, text: "probe"}
      assert {:ok, text_only} = Conversation.append_message(session.session_id, text_message)
      assert {:ok, :committed, 1} = Conversation.begin_voice_turn(session.session_id, 1, "probe")

      # The existing rollback matcher intentionally remains role/text based.
      assert {:ok, popped} = Conversation.pop_last_message(session.session_id, text_message)
      assert popped.messages == text_only.messages
      assert {:ok, nil} = Conversation.active_generation(session.session_id)

      assert {:error, :stale_generation} =
               Conversation.resolve_patient_reply(session.session_id, 1, "orphan")

      assert {:ok, ^popped} = Conversation.fetch(session.session_id)
    end

    test "replacement does not restore superseded authority when voice origins are popped" do
      session = Conversation.start()
      assert {:ok, :committed, 1} = Conversation.begin_voice_turn(session.session_id, 1, "probe")
      assert {:ok, :committed, 2} = Conversation.begin_voice_turn(session.session_id, 2, "probe")
      assert {:ok, replacement} = Conversation.fetch(session.session_id)

      assert {:error, :stale_generation} =
               Conversation.resolve_patient_reply(session.session_id, 1, "old reply")

      assert {:ok, ^replacement} = Conversation.fetch(session.session_id)
      assert {:ok, _} = Conversation.pop_last_message(session.session_id)
      assert {:ok, nil} = Conversation.active_generation(session.session_id)
      assert {:ok, empty} = Conversation.pop_last_message(session.session_id)
      assert empty.messages == []

      for generation_id <- [1, 2] do
        assert {:error, :stale_generation} =
                 Conversation.resolve_patient_reply(session.session_id, generation_id, "orphan")

        assert {:ok, ^empty} = Conversation.fetch(session.session_id)
      end

      assert {:ok, :committed, 3} = Conversation.begin_voice_turn(session.session_id, 3, "probe")
      assert {:ok, _} = Conversation.resolve_patient_reply(session.session_id, 3, "new reply")
    end

    test "popping a superseded message copied after replacement cannot cancel the new generation" do
      session = Conversation.start()
      assert {:ok, :committed, 1} = Conversation.begin_voice_turn(session.session_id, 1, "probe")
      assert {:ok, old} = Conversation.fetch(session.session_id)
      assert {:ok, :committed, 2} = Conversation.begin_voice_turn(session.session_id, 2, "probe")
      assert {:ok, replacement} = Conversation.fetch(session.session_id)
      assert {:ok, _} = Conversation.append_message(session.session_id, hd(old.messages))
      assert {:ok, ^replacement} = Conversation.pop_last_message(session.session_id)
      assert {:ok, 2} = Conversation.active_generation(session.session_id)
      assert {:ok, _} = Conversation.resolve_patient_reply(session.session_id, 2, "new reply")
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

    test "idle turn cancellation fences admission and retries while later turns remain eligible" do
      session = Conversation.start()

      # No matching active generation still returns stale, but fences admission.
      assert {:error, :stale_generation} =
               Conversation.cancel_voice_turn(session.session_id, 1)

      for _attempt <- 1..2 do
        assert {:error, :stale_generation} =
                 Conversation.begin_voice_turn(session.session_id, 1, "Cancelled question")

        assert {:error, :stale_generation} =
                 Conversation.commit_voice_turn(
                   session.session_id,
                   1,
                   "Cancelled legacy question"
                 )
      end

      assert {:error, :stale_generation} =
               Conversation.resolve_patient_reply(session.session_id, 1, "Late reply")

      assert {:ok, %{messages: [], last_voice_turn_id: 0}} =
               Conversation.fetch(session.session_id)

      {:ok, :committed, 1} =
        Conversation.begin_voice_turn(session.session_id, 2, "Later question")

      {:ok, _} =
        Conversation.resolve_patient_reply(session.session_id, 1, "Resposta 1")

      # Already resolved: late cancel returns stale_generation
      assert {:error, :stale_generation} =
               Conversation.cancel_voice_turn(session.session_id, 2)

      assert {:ok, :duplicate} =
               Conversation.begin_voice_turn(session.session_id, 2, "Repeated admitted question")
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

    test "admission fences protect independent newer work and generation mismatch has no side effects" do
      session = Conversation.start()

      assert {:ok, :committed, 1} =
               Conversation.begin_voice_turn(session.session_id, 3, "Independent question")

      assert {:error, :stale_generation} =
               Conversation.cancel_voice_turn(session.session_id, turn_id: 1)

      assert {:error, :stale_generation} =
               Conversation.cancel_voice_turn(session.session_id, turn_id: 4, generation_id: 999)

      assert {:ok, 1} = Conversation.active_generation(session.session_id)

      assert {:ok, _} =
               Conversation.resolve_patient_reply(session.session_id, 1, "Independent reply")

      assert {:ok, :committed, 2} =
               Conversation.begin_voice_turn(session.session_id, 4, "Next independent question")

      idle = Conversation.start()
      assert {:error, :stale_generation} = Conversation.cancel_generation(idle.session_id, 999)
      assert {:ok, :cancelled} = Conversation.cancel_generation(idle.session_id)

      assert {:ok, :committed, 1} =
               Conversation.begin_voice_turn(idle.session_id, 1, "Generation-only compatibility")
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
