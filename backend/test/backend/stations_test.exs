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
      if session_id, do: Backend.Stations.complete_session(session_id, :user)
      {:ok, %{text: "Resposta tardia", used_facts: []}}
    end
  end

  defmodule TestVerifyingJevAdapter do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request) do
      {:ok, %{status: :verified}}
    end

    @impl true
    def decide_rubric(_request) do
      {:error, :not_implemented}
    end
  end

  defmodule RefuseThenVerifyAdapter do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(request) do
      decide_patient(request, [])
    end

    def decide_patient(request, _opts) do
      if request.candidate_text == "initial_refused" do
        {:ok, %{status: :semantic_refusal, reason: "hallucination"}}
      else
        {:ok, %{status: :verified}}
      end
    end

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  defmodule TemplateReplyAIAdapter do
    @behaviour Backend.Stations.StationAI

    @impl true
    def next_reply(_package, _context) do
      case Process.get(:template_reply_text) do
        text when is_binary(text) -> {:ok, %{text: text, used_facts: []}}
        _ -> {:error, :template_reply_text_not_set}
      end
    end
  end

  defmodule ProbingVerifyingJevAdapter do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request) do
      # Runs inside a Task, so the probe pid is read from application env.
      parent = Process.get(:jev_probe_pid) || Application.get_env(:backend, :jev_probe_pid)
      if parent, do: send(parent, :jev_verification_invoked)
      {:ok, %{status: :verified}}
    end

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  setup do
    prev_adapter = Application.get_env(:backend, :station_ai_adapter)
    prev_jev_adapter = Application.get_env(:backend, :jev_decision_adapter)

    Application.put_env(:backend, :station_ai_adapter, TestSuccessAdapter)
    Application.put_env(:backend, :jev_decision_adapter, TestVerifyingJevAdapter)

    on_exit(fn ->
      if prev_adapter do
        Application.put_env(:backend, :station_ai_adapter, prev_adapter)
      else
        Application.delete_env(:backend, :station_ai_adapter)
      end

      if prev_jev_adapter do
        Application.put_env(:backend, :jev_decision_adapter, prev_jev_adapter)
      else
        Application.delete_env(:backend, :jev_decision_adapter)
      end
    end)

    :ok
  end

  describe "package & metadata" do
    test "get_active_station/0 returns metadata map" do
      station = Stations.get_active_station()

      assert %{
               "station_id" => "chest-pain-initial-assessment",
               "version" => "2.0.0",
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
      assert Stations.active_version() == "2.0.0"
    end
  end

  describe "session lifecycle" do
    test "create_session/1 creates an ephemeral active session with defaults" do
      session = Stations.create_session(%{audio_consent: true})

      assert is_binary(session.session_id)
      assert session.station_id == "chest-pain-initial-assessment"
      assert session.station_version == "2.0.0"
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

  describe "approved template case-state bypass" do
    # The loader state is the validated package map itself, so the active
    # package is swapped temporarily (restored via on_exit) to serve approved
    # templates through the real create_message/2 production path.
    defp swap_active_templates(templates) do
      loader = Backend.Stations.StationLoader
      original = :sys.get_state(loader)
      :sys.replace_state(loader, fn _ -> Map.put(original, "approved_templates", templates) end)

      on_exit(fn ->
        :sys.replace_state(loader, fn _ -> original end)
      end)
    end

    defp activate_template_bypass_probe(template_text) do
      Application.put_env(:backend, :station_ai_adapter, TemplateReplyAIAdapter)
      Application.put_env(:backend, :jev_decision_adapter, ProbingVerifyingJevAdapter)
      Application.put_env(:backend, :jev_probe_pid, self())
      Process.put(:template_reply_text, template_text)

      on_exit(fn ->
        Application.delete_env(:backend, :jev_probe_pid)
      end)
    end

    test "create_message/2 routes the byte-identical min_learner_turns candidate to Jev below the count and bypasses once met" do
      template_text = "Estou sentindo uma dor no peito há duas horas."

      swap_active_templates([
        %{
          "template_id" => "onset-summary",
          "text" => template_text,
          "applicability" => %{"type" => "min_learner_turns", "count" => 2}
        }
      ])

      activate_template_bypass_probe(template_text)
      session = Stations.create_session(%{audio_consent: true})

      # Learner turn 1: learner_turns is 1, so the predicate is false and the
      # same byte-identical candidate routes to Jev verification.
      assert {:ok, first} =
               Stations.create_message(session.session_id, %{
                 role: :learner,
                 modality: :text,
                 text: "Onde dói?"
               })

      assert first.reply_text == template_text
      assert_receive :jev_verification_invoked, 1_000

      # Learner turn 2: learner_turns is 2, so the candidate bypasses Jev.
      assert {:ok, second} =
               Stations.create_message(session.session_id, %{
                 role: :learner,
                 modality: "text",
                 text: "Há quanto tempo?"
               })

      assert second.reply_text == template_text
      refute_receive :jev_verification_invoked, 100
    end

    test "create_message/2 honors first_learner_turn only when no learner turn precedes the candidate" do
      template_text = "A dor começou de repente enquanto eu caminhava."

      swap_active_templates([
        %{
          "template_id" => "opening-onset",
          "text" => template_text,
          "applicability" => %{"type" => "first_learner_turn"}
        }
      ])

      activate_template_bypass_probe(template_text)
      session = Stations.create_session(%{audio_consent: true})

      # First learner turn: bypass without any Jev consultation.
      assert {:ok, first} =
               Stations.create_message(session.session_id, %{
                 role: :learner,
                 modality: "text",
                 text: "Me conte o que aconteceu."
               })

      assert first.reply_text == template_text
      refute_receive :jev_verification_invoked, 100

      # Second learner turn: the predicate no longer holds, so Jev runs.
      assert {:ok, second} =
               Stations.create_message(session.session_id, %{
                 role: :learner,
                 modality: "text",
                 text: "Já sentiu isso antes?"
               })

      assert second.reply_text == template_text
      assert_receive :jev_verification_invoked, 1_000
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

    test "create_voice_session/2 returns not_implemented" do
      assert Stations.create_voice_session("session-id") == {:error, :not_implemented}
    end

    test "verify_patient_reply/3 passes through reply" do
      pkg = Stations.get_active_package()
      reply = %{text: "dor forte"}
      assert Stations.verify_patient_reply(pkg, reply) == {:ok, reply}
    end

    test "verify_patient_reply/3 purges stale used_facts when candidate is regenerated after refusal" do
      pkg = Stations.get_active_package()
      initial_reply = %{text: "initial_refused", used_facts: ["fact-initial-stale"]}

      opts = [
        adapter: RefuseThenVerifyAdapter,
        generator: fn -> {:ok, "verified_regenerated_text"} end
      ]

      assert {:ok, verified_reply} = Stations.verify_patient_reply(pkg, initial_reply, opts)
      assert verified_reply.text == "verified_regenerated_text"
      assert verified_reply.used_facts == []
    end

    test "verify_patient_reply/3 purges stale used_facts on string-keyed reply maps" do
      pkg = Stations.get_active_package()
      initial_reply = %{"text" => "initial_refused", "used_facts" => ["fact-initial-stale"]}

      opts = [
        adapter: RefuseThenVerifyAdapter,
        generator: fn -> {:ok, "verified_regenerated_text"} end
      ]

      assert {:ok, verified_reply} = Stations.verify_patient_reply(pkg, initial_reply, opts)
      assert verified_reply["text"] == "verified_regenerated_text"
      assert verified_reply["used_facts"] == []
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
