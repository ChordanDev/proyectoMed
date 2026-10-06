defmodule Backend.StationsTest do
  use ExUnit.Case, async: false

  alias Backend.Stations
  alias Backend.Stations.Conversation

  defmodule TestSuccessAdapter do
    @behaviour Backend.Stations.StationAI
    @impl true
    def next_reply(_package, _context) do
      {:ok, %{text: "Estou sentindo uma forte dor no peito há 2 horas.", used_facts: []}}
    end
  end

  defmodule TestFailureAdapter do
    @behaviour Backend.Stations.StationAI
    @impl true
    def next_reply(_package, _context) do
      {:error, :service_unavailable}
    end
  end

  defmodule TestConcurrentCompleteAdapter do
    @behaviour Backend.Stations.StationAI
    @impl true
    def next_reply(_package, _context) do
      session_id = Process.get(:test_concurrent_session_id)
      if session_id, do: Backend.Stations.complete_session(session_id, :user)
      {:ok, %{text: "Resposta tardia", used_facts: []}}
    end
  end

  defmodule TestRefusalAdapter do
    @behaviour Backend.Stations.StationAI
    @impl true
    def next_reply(_package, _context) do
      {:ok, %{text: "Não tenho essa informação", used_facts: []}}
    end
  end

  defmodule TestFabricatedClinicalAdapter do
    @behaviour Backend.Stations.StationAI
    @impl true
    def next_reply(_package, _context) do
      {:ok, %{text: "Estou sentindo uma queimação forte e tomei omeprazol de manhã cedo."}}
    end
  end

  defmodule TestFactSubstringWithFabricatedAdapter do
    @behaviour Backend.Stations.StationAI
    @impl true
    def next_reply(_package, _context) do
      {:ok,
       %{
         text: "A dor começou durante uma caminhada e também sinto dor intensa no braço esquerdo."
       }}
    end
  end

  defmodule TestRevealableFactsAdapter do
    @behaviour Backend.Stations.StationAI
    @impl true
    def next_reply(_package, _context) do
      {:ok, %{text: "A dor começou durante uma caminhada."}}
    end
  end

  defmodule TestFactWithoutPeriodAdapter do
    @behaviour Backend.Stations.StationAI
    @impl true
    def next_reply(_package, _context) do
      {:ok, %{text: "A dor começou durante uma caminhada"}}
    end
  end

  defmodule TestSlowBarrierAdapter do
    @behaviour Backend.Stations.StationAI
    @impl true
    def next_reply(_package, context) do
      caller =
        Process.get(:voice_turn_test_pid) ||
          Application.get_env(:backend, :voice_turn_test_pid)

      if caller, do: send(caller, {:adapter_called, context})

      receive do
        {:resume_adapter, reply_text} ->
          {:ok, %{text: reply_text, used_facts: []}}
      after
        5000 ->
          {:ok, %{text: "Tempo esgotado no adaptador", used_facts: []}}
      end
    end
  end

  setup do
    prev_adapter = Application.get_env(:backend, :station_ai_adapter)
    Application.put_env(:backend, :station_ai_adapter, TestSuccessAdapter)

    on_exit(fn ->
      if prev_adapter do
        Application.put_env(:backend, :station_ai_adapter, prev_adapter)
      else
        Application.delete_env(:backend, :station_ai_adapter)
      end

      Application.delete_env(:backend, :voice_turn_test_pid)
    end)

    :ok
  end

  describe "package & metadata" do
    test "get_active_station/0 returns metadata map" do
      station = Stations.get_active_station()

      assert %{
               "station_id" => "chest-pain-initial-assessment",
               "version" => "1.0.0",
               "language" => "pt-BR",
               "display_title" => "Avaliação inicial de dor torácica"
             } = station
    end

    test "get_active_package/0 returns full package" do
      package = Stations.get_active_package()
      assert is_map(package)
      assert package["station_id"] == "chest-pain-initial-assessment"
      assert is_list(package["rubric"])
    end

    test "active_version/0 returns version string" do
      assert Stations.active_version() == "1.0.0"
    end
  end

  describe "session lifecycle" do
    test "create_session/1 creates an ephemeral active session with defaults" do
      session = Stations.create_session(%{audio_consent: true})

      assert is_binary(session.session_id)
      assert session.station_id == "chest-pain-initial-assessment"
      assert session.station_version == "1.0.0"
      assert session.audio_consent == true
      assert session.status == :active
      assert session.messages == []

      assert {:ok, fetched} = Stations.get_session(session.session_id)
      assert fetched.session_id == session.session_id
    end

    test "create_session/1 accepts keyword list and start_session/1 alias" do
      session = Stations.start_session(audio_consent: false)
      assert session.audio_consent == false
      assert {:ok, _} = Stations.fetch_session(session.session_id)
    end

    test "get_session/1 returns not_found for unknown session" do
      assert Stations.get_session("non-existent-id") == {:error, :not_found}
    end

    test "get_session/1 returns expired for timed out session" do
      prev_timeout = Application.get_env(:backend, :conversation_timeout_ms)
      Application.put_env(:backend, :conversation_timeout_ms, 0)

      on_exit(fn ->
        if prev_timeout do
          Application.put_env(:backend, :conversation_timeout_ms, prev_timeout)
        else
          Application.delete_env(:backend, :conversation_timeout_ms)
        end
      end)

      session = Stations.create_session(%{audio_consent: false})
      assert Stations.get_session(session.session_id) == {:error, :expired}
    end

    test "complete_session/2 and finish_session/2 mark session completed" do
      session = Stations.create_session(%{audio_consent: true})
      assert {:ok, completed} = Stations.complete_session(session.session_id, :user)
      assert completed.status == :completed
      assert completed.completion_reason == :user
      assert %DateTime{} = completed.completed_at

      # Completing again returns the same completed session
      assert {:ok, completed_again} = Stations.finish_session(session.session_id, :timer)
      assert completed_again.completed_at == completed.completed_at
    end

    test "complete_session/2 returns error on unknown session" do
      assert Stations.complete_session("non-existent", :user) == {:error, :not_found}
    end
  end

  describe "conversation & messaging" do
    test "create_message/2 appends learner message and patient reply" do
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, result} =
               Stations.create_message(session.session_id, %{
                 role: "learner",
                 modality: "text",
                 text: "Olá, o que você está sentindo?"
               })

      assert result.reply_text == "Estou sentindo uma forte dor no peito há 2 horas."
      assert result.reply_audio_url == nil

      {:ok, updated_session} = Stations.get_session(session.session_id)
      assert length(updated_session.messages) == 2
      [msg1, msg2] = updated_session.messages
      assert msg1.role == :learner
      assert msg1.text == "Olá, o que você está sentindo?"
      assert msg2.role == :patient
      assert msg2.text == "Estou sentindo uma forte dor no peito há 2 horas."
    end

    test "post_message/2 works as alias" do
      session = Stations.create_session(%{audio_consent: false})

      assert {:ok, result} =
               Stations.post_message(session.session_id, %{
                 role: :learner,
                 modality: :voice,
                 text: "Bom dia."
               })

      assert is_binary(result.reply_text)
    end

    test "create_message/2 returns error for completed session" do
      session = Stations.create_session(%{audio_consent: true})
      {:ok, _} = Stations.complete_session(session.session_id, :user)

      assert Stations.create_message(session.session_id, %{
               role: "learner",
               modality: "text",
               text: "Olá"
             }) == {:error, :completed}
    end

    test "create_message/2 returns error for unknown or expired session" do
      assert Stations.create_message("unknown", %{role: "learner", modality: "text", text: "Olá"}) ==
               {:error, :not_found}
    end

    test "create_message/2 returns station_ai_unavailable and rolls back learner message when adapter fails" do
      Application.put_env(:backend, :station_ai_adapter, TestFailureAdapter)
      session = Stations.create_session(%{audio_consent: true})

      assert Stations.create_message(session.session_id, %{
               role: "learner",
               modality: "text",
               text: "Olá"
             }) == {:error, :station_ai_unavailable}

      {:ok, session_after_failure} = Stations.get_session(session.session_id)
      assert session_after_failure.messages == []

      # Retry with recovered adapter succeeds without duplicating learner messages
      Application.put_env(:backend, :station_ai_adapter, TestSuccessAdapter)

      assert {:ok, result} =
               Stations.create_message(session.session_id, %{
                 role: "learner",
                 modality: "text",
                 text: "Olá"
               })

      assert is_binary(result.reply_text)
      {:ok, session_after_retry} = Stations.get_session(session.session_id)
      assert length(session_after_retry.messages) == 2
      assert hd(session_after_retry.messages).text == "Olá"
      assert List.last(session_after_retry.messages).text == result.reply_text
    end

    test "create_message/2 handles race when session completes while generating reply" do
      Application.put_env(:backend, :station_ai_adapter, TestConcurrentCompleteAdapter)
      session = Stations.create_session(%{audio_consent: true})
      Process.put(:test_concurrent_session_id, session.session_id)

      assert {:ok, %{reply_text: "Resposta tardia"}} =
               Stations.create_message(session.session_id, %{
                 role: "learner",
                 modality: "text",
                 text: "Olá"
               })

      assert {:ok, completed_session} = Stations.get_session(session.session_id)
      assert completed_session.status == :completed
      assert length(completed_session.messages) == 1
    end
  end

  describe "result evaluation" do
    test "get_session_result/1 returns error for active session" do
      session = Stations.create_session(%{audio_consent: true})
      assert Stations.get_session_result(session.session_id) == {:error, :session_not_finished}
    end

    test "get_session_result/1 returns evaluation for completed session" do
      session = Stations.create_session(%{audio_consent: true})

      {:ok, _} =
        Stations.create_message(session.session_id, %{
          role: "learner",
          modality: "text",
          text: "Quando começou a dor no peito?"
        })

      {:ok, _} = Stations.complete_session(session.session_id, :user)

      assert {:ok, result} = Stations.get_session_result(session.session_id)
      assert result.session_id == session.session_id
      assert result.status == "completed"
      assert is_list(result.criteria)
      assert length(result.criteria) > 0

      first_criterion = hd(result.criteria)
      assert Map.has_key?(first_criterion, :id)
      assert Map.has_key?(first_criterion, :status)
      assert Map.has_key?(first_criterion, :evidence)
      assert Map.has_key?(first_criterion, :recommendation)
    end

    test "evaluate_session/1 works as alias" do
      session = Stations.create_session(%{audio_consent: true})
      {:ok, _} = Stations.complete_session(session.session_id, :user)
      assert {:ok, _} = Stations.evaluate_session(session.session_id)
    end

    test "get_session_result/1 returns not_found on unknown session" do
      assert Stations.get_session_result("unknown-id") == {:error, :not_found}
    end
  end

  describe "extension points" do
    test "discard_session/1 idempotently removes session" do
      session = Stations.create_session(%{audio_consent: true})
      assert {:ok, _} = Stations.get_session(session.session_id)

      assert Stations.discard_session(session.session_id) == :ok
      assert Stations.get_session(session.session_id) == {:error, :not_found}

      # Idempotent: repeated discard is safe
      assert Stations.discard_session(session.session_id) == :ok
    end

    test "check_session_deadline/1 returns within_deadline for active session" do
      session = Stations.create_session(%{audio_consent: true})
      assert Stations.check_session_deadline(session.session_id) == {:ok, :within_deadline}

      {:ok, _} = Stations.complete_session(session.session_id, :user)

      assert Stations.check_session_deadline(session.session_id) ==
               {:error, :session_time_elapsed}
    end

    test "request_impresso/2 returns not_implemented" do
      assert Stations.request_impresso("session-id", %{"type" => "ecg"}) ==
               {:error, :not_implemented}
    end

    test "verify_patient_reply/3 passes through reply" do
      pkg = Stations.get_active_package()
      reply = %{text: "dor forte"}
      assert Stations.verify_patient_reply(pkg, reply) == {:ok, reply}
    end
  end

  describe "speech operations" do
    test "allowed_tts_voices/0 returns voices" do
      voices = Stations.allowed_tts_voices()
      assert is_list(voices)
      assert "alloy" in voices
    end
  end

  describe "voice sessions" do
    setup do
      Application.put_env(:backend, :livekit_url, "wss://revalida.livekit.cloud")
      Application.put_env(:backend, :livekit_api_key, "test-api-key")
      Application.put_env(:backend, :livekit_api_secret, "test-api-secret")

      on_exit(fn ->
        Application.delete_env(:backend, :livekit_url)
        Application.delete_env(:backend, :livekit_api_key)
        Application.delete_env(:backend, :livekit_api_secret)
        Application.delete_env(:backend, :livekit_rate_limit_max)
        Application.delete_env(:backend, :conversation_timeout_ms)
      end)

      :ok
    end

    test "create_voice_session/2 issues a token for an active, consented session" do
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, %{url: url, token: token, room: room, identity: identity, expires_at: exp}} =
               Stations.create_voice_session(session.session_id)

      assert url == "wss://revalida.livekit.cloud"
      assert is_binary(token)
      assert room == "station-session-" <> session.session_id
      assert identity == "learner-" <> session.session_id
      assert %DateTime{} = exp
    end

    test "create_voice_session/2 returns :not_found for an unknown session" do
      assert Stations.create_voice_session("unknown-id") == {:error, :not_found}
    end

    test "create_voice_session/2 returns :expired for an expired session" do
      Application.put_env(:backend, :conversation_timeout_ms, 0)
      session = Stations.create_session(%{audio_consent: true})

      assert Stations.create_voice_session(session.session_id) == {:error, :expired}
    end

    test "create_voice_session/2 returns :completed for a completed session" do
      session = Stations.create_session(%{audio_consent: true})
      {:ok, _} = Stations.complete_session(session.session_id, :user)

      assert Stations.create_voice_session(session.session_id) == {:error, :completed}
    end

    test "create_voice_session/2 returns :no_consent without audio consent" do
      session = Stations.create_session(%{audio_consent: false})

      assert Stations.create_voice_session(session.session_id) == {:error, :no_consent}
    end

    test "create_voice_session/2 returns :voice_unavailable when LiveKit is not configured" do
      Application.delete_env(:backend, :livekit_url)
      session = Stations.create_session(%{audio_consent: true})

      assert Stations.create_voice_session(session.session_id) == {:error, :voice_unavailable}
    end

    test "create_voice_session/2 rate-limits repeated issuance for the same session" do
      Application.put_env(:backend, :livekit_rate_limit_max, 2)
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, _} = Stations.create_voice_session(session.session_id)
      assert {:ok, _} = Stations.create_voice_session(session.session_id)
      assert Stations.create_voice_session(session.session_id) == {:error, :rate_limited}
    end

    test "create_voice_session/2 rate limit does not affect other sessions" do
      Application.put_env(:backend, :livekit_rate_limit_max, 1)
      session_a = Stations.create_session(%{audio_consent: true})
      session_b = Stations.create_session(%{audio_consent: true})

      assert {:ok, _} = Stations.create_voice_session(session_a.session_id)
      assert Stations.create_voice_session(session_a.session_id) == {:error, :rate_limited}
      assert {:ok, _} = Stations.create_voice_session(session_b.session_id)
    end

    test "create_voice_session/2 caps the token expiry to the session's expiry" do
      Application.put_env(:backend, :conversation_timeout_ms, 5_000)
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, %{expires_at: exp}} = Stations.create_voice_session(session.session_id)
      assert DateTime.compare(exp, session.expires_at) != :gt
      assert_in_delta DateTime.to_unix(exp), DateTime.to_unix(session.expires_at), 1
    end
  end

  describe "voice room cleanup" do
    defmodule RecordingRoomService do
      @behaviour Backend.Stations.LiveKit.RoomService

      @impl true
      def delete_room(room) do
        send(Backend.StationsTest.cleanup_test_pid(), {:deleted_room, room})
        :ok
      end

      @impl true
      def list_rooms, do: {:ok, []}
    end

    defmodule FailingRoomService do
      @behaviour Backend.Stations.LiveKit.RoomService

      @impl true
      def delete_room(_room), do: {:error, :livekit_unavailable}

      @impl true
      def list_rooms, do: {:ok, []}
    end

    def cleanup_test_pid, do: Process.get(:stations_cleanup_test_pid)

    setup do
      Application.put_env(:backend, :livekit_url, "wss://revalida.livekit.cloud")
      Application.put_env(:backend, :livekit_api_key, "test-api-key")
      Application.put_env(:backend, :livekit_api_secret, "test-api-secret")
      Process.put(:stations_cleanup_test_pid, self())

      on_exit(fn ->
        Application.delete_env(:backend, :livekit_url)
        Application.delete_env(:backend, :livekit_api_key)
        Application.delete_env(:backend, :livekit_api_secret)
        Application.delete_env(:backend, :livekit_room_service)
      end)

      :ok
    end

    test "complete_session/2 deletes the session's LiveKit room" do
      Application.put_env(:backend, :livekit_room_service, RecordingRoomService)
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, _} = Stations.complete_session(session.session_id, :user)
      assert_receive {:deleted_room, room}
      assert room == "station-session-" <> session.session_id
    end

    test "discard_session/1 deletes the session's LiveKit room" do
      Application.put_env(:backend, :livekit_room_service, RecordingRoomService)
      session = Stations.create_session(%{audio_consent: true})

      assert Stations.discard_session(session.session_id) == :ok
      assert_receive {:deleted_room, room}
      assert room == "station-session-" <> session.session_id
    end

    test "complete_session/2 succeeds even when room cleanup fails" do
      Application.put_env(:backend, :livekit_room_service, FailingRoomService)
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, completed} = Stations.complete_session(session.session_id, :user)
      assert completed.status == :completed
    end

    test "discard_session/1 succeeds even when room cleanup fails" do
      Application.put_env(:backend, :livekit_room_service, FailingRoomService)
      session = Stations.create_session(%{audio_consent: true})

      assert Stations.discard_session(session.session_id) == :ok
    end

    test "cleanup is skipped entirely when LiveKit is not configured" do
      Application.delete_env(:backend, :livekit_url)
      Application.put_env(:backend, :livekit_room_service, RecordingRoomService)
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, _} = Stations.complete_session(session.session_id, :user)
      refute_receive {:deleted_room, _room}, 50
    end
  end

  describe "real-time bounded voice turns (#119)" do
    for rule_id <- ["length-cap", "max-length"] do
      test "process_voice_turn/3 refuses final fact text exceeding #{rule_id} without claiming emitted facts" do
        original_package = Stations.get_active_package()

        package =
          Path.expand("../../priv/stations/fixtures/valid-package.json", __DIR__)
          |> File.read!()
          |> Jason.decode!()
          |> Map.put("response_rules", [
            %{
              "id" => unquote(rule_id),
              "instruction" => "Keep replies within 35 characters.",
              "max_length" => 35
            }
          ])

        assert {:ok, package} = Backend.Stations.StationPackage.validate(package)
        :sys.replace_state(Backend.Stations.StationLoader, fn _ -> package end)

        on_exit(fn ->
          :sys.replace_state(Backend.Stations.StationLoader, fn _ -> original_package end)
        end)

        Application.put_env(:backend, :station_ai_adapter, TestFactWithoutPeriodAdapter)
        session = Stations.create_session(%{audio_consent: true})

        assert {:ok, result} =
                 Stations.process_voice_turn(session.session_id, 1, "Quando começou a dor?")

        assert result.reply_text == "Não tenho essa informação"
        assert String.length(result.reply_text) <= 35
        assert result.used_facts == []
        assert result.turn_id == 1
        assert result.generation_id == 1

        assert {:ok, updated_session} = Stations.get_session(session.session_id)
        assert [learner, patient] = updated_session.messages
        assert learner.text == "Quando começou a dor?"
        assert patient.role == :patient
        assert patient.text == "Não tenho essa informação"
        assert String.length(patient.text) <= 35

        assert {:ok, :duplicate} =
                 Stations.process_voice_turn(session.session_id, 1, "Quando começou a dor?")

        assert {:ok, unchanged_session} = Stations.get_session(session.session_id)
        assert unchanged_session.messages == updated_session.messages
      end
    end

    test "process_voice_turn/3 allows authorized fact content to survive and updates session" do
      Application.put_env(:backend, :station_ai_adapter, TestRevealableFactsAdapter)
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, result} =
               Stations.process_voice_turn(
                 session.session_id,
                 1,
                 "Quando começou a dor no peito?"
               )

      assert result.reply_text == "A dor começou durante uma caminhada."
      assert result.turn_id == 1
      assert result.generation_id == 1
      assert length(result.used_facts) == 1
      assert hd(result.used_facts)["topic"] == "onset"
      assert hd(result.used_facts)["content"] == "A dor começou durante uma caminhada."

      {:ok, updated_session} = Stations.get_session(session.session_id)
      assert length(updated_session.messages) == 2

      [msg1, msg2] = updated_session.messages
      assert msg1.role == :learner
      assert msg1.modality == :voice
      assert msg1.text == "Quando começou a dor no peito?"
      assert msg2.role == :patient
      assert msg2.modality == :voice
      assert msg2.text == "A dor começou durante uma caminhada."

      assert updated_session.last_voice_turn_id == 1
      assert {:ok, nil} = Conversation.active_generation(session.session_id)
    end

    test "process_voice_turn/3 returns canonical refusal when unknown question is asked" do
      Application.put_env(:backend, :station_ai_adapter, TestRefusalAdapter)
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, result} =
               Stations.process_voice_turn(
                 session.session_id,
                 1,
                 "Qual o seu time de futebol favorito?"
               )

      assert result.reply_text == "Não tenho essa informação"
      assert result.turn_id == 1
      assert result.generation_id == 1
      assert result.used_facts == []

      {:ok, updated_session} = Stations.get_session(session.session_id)
      assert List.last(updated_session.messages).text == "Não tenho essa informação"
    end

    test "process_voice_turn/3 fails closed: fabricated pt-BR clinical assertion becomes canonical refusal" do
      Application.put_env(:backend, :station_ai_adapter, TestFabricatedClinicalAdapter)
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, result} =
               Stations.process_voice_turn(
                 session.session_id,
                 1,
                 "Você toma algum remédio para o estômago?"
               )

      # Fabricated clinical text must never leave Phoenix; replaced by refusal
      assert result.reply_text == "Não tenho essa informação"
      assert result.used_facts == []

      {:ok, updated_session} = Stations.get_session(session.session_id)
      assert List.last(updated_session.messages).text == "Não tenho essa informação"
    end

    test "process_voice_turn/3 fails closed: clinical assertion embedding fact substring plus fabricated text becomes refusal" do
      Application.put_env(:backend, :station_ai_adapter, TestFactSubstringWithFabricatedAdapter)
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, result} =
               Stations.process_voice_turn(
                 session.session_id,
                 1,
                 "A dor irradia para algum lugar?"
               )

      # Substring match alone does not make arbitrary clinical assertion safe
      assert result.reply_text == "Não tenho essa informação"
      assert result.used_facts == []

      {:ok, updated_session} = Stations.get_session(session.session_id)
      assert List.last(updated_session.messages).text == "Não tenho essa informação"
    end

    test "process_voice_turn/3 refuses duplicate or reordered turn_id without calling adapter or returning text" do
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, %{reply_text: _}} =
               Stations.process_voice_turn(session.session_id, 1, "Primeira fala")

      # Repeating turn_id 1 returns duplicate, no reply text
      assert {:ok, :duplicate} =
               Stations.process_voice_turn(session.session_id, 1, "Repetição do turno 1")

      # Stale turn_id 0 returns invalid_transcript, no reply text
      assert {:error, :invalid_transcript} =
               Stations.process_voice_turn(session.session_id, 0, "Turno 0 inválido")

      {:ok, updated_session} = Stations.get_session(session.session_id)
      assert length(updated_session.messages) == 2
      assert hd(updated_session.messages).text == "Primeira fala"
    end

    test "supersession during slow adapter call suppresses stale turn without returning text" do
      Application.put_env(:backend, :station_ai_adapter, TestSlowBarrierAdapter)
      Application.put_env(:backend, :voice_turn_test_pid, self())
      session = Stations.create_session(%{audio_consent: true})

      # Start Turn 1 in background task
      task1 =
        Task.async(fn ->
          Stations.process_voice_turn(session.session_id, 1, "Pergunta 1 com adaptador lento")
        end)

      # Wait until Turn 1 enters adapter
      assert_receive {:adapter_called, _context}, 1000

      # While Turn 1 is suspended in adapter, Turn 2 arrives with RevealableFactsAdapter
      Application.put_env(:backend, :station_ai_adapter, TestRevealableFactsAdapter)

      assert {:ok, turn2_result} =
               Stations.process_voice_turn(session.session_id, 2, "Pergunta 2 interrompendo")

      assert turn2_result.turn_id == 2
      assert turn2_result.generation_id == 2

      # Now resume Turn 1's adapter
      send(task1.pid, {:resume_adapter, "A dor começou durante uma caminhada."})

      # Turn 1 must fail with :stale_generation and NEVER return text
      assert Task.await(task1) == {:error, :stale_generation}

      # Verify session only contains Turn 1 (learner), Turn 2 (learner), and Turn 2 (patient)
      {:ok, final_session} = Stations.get_session(session.session_id)
      assert length(final_session.messages) == 3

      assert Enum.map(final_session.messages, & &1.text) == [
               "Pergunta 1 com adaptador lento",
               "Pergunta 2 interrompendo",
               turn2_result.reply_text
             ]
    end

    test "cancellation during slow adapter call invalidates generation and suppresses text" do
      Application.put_env(:backend, :station_ai_adapter, TestSlowBarrierAdapter)
      Application.put_env(:backend, :voice_turn_test_pid, self())
      session = Stations.create_session(%{audio_consent: true})

      # Start Turn 1 in background task
      task =
        Task.async(fn ->
          Stations.process_voice_turn(session.session_id, 1, "Pergunta a ser cancelada")
        end)

      assert_receive {:adapter_called, _context}, 1000

      # Cancel generation 1 explicitly via public context API
      assert {:ok, :cancelled} = Stations.cancel_voice_turn(session.session_id, 1)

      # Resume adapter
      send(task.pid, {:resume_adapter, "A dor começou durante uma caminhada."})

      # Awaited task returns stale_generation error, no text
      assert Task.await(task) == {:error, :stale_generation}

      # Session only has the learner message, no patient message was appended
      {:ok, final_session} = Stations.get_session(session.session_id)
      assert length(final_session.messages) == 1
      assert hd(final_session.messages).text == "Pergunta a ser cancelada"
    end

    test "completion during slow adapter call suppresses text and locks session" do
      Application.put_env(:backend, :station_ai_adapter, TestSlowBarrierAdapter)
      Application.put_env(:backend, :voice_turn_test_pid, self())
      session = Stations.create_session(%{audio_consent: true})

      task =
        Task.async(fn ->
          Stations.process_voice_turn(session.session_id, 1, "Pergunta antes de completar")
        end)

      assert_receive {:adapter_called, _context}, 1000

      assert {:ok, _} = Stations.complete_session(session.session_id, :user)

      send(task.pid, {:resume_adapter, "A dor começou durante uma caminhada."})

      assert Task.await(task) == {:error, :completed}

      {:ok, completed_session} = Stations.get_session(session.session_id)
      assert completed_session.status == :completed
      assert length(completed_session.messages) == 1

      # Calling on an already completed session also returns {:error, :completed}
      assert Stations.process_voice_turn(session.session_id, 2, "Pergunta pós-conclusão") ==
               {:error, :completed}
    end

    test "expiry during slow adapter call suppresses text" do
      Application.put_env(:backend, :station_ai_adapter, TestSlowBarrierAdapter)
      Application.put_env(:backend, :voice_turn_test_pid, self())
      session = Stations.create_session(%{audio_consent: true})

      task =
        Task.async(fn ->
          Stations.process_voice_turn(session.session_id, 1, "Pergunta antes de expirar")
        end)

      assert_receive {:adapter_called, _context}, 1000

      # Force expiration by setting expires_at into the past in Conversation ETS
      [{_id, stored_session}] = :ets.lookup(Conversation, session.session_id)

      expired_session = %{
        stored_session
        | expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
      }

      :ets.insert(Conversation, {session.session_id, expired_session})

      send(task.pid, {:resume_adapter, "A dor começou durante uma caminhada."})

      assert Task.await(task) == {:error, :expired}

      # A fresh expired session also returns {:error, :expired} on first call
      session2 = Stations.create_session(%{audio_consent: true})
      [{_id, stored2}] = :ets.lookup(Conversation, session2.session_id)

      expired2 = %{
        stored2
        | expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
      }

      :ets.insert(Conversation, {session2.session_id, expired2})

      assert Stations.process_voice_turn(session2.session_id, 1, "Pergunta sessão expirada") ==
               {:error, :expired}
    end

    test "evaluator consumes role-labelled voice turn transcript and produces rubric evaluation" do
      Application.put_env(:backend, :station_ai_adapter, TestRevealableFactsAdapter)
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, turn1} =
               Stations.process_voice_turn(
                 session.session_id,
                 1,
                 "Quando começou a dor no peito?"
               )

      assert turn1.reply_text == "A dor começou durante uma caminhada."

      assert {:ok, _} = Stations.complete_session(session.session_id, :user)

      assert {:ok, result} = Stations.get_session_result(session.session_id)
      assert result.session_id == session.session_id
      assert result.status == "completed"

      onset_criterion = Enum.find(result.criteria, &(&1.id == "onset-assessment"))
      assert onset_criterion != nil
      assert onset_criterion.status == "met"
      assert is_list(onset_criterion.evidence)
      assert length(onset_criterion.evidence) > 0

      # Learner question was properly captured and visible to Evaluator
      assert Enum.any?(
               onset_criterion.evidence,
               &String.contains?(&1, "Quando começou a dor no peito?")
             )
    end

    test "cancel_voice_turn/2 enforces generation match and session state" do
      session = Stations.create_session(%{audio_consent: true})

      # No active generation initially
      assert {:ok, :cancelled} = Stations.cancel_voice_turn(session.session_id)

      # Start a turn and cancel it
      Application.put_env(:backend, :station_ai_adapter, TestSlowBarrierAdapter)
      Application.put_env(:backend, :voice_turn_test_pid, self())

      task =
        Task.async(fn ->
          Stations.process_voice_turn(session.session_id, 1, "Pergunta para cancelamento")
        end)

      assert_receive {:adapter_called, _context}, 1000

      # Stale generation cancel fails
      assert {:error, :stale_generation} = Stations.cancel_voice_turn(session.session_id, 999)

      # Matching generation cancel succeeds
      assert {:ok, :cancelled} = Stations.cancel_voice_turn(session.session_id, 1)

      send(task.pid, {:resume_adapter, "Resposta descartada"})
      assert Task.await(task) == {:error, :stale_generation}

      # Cancel on non-existent session returns :not_found
      assert Stations.cancel_voice_turn("unknown-session-id", 1) == {:error, :not_found}
    end

    test "process_voice_turn/3 refuses turn without audio consent" do
      session = Stations.create_session(%{audio_consent: false})

      assert Stations.process_voice_turn(session.session_id, 1, "Tentativa sem consentimento") ==
               {:error, :no_consent}

      {:ok, current} = Stations.get_session(session.session_id)
      assert current.messages == []
    end

    test "commit_voice_transcript/3 preserves #118 behavior" do
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, :committed} =
               Stations.commit_voice_transcript(session.session_id, 1, "Fala legada")

      assert {:ok, :duplicate} =
               Stations.commit_voice_transcript(session.session_id, 1, "Fala repetida")

      {:ok, current} = Stations.get_session(session.session_id)
      assert length(current.messages) == 1
      assert hd(current.messages).text == "Fala legada"
    end
  end
end
