defmodule Backend.StationsTest do
  use ExUnit.Case, async: false

  alias Backend.Stations

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

      # A manual completion racing an in-flight turn is deferred until the turn
      # resolves. Run it from a separate process so this synchronous adapter
      # call does not deadlock waiting on its own future completion.
      if session_id do
        task = Task.async(fn -> Backend.Stations.complete_session(session_id, :user) end)
        Process.put(:test_concurrent_complete_task, task)
      end

      {:ok, %{text: "Resposta tardia", used_facts: []}}
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

    test "complete_session/2 rejects an early reason=:timer finish arriving well before the deadline" do
      session = Stations.create_session(%{audio_consent: true})

      assert Stations.complete_session(session.session_id, :timer) ==
               {:error, :deadline_not_reached}

      # The session stays active: the rejection did not complete it.
      assert {:ok, %{status: :active}} = Stations.get_session(session.session_id)
    end

    test "complete_session/2 accepts reason=:timer within the tolerance window at the deadline" do
      original_duration = Application.get_env(:backend, :station_duration_ms)
      Application.put_env(:backend, :station_duration_ms, 0)

      on_exit(fn ->
        if is_nil(original_duration) do
          Application.delete_env(:backend, :station_duration_ms)
        else
          Application.put_env(:backend, :station_duration_ms, original_duration)
        end
      end)

      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, completed} = Stations.complete_session(session.session_id, :timer)
      assert completed.status == :completed
      assert completed.completion_reason == :timer
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

    test "create_message/2 rejects a turn received at/after the deadline without touching the transcript" do
      original_duration = Application.get_env(:backend, :station_duration_ms)
      Application.put_env(:backend, :station_duration_ms, 30)

      on_exit(fn ->
        if is_nil(original_duration) do
          Application.delete_env(:backend, :station_duration_ms)
        else
          Application.put_env(:backend, :station_duration_ms, original_duration)
        end
      end)

      session = Stations.create_session(%{audio_consent: true})
      Process.sleep(60)

      assert Stations.create_message(session.session_id, %{
               role: "learner",
               modality: "text",
               text: "Chegou tarde"
             }) == {:error, :station_time_elapsed}

      {:ok, unchanged} = Stations.get_session(session.session_id)
      assert unchanged.messages == []
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

    test "create_message/2 preserves an accepted pending turn's reply when completion races it" do
      Application.put_env(:backend, :station_ai_adapter, TestConcurrentCompleteAdapter)
      session = Stations.create_session(%{audio_consent: true})
      Process.put(:test_concurrent_session_id, session.session_id)

      assert {:ok, %{reply_text: "Resposta tardia"}} =
               Stations.create_message(session.session_id, %{
                 role: "learner",
                 modality: "text",
                 text: "Olá"
               })

      complete_task = Process.get(:test_concurrent_complete_task)
      assert {:ok, completed_via_race} = Task.await(complete_task, 2_000)
      assert completed_via_race.status == :completed
      assert completed_via_race.completion_reason == :user

      assert {:ok, completed_session} = Stations.get_session(session.session_id)
      assert completed_session.status == :completed
      assert completed_session.completion_reason == :user
      assert length(completed_session.messages) == 2
      [msg1, msg2] = completed_session.messages
      assert msg1.role == :learner
      assert msg2.role == :patient
      assert msg2.text == "Resposta tardia"
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

    test "check_session_deadline/1 is genuinely time-based: it flips once the deadline passes, without completing the session" do
      original_duration = Application.get_env(:backend, :station_duration_ms)
      Application.put_env(:backend, :station_duration_ms, 50)

      on_exit(fn ->
        if is_nil(original_duration) do
          Application.delete_env(:backend, :station_duration_ms)
        else
          Application.put_env(:backend, :station_duration_ms, original_duration)
        end
      end)

      session = Stations.create_session(%{audio_consent: true})
      assert Stations.check_session_deadline(session.session_id) == {:ok, :within_deadline}

      Process.sleep(80)

      # Time-based regardless of whether the auto-completion timer has already
      # fired: an active session past its deadline and a completed session both
      # report :session_time_elapsed.
      assert Stations.check_session_deadline(session.session_id) ==
               {:error, :session_time_elapsed}
    end

    test "request_impresso/2 returns not_implemented" do
      assert Stations.request_impresso("session-id", %{"type" => "ecg"}) ==
               {:error, :not_implemented}
    end

    test "create_voice_session/2 returns not_implemented" do
      assert Stations.create_voice_session("session-id") == {:error, :not_implemented}
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
end
