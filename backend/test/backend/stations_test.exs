defmodule Backend.StationsTest do
  use ExUnit.Case, async: false

  alias Backend.Stations
  alias Backend.Stations.Conversation

  test "voice worker allocation floor separates cancelled IDs from committed learner history" do
    session = Stations.create_session(%{audio_consent: true})
    id = session.session_id

    assert {:ok, :committed} = Stations.commit_voice_transcript(id, 2, "Committed question")
    assert {:error, :stale_generation} = Stations.cancel_voice_turn(id, turn_id: 7)
    assert {:ok, %{last_turn_id: 2, turn_id_floor: 7}} = Stations.voice_worker_context(id)
    assert {:ok, %{messages: [%{text: "Committed question"}]}} = Stations.get_session(id)

    assert {:ok, :committed} = Stations.commit_voice_transcript(id, 9, "New question")
    assert {:ok, %{last_turn_id: 9, turn_id_floor: 9}} = Stations.voice_worker_context(id)
    assert {:error, :stale_generation} = Stations.cancel_voice_turn(id, 999)
    assert {:ok, %{last_turn_id: 9, turn_id_floor: 9}} = Stations.voice_worker_context(id)
  end

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
      if caller = Process.get(:voice_turn_test_pid), do: send(caller, :failed_adapter_called)
      {:error, Process.get(:voice_turn_test_error, :service_unavailable)}
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

  defmodule TestNaturalReplyWithFactsAdapter do
    @behaviour Backend.Stations.StationAI
    @impl true
    def next_reply(_package, _context) do
      {:ok,
       %{
         text: "Começou quando eu estava caminhando, doutor, e ainda não passou.",
         used_facts: [
           %{"topic" => "onset", "content" => "A dor começou durante uma caminhada."}
         ]
       }}
    end
  end

  defmodule TestRegeneratingAdapter do
    @behaviour Backend.Stations.StationAI
    @impl true
    def next_reply(_package, _context) do
      if Process.put(:voice_regeneration_requested, true) do
        {:ok, %{text: "Foi durante uma caminhada, doutor.", used_facts: []}}
      else
        {:ok, %{text: "initial_refused", used_facts: ["fact-initial-stale"]}}
      end
    end
  end

  # Refused first candidate, then a regeneration slower than the Jev deadline
  # the test configures (issue #269).
  defmodule SlowRegenerationAdapter do
    @behaviour Backend.Stations.StationAI
    @impl true
    def next_reply(_package, _context) do
      if Process.put(:slow_regeneration_requested, true) do
        Process.sleep(300)
        {:ok, %{text: "Foi durante uma caminhada, doutor.", used_facts: []}}
      else
        {:ok, %{text: "initial_refused", used_facts: []}}
      end
    end
  end

  defmodule TestRevealableFactsAdapter do
    @behaviour Backend.Stations.StationAI
    @impl true
    def next_reply(_package, _context) do
      {:ok, %{text: "A dor começou durante uma caminhada."}}
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
        {:fail_adapter, reason} ->
          {:error, reason}

        {:resume_adapter, reply_text} ->
          {:ok, %{text: reply_text, used_facts: []}}
      after
        5000 ->
          {:ok, %{text: "Tempo esgotado no adaptador", used_facts: []}}
      end
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

  defmodule DeadlineProbeJevAdapter do
    @moduledoc "Reports the verification budget each patient decision receives (issue #269)."
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(request) do
      send(Application.fetch_env!(:backend, :jev_probe_pid), {:deadline_ms, request.deadline_ms})
      {:ok, %{status: :verified}}
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

  # Issue #242: the patient volunteers an unasked on_request fact unless the
  # regeneration names it as withheld.
  @volunteering_reply "Pioro ao andar, sem febre, e também perdi o apetite."
  @compliant_reply "Pioro ao andar e não tive febre nem vômitos."

  defmodule WithholdingAwareAIAdapter do
    @behaviour Backend.Stations.StationAI

    @impl true
    def next_reply(_package, context) do
      withheld = Map.get(context, :withheld_fact_ids, [])

      if pid = Application.get_env(:backend, :test_withheld_probe_pid),
        do: send(pid, {:withheld, withheld})

      if withheld == [] do
        {:ok, %{text: "Pioro ao andar, sem febre, e também perdi o apetite.", used_facts: []}}
      else
        {:ok, %{text: "Pioro ao andar e não tive febre nem vômitos.", used_facts: []}}
      end
    end
  end

  defmodule UnaskedFactJevAdapter do
    @moduledoc "Refuses the volunteering reply, naming the first on_request fact as unasked."
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(
          %{candidate_text: "Pioro ao andar, sem febre, e também perdi o apetite."} = request
        ) do
      fact =
        request.package["revealable_facts"]
        |> Enum.find(&(&1["disclosure_condition"] == "on_request"))

      {:ok, %{status: :semantic_refusal, unasked_fact_ids: [fact["id"]]}}
    end

    def decide_patient(_request), do: {:ok, %{status: :verified}}

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

      Application.delete_env(:backend, :voice_turn_test_pid)
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

    test "create_message/2 regenerates once naming the unasked fact and delivers the compliant reply" do
      Application.put_env(:backend, :station_ai_adapter, WithholdingAwareAIAdapter)
      Application.put_env(:backend, :jev_decision_adapter, UnaskedFactJevAdapter)
      Application.put_env(:backend, :test_withheld_probe_pid, self())
      on_exit(fn -> Application.delete_env(:backend, :test_withheld_probe_pid) end)

      session = Stations.create_session(%{audio_consent: true})

      on_request_id =
        Stations.get_active_package()["revealable_facts"]
        |> Enum.find(&(&1["disclosure_condition"] == "on_request"))
        |> Map.fetch!("id")

      {result, log} =
        ExUnit.CaptureLog.with_log(fn ->
          Stations.create_message(session.session_id, %{
            role: "learner",
            modality: "text",
            text: "Alguma coisa piora a dor? Teve febre?"
          })
        end)

      assert {:ok, %{reply_text: @compliant_reply}} = result
      assert_received {:withheld, []}
      assert_received {:withheld, [^on_request_id]}
      refute_received {:withheld, _}

      {:ok, session_after} = Stations.get_session(session.session_id)
      refute inspect(session_after) =~ @volunteering_reply
      refute inspect(result) =~ @volunteering_reply
      refute log =~ @volunteering_reply
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
    defmodule TestRefusingJevAdapter do
      @behaviour Backend.Stations.JevDecision.Adapter

      @impl true
      def decide_patient(_request), do: {:ok, %{status: :semantic_refusal}}

      @impl true
      def decide_rubric(_request), do: {:error, :not_implemented}
    end

    test "process_voice_turn/3 verifies the generated reply through Jev before admitting it" do
      Application.put_env(:backend, :station_ai_adapter, TestRevealableFactsAdapter)
      Application.put_env(:backend, :jev_decision_adapter, ProbingVerifyingJevAdapter)
      Application.put_env(:backend, :jev_probe_pid, self())
      on_exit(fn -> Application.delete_env(:backend, :jev_probe_pid) end)

      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, %{reply_text: "A dor começou durante uma caminhada.", turn_id: 1}} =
               Stations.process_voice_turn(session.session_id, 1, "Quando a dor começou?")

      assert_receive :jev_verification_invoked
    end

    test "Jev unavailability fails the voice generation without releasing text" do
      Application.put_env(:backend, :station_ai_adapter, TestRevealableFactsAdapter)

      for jev_adapter <- [Backend.Stations.JevDecision.DisabledAdapter] do
        Application.put_env(:backend, :jev_decision_adapter, jev_adapter)
        session = Stations.create_session(%{audio_consent: true})

        assert {:error, :station_ai_unavailable} =
                 Stations.process_voice_turn(session.session_id, 1, "Quando a dor começou?")

        assert {:error, :station_ai_unavailable} =
                 Stations.process_voice_turn(session.session_id, 1, "Quando a dor começou?")

        assert {:ok, stored} = Stations.get_session(session.session_id)
        assert [%{role: :learner, text: "Quando a dor começou?"}] = stored.messages
        assert stored.failed_voice_turn.turn_id == 1
        assert {:ok, nil} = Conversation.active_generation(session.session_id)
      end
    end

    # Issue #269: a refused voice reply follows the text path (#235): the
    # learner turn is kept, no patient text is stored or spoken, and the
    # result is a kept turn, not a technical failure.
    for refusal <- [:semantic_refusal, :low_confidence] do
      test "a #{refusal} keeps the learner voice turn without patient text" do
        Application.put_env(:backend, :station_ai_adapter, TestRevealableFactsAdapter)
        use_patient_decision({:ok, %{status: unquote(refusal), rationale: "refused"}})
        session = Stations.create_session(%{audio_consent: true})
        id = session.session_id

        assert {:ok, {:kept, kept}} = Stations.process_voice_turn(id, 1, "Quando a dor começou?")
        assert kept == %{turn_id: 1, generation_id: 1, refusal: unquote(refusal)}

        assert {:ok, stored} = Stations.get_session(id)
        assert [%{role: :learner, text: "Quando a dor começou?"}] = stored.messages
        assert stored.failed_voice_turn == nil
        assert {:ok, nil} = Conversation.active_generation(id)

        # A retry of the kept turn never duplicates it or starts a new generation.
        assert {:ok, :duplicate} = Stations.process_voice_turn(id, 1, "Quando a dor começou?")

        # The next turn is processed normally.
        use_patient_decision({:ok, %{status: :verified}})

        assert {:ok, %{turn_id: 2, reply_text: _}} =
                 Stations.process_voice_turn(id, 2, "E agora?")

        assert {:ok, stored} = Stations.get_session(id)
        assert Enum.map(stored.messages, & &1.role) == [:learner, :learner, :patient]
      end
    end

    test "a refusal whose regeneration runs out of time keeps the learner voice turn" do
      Application.put_env(:backend, :station_ai_adapter, SlowRegenerationAdapter)
      Application.put_env(:backend, :jev_decision_adapter, RefuseThenVerifyAdapter)
      prev_deadline = Application.get_env(:backend, :jev_decision_default_deadline_ms)
      Application.put_env(:backend, :jev_decision_default_deadline_ms, 100)

      on_exit(fn ->
        Application.put_env(:backend, :jev_decision_default_deadline_ms, prev_deadline)
      end)

      session = Stations.create_session(%{audio_consent: true})
      id = session.session_id

      assert {:ok, {:kept, %{turn_id: 1, generation_id: 1, refusal: :semantic_refusal}}} =
               Stations.process_voice_turn(id, 1, "Quando a dor começou?")

      assert {:ok, stored} = Stations.get_session(id)
      assert [%{role: :learner, text: "Quando a dor começou?"}] = stored.messages
      assert stored.failed_voice_turn == nil
      assert {:ok, nil} = Conversation.active_generation(id)
    end

    test "voice and text verification share the configured patient reply deadline" do
      Application.put_env(:backend, :station_ai_adapter, TestRevealableFactsAdapter)
      Application.put_env(:backend, :jev_decision_adapter, DeadlineProbeJevAdapter)
      Application.put_env(:backend, :jev_probe_pid, self())
      prev_deadline = Application.get_env(:backend, :jev_decision_default_deadline_ms)
      Application.put_env(:backend, :jev_decision_default_deadline_ms, 2_345)

      on_exit(fn ->
        Application.delete_env(:backend, :jev_probe_pid)
        Application.put_env(:backend, :jev_decision_default_deadline_ms, prev_deadline)
      end)

      voice = Stations.create_session(%{audio_consent: true})
      assert {:ok, %{turn_id: 1}} = Stations.process_voice_turn(voice.session_id, 1, "Quando?")
      assert_receive {:deadline_ms, voice_budget}

      text = Stations.create_session()
      assert {:ok, _reply} = Stations.create_message(text.session_id, %{text: "Quando?"})
      assert_receive {:deadline_ms, text_budget}

      for budget <- [voice_budget, text_budget], do: assert(budget in 2_000..2_345)
    end

    # Issue #269: the voice reply follows the #257 stage-direction rule, so the
    # worker never reads a nonverbal action aloud. The transcript keeps the full
    # verified reply, as on the text path.
    test "process_voice_turn/3 returns reply_text without stage directions" do
      Application.put_env(:backend, :station_ai_adapter, TemplateReplyAIAdapter)
      Process.put(:template_reply_text, "*(curvado, com a mão na barriga)* Começou ontem. (geme)")
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, %{reply_text: "Começou ontem.", turn_id: 1}} =
               Stations.process_voice_turn(session.session_id, 1, "Quando começou?")

      assert {:ok, stored} = Stations.get_session(session.session_id)

      assert [%{role: :learner}, %{role: :patient, text: full}] = stored.messages
      assert full == "*(curvado, com a mão na barriga)* Começou ontem. (geme)"
    end

    test "a voice reply made only of stage directions keeps the learner turn" do
      Application.put_env(:backend, :station_ai_adapter, TemplateReplyAIAdapter)
      Process.put(:template_reply_text, "*(suspira e olha para o chão)*")
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, {:kept, %{turn_id: 1, generation_id: 1, refusal: :unspeakable}}} =
               Stations.process_voice_turn(session.session_id, 1, "Como o senhor está?")

      assert {:ok, stored} = Stations.get_session(session.session_id)
      assert [%{role: :learner, text: "Como o senhor está?"}] = stored.messages
      assert stored.failed_voice_turn == nil
      assert {:ok, nil} = Conversation.active_generation(session.session_id)
    end

    test "provider and model errors remain technical failures on retry without text or regeneration" do
      Application.put_env(:backend, :station_ai_adapter, TestFailureAdapter)
      Process.put(:voice_turn_test_pid, self())

      for reason <- [
            :service_unavailable,
            :timeout,
            :network_error,
            :malformed_response,
            :model_error
          ] do
        Process.put(:voice_turn_test_error, reason)
        session = Stations.create_session(%{audio_consent: true})

        assert {:error, :station_ai_unavailable} =
                 Stations.process_voice_turn(session.session_id, 1, "Learner question")

        assert_receive :failed_adapter_called

        assert {:error, :station_ai_unavailable} =
                 Stations.process_voice_turn(session.session_id, 1, "Learner question")

        refute_receive :failed_adapter_called
        assert {:ok, stored} = Stations.get_session(session.session_id)
        assert [%{role: :learner, text: "Learner question"}] = stored.messages
        assert {:ok, nil} = Conversation.active_generation(session.session_id)
      end
    end

    test "late provider failure cannot overwrite a newer pending or failed generation" do
      Application.put_env(:backend, :station_ai_adapter, TestSlowBarrierAdapter)
      Application.put_env(:backend, :voice_turn_test_pid, self())

      for newer_outcome <- [:pending, :failed] do
        session = Stations.create_session(%{audio_consent: true})
        first = Task.async(fn -> Stations.process_voice_turn(session.session_id, 1, "First") end)
        assert_receive {:adapter_called, _}, 1000

        second =
          Task.async(fn -> Stations.process_voice_turn(session.session_id, 2, "Second") end)

        assert_receive {:adapter_called, _}, 1000

        if newer_outcome == :failed do
          send(second.pid, {:fail_adapter, :model_error})
          assert Task.await(second) == {:error, :station_ai_unavailable}
        end

        send(first.pid, {:fail_adapter, :timeout})
        assert Task.await(first) == {:error, :stale_generation}
        assert {:ok, :duplicate} = Stations.process_voice_turn(session.session_id, 1, "First")

        if newer_outcome == :pending do
          assert {:ok, 2} = Conversation.active_generation(session.session_id)
          send(second.pid, {:resume_adapter, "A dor começou durante uma caminhada."})
          assert {:ok, %{turn_id: 2}} = Task.await(second)
        else
          assert {:error, :station_ai_unavailable} =
                   Stations.process_voice_turn(session.session_id, 2, "Second")

          assert {:ok, stored} = Stations.get_session(session.session_id)
          assert Enum.map(stored.messages, & &1.role) == [:learner, :learner]
          assert stored.failed_voice_turn.generation_id == 2
        end
      end
    end

    test "late provider failure respects cancellation, completion, expiry and discard" do
      Application.put_env(:backend, :station_ai_adapter, TestSlowBarrierAdapter)
      Application.put_env(:backend, :voice_turn_test_pid, self())

      for boundary <- [:cancelled, :completed, :expired, :discarded] do
        session = Stations.create_session(%{audio_consent: true})

        task =
          Task.async(fn -> Stations.process_voice_turn(session.session_id, 1, "Question") end)

        assert_receive {:adapter_called, _}, 1000

        expected =
          case boundary do
            :cancelled ->
              assert {:ok, :cancelled} =
                       Stations.cancel_voice_turn(session.session_id, turn_id: 1)

              :stale_generation

            :completed ->
              assert {:ok, _} = Stations.complete_session(session.session_id)
              :completed

            :expired ->
              {:ok, stored} = Stations.get_session(session.session_id)

              :ets.insert(
                Conversation,
                {session.session_id, %{stored | expires_at: session.started_at}}
              )

              :expired

            :discarded ->
              assert :ok = Stations.discard_session(session.session_id)
              :not_found
          end

        send(task.pid, {:fail_adapter, :model_error})
        assert Task.await(task) == {:error, expected}

        if boundary in [:cancelled, :completed] do
          assert {:ok, stored} = Stations.get_session(session.session_id)
          assert stored.failed_voice_turn == nil
          assert [%{role: :learner}] = stored.messages
        else
          assert {:error, :not_found} = Stations.get_session(session.session_id)
        end
      end
    end

    for rule_id <- ["length-cap", "max-length"] do
      test "process_voice_turn/3 denies a reply exceeding #{rule_id} without committing patient content" do
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

        # 36 characters, one over the cap
        Application.put_env(:backend, :station_ai_adapter, TestRevealableFactsAdapter)
        session = Stations.create_session(%{audio_consent: true})

        assert {:error, :station_ai_unavailable} =
                 Stations.process_voice_turn(session.session_id, 1, "Quando começou a dor?")

        assert {:ok, updated_session} = Stations.get_session(session.session_id)
        assert [%{role: :learner, text: "Quando começou a dor?"}] = updated_session.messages
        assert updated_session.failed_voice_turn.turn_id == 1
        assert {:ok, nil} = Conversation.active_generation(session.session_id)

        assert {:error, :station_ai_unavailable} =
                 Stations.process_voice_turn(session.session_id, 1, "Quando começou a dor?")

        assert {:ok, unchanged_session} = Stations.get_session(session.session_id)
        assert unchanged_session.messages == updated_session.messages
      end
    end

    test "process_voice_turn/3 commits the verified reply and updates session" do
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
      # used_facts are the ones the verified reply carries, never re-derived from its text
      assert result.used_facts == []

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

    test "process_voice_turn/3 returns a Jev-approved reply verbatim with the used_facts it carries" do
      Application.put_env(:backend, :station_ai_adapter, TestNaturalReplyWithFactsAdapter)
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, result} =
               Stations.process_voice_turn(
                 session.session_id,
                 1,
                 "Quando começou a dor no peito?"
               )

      # Not an exact package fact: Jev approved it, so it is spoken as written
      assert result.reply_text ==
               "Começou quando eu estava caminhando, doutor, e ainda não passou."

      assert result.used_facts == [
               %{"topic" => "onset", "content" => "A dor começou durante uma caminhada."}
             ]

      {:ok, updated_session} = Stations.get_session(session.session_id)
      patient = List.last(updated_session.messages)
      assert patient.role == :patient
      assert patient.modality == :voice
      assert patient.text == result.reply_text
    end

    test "process_voice_turn/3 delivers the reply Jev replaced through regeneration" do
      Application.put_env(:backend, :station_ai_adapter, TestRegeneratingAdapter)
      Application.put_env(:backend, :jev_decision_adapter, RefuseThenVerifyAdapter)
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, result} =
               Stations.process_voice_turn(
                 session.session_id,
                 1,
                 "Quando começou a dor no peito?"
               )

      assert result.reply_text == "Foi durante uma caminhada, doutor."
      # Facts claimed by the refused candidate never survive the replacement
      assert result.used_facts == []

      {:ok, updated_session} = Stations.get_session(session.session_id)
      assert [%{role: :learner}, %{role: :patient, text: text}] = updated_session.messages
      assert text == "Foi durante uma caminhada, doutor."
    end

    test "process_voice_turn/3 never commits or returns a fabricated assertion Jev refuses" do
      Application.put_env(:backend, :station_ai_adapter, TestFabricatedClinicalAdapter)
      Application.put_env(:backend, :jev_decision_adapter, TestRefusingJevAdapter)
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, {:kept, %{turn_id: 1, generation_id: 1, refusal: :semantic_refusal}}} =
               Stations.process_voice_turn(
                 session.session_id,
                 1,
                 "Você toma algum remédio para o estômago?"
               )

      {:ok, updated_session} = Stations.get_session(session.session_id)

      assert [%{role: :learner, text: "Você toma algum remédio para o estômago?"}] =
               updated_session.messages
    end

    test "process_voice_turn/3 never commits or returns a reply without usable text" do
      Application.put_env(:backend, :station_ai_adapter, TemplateReplyAIAdapter)
      Process.put(:template_reply_text, "   ")
      session = Stations.create_session(%{audio_consent: true})

      assert {:error, :station_ai_unavailable} =
               Stations.process_voice_turn(session.session_id, 1, "Quando começou a dor?")

      {:ok, updated_session} = Stations.get_session(session.session_id)
      assert [%{role: :learner, text: "Quando começou a dor?"}] = updated_session.messages
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

    test "cancel_voice_turn with expected turn_id cancels matching active turn" do
      session = Stations.create_session(%{audio_consent: true})

      Application.put_env(:backend, :station_ai_adapter, TestSlowBarrierAdapter)
      Application.put_env(:backend, :voice_turn_test_pid, self())

      task =
        Task.async(fn ->
          Stations.process_voice_turn(
            session.session_id,
            1,
            "Pergunta para cancelamento por turn_id"
          )
        end)

      assert_receive {:adapter_called, _context}, 1000

      # Cancel with matching expected turn_id
      assert {:ok, :cancelled} =
               Stations.cancel_voice_turn(session.session_id, turn_id: 1)

      send(task.pid, {:resume_adapter, "A dor começou durante uma caminhada."})
      assert Task.await(task) == {:error, :stale_generation}
    end

    test "delayed cancellation of earlier turn_id returns :stale_generation and does not invalidate newer turn" do
      session = Stations.create_session(%{audio_consent: true})

      Application.put_env(:backend, :station_ai_adapter, TestSlowBarrierAdapter)
      Application.put_env(:backend, :voice_turn_test_pid, self())

      task1 =
        Task.async(fn ->
          Stations.process_voice_turn(session.session_id, 1, "Pergunta 1")
        end)

      assert_receive {:adapter_called, _ctx1}, 1000

      # Newer turn 2 arrives and starts generation
      task2 =
        Task.async(fn ->
          Stations.process_voice_turn(session.session_id, 2, "Pergunta 2")
        end)

      assert_receive {:adapter_called, _ctx2}, 1000

      # Delayed cancellation for turn 1 arrives late
      assert {:error, :stale_generation} =
               Stations.cancel_voice_turn(session.session_id, turn_id: 1)

      # Resume turn 1: superseded by turn 2
      send(task1.pid, {:resume_adapter, "Resposta descartada 1"})
      assert Task.await(task1) == {:error, :stale_generation}

      # Turn 2 is untouched and resolves with authorized fact
      send(task2.pid, {:resume_adapter, "A dor começou durante uma caminhada."})

      assert {:ok, result} = Task.await(task2)
      assert result.turn_id == 2
      assert result.reply_text == "A dor começou durante uma caminhada."
    end

    test "cancel_voice_turn and process_voice_turn enforce completed and expired session boundaries" do
      session = Stations.create_session(%{audio_consent: true})
      {:ok, _} = Stations.complete_session(session.session_id)

      assert Stations.cancel_voice_turn(session.session_id, turn_id: 1) == {:error, :completed}
      assert Stations.process_voice_turn(session.session_id, 1, "Fala") == {:error, :completed}

      prev_timeout = Application.get_env(:backend, :conversation_timeout_ms)
      Application.put_env(:backend, :conversation_timeout_ms, 0)

      try do
        expired1 = Stations.create_session(%{audio_consent: true})
        assert Stations.cancel_voice_turn(expired1.session_id, turn_id: 1) == {:error, :expired}

        expired2 = Stations.create_session(%{audio_consent: true})
        assert Stations.process_voice_turn(expired2.session_id, 1, "Fala") == {:error, :expired}
      after
        if prev_timeout,
          do: Application.put_env(:backend, :conversation_timeout_ms, prev_timeout),
          else: Application.delete_env(:backend, :conversation_timeout_ms)
      end
    end

    test "process_voice_turn/3 handles duplicate and older turn_ids idempotently" do
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, %{turn_id: 2}} =
               Stations.process_voice_turn(session.session_id, 2, "Segunda pergunta")

      assert {:ok, :duplicate} =
               Stations.process_voice_turn(session.session_id, 2, "Segunda repetida")

      assert {:ok, :duplicate} =
               Stations.process_voice_turn(session.session_id, 1, "Primeira atrasada")

      {:ok, current} = Stations.get_session(session.session_id)
      # Exactly learner + patient messages from turn 2
      assert length(current.messages) == 2
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

  describe "station deadline on voice turns (#201)" do
    setup do
      original_duration = Application.get_env(:backend, :station_duration_ms)
      original_grace = Application.get_env(:backend, :turn_grace_ms)

      on_exit(fn ->
        restore_env(:station_duration_ms, original_duration)
        restore_env(:turn_grace_ms, original_grace)
      end)

      Application.put_env(:backend, :station_ai_adapter, TestSlowBarrierAdapter)
      Application.put_env(:backend, :voice_turn_test_pid, self())

      :ok
    end

    test "a voice turn after the deadline returns :station_time_elapsed and leaves the transcript untouched" do
      Application.put_env(:backend, :station_duration_ms, 300)
      Application.put_env(:backend, :turn_grace_ms, 3_000)

      session = Stations.create_session(%{audio_consent: true})

      # A generation in flight keeps the session active past the deadline.
      first = Task.async(fn -> Stations.process_voice_turn(session.session_id, 1, "Fala") end)
      assert_receive {:adapter_called, _}, 1000

      Process.sleep(450)
      assert {:ok, %{status: :active} = before_reject} = Stations.get_session(session.session_id)

      assert {:error, :station_time_elapsed} =
               Stations.process_voice_turn(session.session_id, 2, "Chegou tarde")

      refute_receive {:adapter_called, _}

      assert {:ok, after_reject} = Stations.get_session(session.session_id)
      assert after_reject.messages == before_reject.messages
      assert after_reject.last_voice_turn_id == 1
      assert {:ok, 1} = Conversation.active_generation(session.session_id)

      send(first.pid, {:resume_adapter, "A dor começou durante uma caminhada."})
      assert {:ok, %{turn_id: 1}} = Task.await(first)
    end

    test "a voice turn on a session completed by the timer returns :station_time_elapsed" do
      Application.put_env(:backend, :station_duration_ms, 30)
      session = Stations.create_session(%{audio_consent: true})

      wait_until(fn ->
        match?({:ok, %{status: :completed}}, Stations.get_session(session.session_id))
      end)

      assert {:error, :station_time_elapsed} =
               Stations.process_voice_turn(session.session_id, 1, "Chegou tarde")

      assert {:error, :station_time_elapsed} =
               Stations.commit_voice_transcript(session.session_id, 1, "Chegou tarde")

      refute_receive {:adapter_called, _}

      assert {:ok, %{messages: [], completion_reason: :timer}} =
               Stations.get_session(session.session_id)
    end

    test "a generation cut off by the deadline returns :station_time_elapsed when its reply resolves after grace" do
      Application.put_env(:backend, :station_duration_ms, 200)
      Application.put_env(:backend, :turn_grace_ms, 100)

      session = Stations.create_session(%{audio_consent: true})
      task = Task.async(fn -> Stations.process_voice_turn(session.session_id, 1, "Fala") end)
      assert_receive {:adapter_called, _}, 1000

      # Let both the deadline and the grace window elapse without a reply.
      wait_until(fn ->
        match?({:ok, %{status: :completed}}, Stations.get_session(session.session_id))
      end)

      assert {:ok, forced} = Stations.get_session(session.session_id)
      assert forced.completion_reason == :timer
      assert forced.messages == []

      send(task.pid, {:resume_adapter, "A dor começou durante uma caminhada."})
      assert Task.await(task) == {:error, :station_time_elapsed}

      # Not a technical failure: nothing is recorded against the generation.
      assert {:ok, ^forced} = Stations.get_session(session.session_id)
      assert Map.get(forced, :failed_voice_turn) == nil
    end

    test "a reply resolving inside the grace window succeeds and the timer completes the session" do
      Application.put_env(:backend, :station_duration_ms, 300)
      Application.put_env(:backend, :turn_grace_ms, 3_000)

      session = Stations.create_session(%{audio_consent: true})
      task = Task.async(fn -> Stations.process_voice_turn(session.session_id, 1, "Fala") end)
      assert_receive {:adapter_called, _}, 1000

      # Past the deadline, inside the grace window.
      Process.sleep(450)
      assert {:ok, %{status: :active}} = Stations.get_session(session.session_id)

      send(task.pid, {:resume_adapter, "A dor começou durante uma caminhada."})

      assert {:ok,
              %{
                reply_text: "A dor começou durante uma caminhada.",
                turn_id: 1,
                generation_id: 1
              }} = Task.await(task)

      assert {:ok, completed} = Stations.get_session(session.session_id)
      assert completed.status == :completed
      assert completed.completion_reason == :timer

      assert Enum.map(completed.messages, &{&1.role, &1.text}) == [
               {:learner, "Fala"},
               {:patient, "A dor começou durante uma caminhada."}
             ]
    end

    test "a session completed for another reason still returns :completed" do
      session = Stations.create_session(%{audio_consent: true})
      assert {:ok, _} = Stations.complete_session(session.session_id)

      assert {:error, :completed} = Stations.process_voice_turn(session.session_id, 1, "Fala")

      assert {:error, :completed} =
               Stations.commit_voice_transcript(session.session_id, 1, "Fala")
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

  defp restore_env(key, nil), do: Application.delete_env(:backend, key)
  defp restore_env(key, value), do: Application.put_env(:backend, key, value)

  defp wait_until(fun, attempts \\ 100)

  defp wait_until(_fun, 0), do: flunk("condition not met in time")

  defp wait_until(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(20)
      wait_until(fun, attempts - 1)
    end
  end
end
