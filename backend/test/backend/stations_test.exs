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

  defmodule ConfiguredPatientJevAdapter do
    @moduledoc "Answers every patient verification with the result set in application env."
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request), do: Application.fetch_env!(:backend, :test_patient_decision)

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

  defp use_patient_decision(decision) do
    Application.put_env(:backend, :jev_decision_adapter, ConfiguredPatientJevAdapter)
    Application.put_env(:backend, :test_patient_decision, decision)
    on_exit(fn -> Application.delete_env(:backend, :test_patient_decision) end)
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

    test "get_active_station/0 projects the brief to scenario and tasks only (#239)" do
      station = Stations.get_active_station()

      assert Map.keys(station) |> Enum.sort() ==
               ~w(candidate_brief display_title language station_id version)

      assert %{"scenario" => scenario, "tasks" => tasks} = station["candidate_brief"]
      assert map_size(station["candidate_brief"]) == 2
      assert is_binary(scenario)
      assert [_ | _] = tasks
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

    for refusal <- [:low_confidence, :semantic_refusal] do
      test "create_message/2 keeps the learner turn and drops the patient reply when Jev refuses with #{refusal}" do
        use_patient_decision({:ok, %{status: unquote(refusal), rationale: "refused"}})
        session = Stations.create_session(%{audio_consent: true})

        assert {:error, {:refused, unquote(refusal), learner_turn}} =
                 Stations.create_message(session.session_id, %{
                   role: "learner",
                   modality: "text",
                   text: "Na palpação há dor no ponto de McBurney."
                 })

        assert %{role: :learner, modality: :text, at: %DateTime{}} = learner_turn
        assert learner_turn.text == "Na palpação há dor no ponto de McBurney."

        {:ok, session_after} = Stations.get_session(session.session_id)
        assert session_after.status == :active
        assert session_after.messages == [learner_turn]
        refute inspect(session_after) =~ "forte dor no peito"
      end
    end

    test "create_message/2 rolls the learner turn back when Jev fails technically" do
      use_patient_decision({:error, :provider_unavailable})
      session = Stations.create_session(%{audio_consent: true})

      assert {:error, reason} =
               Stations.create_message(session.session_id, %{
                 role: "learner",
                 modality: "text",
                 text: "Olá"
               })

      refute match?({:refused, _, _}, reason)

      {:ok, session_after} = Stations.get_session(session.session_id)
      assert session_after.status == :active
      assert session_after.messages == []
    end

    test "create_message/2 accepts the next turn after a refused patient reply without duplicating the kept turn" do
      use_patient_decision({:ok, %{status: :semantic_refusal, rationale: "refused"}})
      session = Stations.create_session(%{audio_consent: true})

      assert {:error, {:refused, :semantic_refusal, _turn}} =
               Stations.create_message(session.session_id, %{
                 role: "learner",
                 modality: "text",
                 text: "Primeira mensagem"
               })

      Application.put_env(:backend, :jev_decision_adapter, TestVerifyingJevAdapter)

      assert {:ok, _reply} =
               Stations.create_message(session.session_id, %{
                 role: "learner",
                 modality: "text",
                 text: "Segunda mensagem"
               })

      {:ok, session_after} = Stations.get_session(session.session_id)

      assert Enum.map(session_after.messages, &{&1.role, &1.text}) == [
               {:learner, "Primeira mensagem"},
               {:learner, "Segunda mensagem"},
               {:patient, "Estou sentindo uma forte dor no peito há 2 horas."}
             ]
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

  describe "learner message length limit" do
    test "create_message/2 accepts a learner message of exactly 2,000 characters" do
      session = Stations.create_session(%{audio_consent: true})
      # Multi-byte graphemes: the limit counts characters, not bytes.
      text = String.duplicate("á", 2_000)

      assert {:ok, _result} =
               Stations.create_message(session.session_id, %{
                 role: "learner",
                 modality: "text",
                 text: text
               })

      {:ok, updated_session} = Stations.get_session(session.session_id)
      assert [%{role: :learner, text: ^text}, %{role: :patient}] = updated_session.messages
    end

    test "create_message/2 rejects a learner message over 2,000 characters before it enters the conversation or reaches Jev" do
      Application.put_env(:backend, :jev_decision_adapter, ProbingVerifyingJevAdapter)
      Application.put_env(:backend, :jev_probe_pid, self())
      on_exit(fn -> Application.delete_env(:backend, :jev_probe_pid) end)

      session = Stations.create_session(%{audio_consent: true})

      assert Stations.create_message(session.session_id, %{
               role: "learner",
               modality: "voice",
               text: String.duplicate("á", 2_001)
             }) == {:error, :message_too_long}

      {:ok, unchanged} = Stations.get_session(session.session_id)
      assert unchanged.messages == []
      refute_received :jev_verification_invoked
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
    test "discard_session/1 idempotently removes active session and denies subsequent operations" do
      session = Stations.create_session(%{audio_consent: true})
      assert {:ok, _} = Stations.get_session(session.session_id)

      assert Stations.discard_session(session.session_id) == :ok

      # Subsequent operations are denied with :not_found
      assert Stations.get_session(session.session_id) == {:error, :not_found}
      assert Stations.fetch_session(session.session_id) == {:error, :not_found}

      assert Stations.create_message(session.session_id, %{
               role: :learner,
               modality: :text,
               text: "Olá"
             }) == {:error, :not_found}

      assert Stations.complete_session(session.session_id, :user) == {:error, :not_found}
      assert Stations.finish_session(session.session_id, :user) == {:error, :not_found}
      assert Stations.get_session_result(session.session_id) == {:error, :not_found}
      assert Stations.evaluate_session(session.session_id) == {:error, :not_found}

      assert Stations.request_impresso(session.session_id, %{
               "text" => "ecg",
               "request_id" => "req-1"
             }) == {:error, :not_found}

      assert Stations.list_impressos(session.session_id) == {:error, :not_found}
      assert Stations.check_session_deadline(session.session_id) == {:error, :not_found}

      # Idempotent: repeated discard is safe
      assert Stations.discard_session(session.session_id) == :ok
    end

    test "discard_session/1 removes completed session and denies subsequent result retrieval" do
      session = Stations.create_session(%{audio_consent: true})
      assert {:ok, _} = Stations.complete_session(session.session_id, :user)

      # Result is retrievable before discard
      assert {:ok, _result} = Stations.get_session_result(session.session_id)

      # Discard the completed session
      assert Stations.discard_session(session.session_id) == :ok

      # Result and session retrieval are now denied
      assert Stations.get_session_result(session.session_id) == {:error, :not_found}
      assert Stations.get_session(session.session_id) == {:error, :not_found}
      assert Stations.complete_session(session.session_id, :user) == {:error, :not_found}

      assert Stations.create_message(session.session_id, %{
               role: :learner,
               modality: :text,
               text: "Depois de descartado"
             }) == {:error, :not_found}

      # Repeated discard remains safe
      assert Stations.discard_session(session.session_id) == :ok
    end

    test "discard_session/1 is safe for unknown and expired sessions" do
      assert Stations.discard_session("completely-unknown-session-id") == :ok

      original_timeout = Application.get_env(:backend, :conversation_timeout_ms)
      Application.put_env(:backend, :conversation_timeout_ms, 0)

      session =
        try do
          Stations.create_session(%{audio_consent: false})
        after
          if is_nil(original_timeout) do
            Application.delete_env(:backend, :conversation_timeout_ms)
          else
            Application.put_env(:backend, :conversation_timeout_ms, original_timeout)
          end
        end

      assert Stations.discard_session(session.session_id) == :ok
      assert Stations.get_session(session.session_id) == {:error, :not_found}
    end

    test "discard_session/1 immediately unblocks pending complete_session callers" do
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, _session, _token} =
               Backend.Stations.Conversation.begin_turn(session.session_id, %{
                 role: :learner,
                 modality: :text,
                 text: "Pergunta em andamento"
               })

      waiter_task =
        Task.async(fn ->
          Stations.complete_session(session.session_id, :user)
        end)

      Process.sleep(20)

      assert Stations.discard_session(session.session_id) == :ok
      assert Task.await(waiter_task, 1_000) == {:error, :not_found}
      assert Stations.get_session(session.session_id) == {:error, :not_found}
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

    test "request_impresso/2 returns not_found for an unknown session" do
      assert Stations.request_impresso("unknown-session", %{"text" => "ecg"}) ==
               {:error, :not_found}
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

  describe "impresso requests" do
    setup do
      session = Stations.create_session(%{audio_consent: false})
      %{session: session}
    end

    test "matches a single impresso and releases it", %{session: session} do
      assert {:ok, result} =
               Stations.request_impresso(session.session_id, %{
                 "text" => "quero ver os sinais vitais"
               })

      assert result.decision == "released"
      assert is_binary(result.request_id)

      assert [%{id: "exame-fisico-geral", title: title, category: "physical_exam"}] =
               result.newly_released

      assert String.starts_with?(title, "IMPRESSO")
      assert result.released_impressos == result.newly_released
      assert result.feedback_message == "Impresso liberado: #{title}"

      for impresso <- result.released_impressos do
        assert Map.has_key?(impresso, :content)
        refute Map.has_key?(impresso, :keywords)
      end
    end

    test "an ambiguous request releases every matched impresso in authored order", %{
      session: session
    } do
      assert {:ok, result} =
               Stations.request_impresso(session.session_id, %{
                 "text" => "preciso do exame físico, sinais vitais e do laudo de ecg"
               })

      assert result.decision == "released"
      ids = Enum.map(result.newly_released, & &1.id)
      assert ids == ["exame-fisico-geral", "laudo-eletrocardiograma"]
    end

    test "repeating the same request is already_released", %{session: session} do
      {:ok, _} =
        Stations.request_impresso(session.session_id, %{"text" => "sinais vitais"})

      assert {:ok, result} =
               Stations.request_impresso(session.session_id, %{"text" => "sinais vitais"})

      assert result.decision == "already_released"
      assert result.newly_released == []
      assert length(result.released_impressos) == 1
      assert result.feedback_message =~ "Impresso já liberado"
    end

    test "accepts request text of exactly 2,000 characters", %{session: session} do
      text = String.pad_trailing("sinais vitais ", 2_000, "á")

      assert {:ok, _result} = Stations.request_impresso(session.session_id, %{"text" => text})

      {:ok, updated} = Stations.get_session(session.session_id)
      assert [%{text: ^text}] = updated.impresso_requests
    end

    test "rejects request text over 2,000 characters before anything is recorded", %{
      session: session
    } do
      text = String.pad_trailing("sinais vitais ", 2_001, "á")

      assert Stations.request_impresso(session.session_id, %{"text" => text}) ==
               {:error, :message_too_long}

      {:ok, unchanged} = Stations.get_session(session.session_id)
      assert unchanged.impresso_requests == []
      assert {:ok, %{released_impressos: []}} = Stations.list_impressos(session.session_id)
    end

    test "an unavailable exam returns the exact required message and releases nothing", %{
      session: session
    } do
      assert {:ok, result} =
               Stations.request_impresso(session.session_id, %{
                 "text" => "quero uma tomografia de crânio"
               })

      assert result.decision == "unavailable"
      assert result.newly_released == []
      assert result.released_impressos == []
      assert result.feedback_message == "Exame não disponível nesta estação"
      refute result.feedback_message == "Não há alterações relatadas"
    end

    test "a repeated request_id is idempotent and does not append a new event", %{
      session: session
    } do
      assert {:ok, first} =
               Stations.request_impresso(session.session_id, %{
                 "text" => "sinais vitais",
                 "request_id" => "client-req-1"
               })

      assert {:ok, second} =
               Stations.request_impresso(session.session_id, %{
                 "text" => "exames laboratoriais",
                 "request_id" => "client-req-1"
               })

      assert second.request_id == "client-req-1"
      assert second.decision == first.decision
      assert second.newly_released == first.newly_released

      {:ok, raw_session} = Stations.get_session(session.session_id)
      assert length(raw_session.impresso_requests) == 1
    end

    test "requests append events in order and preserve the session order field", %{
      session: session
    } do
      {:ok, _} = Stations.request_impresso(session.session_id, %{"text" => "sinais vitais"})

      {:ok, _} =
        Stations.request_impresso(session.session_id, %{"text" => "tomografia de crânio"})

      {:ok, _} =
        Stations.request_impresso(session.session_id, %{"text" => "exames laboratoriais"})

      {:ok, raw_session} = Stations.get_session(session.session_id)
      assert Enum.map(raw_session.impresso_requests, & &1.order) == [1, 2, 3]
    end

    test "returns invalid_request on missing, blank or non-string text", %{session: session} do
      for bad_text <- [nil, "", "   ", 123, %{}] do
        params = if is_nil(bad_text), do: %{}, else: %{"text" => bad_text}
        assert Stations.request_impresso(session.session_id, params) == {:error, :invalid_request}
      end
    end

    test "returns not_found for an unknown session" do
      assert Stations.request_impresso("nonexistent", %{"text" => "ecg"}) ==
               {:error, :not_found}
    end

    test "returns expired for an expired session" do
      original_timeout = Application.get_env(:backend, :conversation_timeout_ms)
      Application.put_env(:backend, :conversation_timeout_ms, 0)

      session =
        try do
          Stations.create_session(%{audio_consent: false})
        after
          if is_nil(original_timeout) do
            Application.delete_env(:backend, :conversation_timeout_ms)
          else
            Application.put_env(:backend, :conversation_timeout_ms, original_timeout)
          end
        end

      assert Stations.request_impresso(session.session_id, %{"text" => "ecg"}) ==
               {:error, :expired}
    end

    test "returns completed for a finished session", %{session: session} do
      {:ok, _} = Stations.complete_session(session.session_id, :user)

      assert Stations.request_impresso(session.session_id, %{"text" => "ecg"}) ==
               {:error, :completed}
    end

    test "restarting the Conversation process discards all released impressos", %{
      session: session
    } do
      {:ok, _} = Stations.request_impresso(session.session_id, %{"text" => "ecg"})

      :ok = Supervisor.terminate_child(Backend.Supervisor, Backend.Stations.Conversation)
      {:ok, _pid} = Supervisor.restart_child(Backend.Supervisor, Backend.Stations.Conversation)

      assert Stations.get_session(session.session_id) == {:error, :not_found}
    end
  end

  describe "list_impressos/1" do
    test "returns released impressos in release order, without keywords" do
      session = Stations.create_session(%{audio_consent: false})
      {:ok, _} = Stations.request_impresso(session.session_id, %{"text" => "sinais vitais"})
      {:ok, _} = Stations.request_impresso(session.session_id, %{"text" => "ecg"})

      assert {:ok, %{released_impressos: released}} = Stations.list_impressos(session.session_id)
      assert Enum.map(released, & &1.id) == ["exame-fisico-geral", "laudo-eletrocardiograma"]
      refute Enum.any?(released, &Map.has_key?(&1, :keywords))
    end

    test "is allowed on a completed session" do
      session = Stations.create_session(%{audio_consent: false})
      {:ok, _} = Stations.request_impresso(session.session_id, %{"text" => "sinais vitais"})
      {:ok, _} = Stations.complete_session(session.session_id, :user)

      assert {:ok, %{released_impressos: released}} = Stations.list_impressos(session.session_id)
      assert length(released) == 1
    end

    test "returns not_found and expired like the other reads" do
      assert Stations.list_impressos("nonexistent") == {:error, :not_found}

      original_timeout = Application.get_env(:backend, :conversation_timeout_ms)
      Application.put_env(:backend, :conversation_timeout_ms, 0)

      session =
        try do
          Stations.create_session(%{audio_consent: false})
        after
          if is_nil(original_timeout) do
            Application.delete_env(:backend, :conversation_timeout_ms)
          else
            Application.put_env(:backend, :conversation_timeout_ms, original_timeout)
          end
        end

      assert Stations.list_impressos(session.session_id) == {:error, :expired}
    end
  end
end
