defmodule Backend.Stations.PreDeliveryGateContractTest do
  use BackendWeb.ConnCase, async: false

  alias Backend.Stations
  alias Backend.Stations.StationLoader

  # ============================================================================
  # Test Adapter Doubles
  # ============================================================================

  defmodule VerifyingJevDouble do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request) do
      {:ok, %{status: :verified, rationale: "Verified candidate grounded in facts"}}
    end

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  defmodule ExplosiveJevDouble do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request) do
      raise "ExplosiveJevDouble invoked! Deny-first checks MUST reject candidate before reaching Jev!"
    end

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  defmodule RefusingJevDouble do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request) do
      {:ok, %{status: :semantic_refusal, rationale: "Semantic refusal: outside package facts"}}
    end

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  defmodule LowConfidenceJevDouble do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request) do
      {:ok, %{status: :low_confidence, rationale: "Low confidence: clinical grounding uncertain"}}
    end

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  defmodule RefuseThenVerifyJevDouble do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request) do
      case Application.get_env(:backend, :refuse_then_verify_count, 0) do
        0 ->
          Application.put_env(:backend, :refuse_then_verify_count, 1)
          {:ok, %{status: :semantic_refusal, rationale: "First candidate refused"}}

        _ ->
          {:ok, %{status: :verified, rationale: "Second candidate verified"}}
      end
    end

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  defmodule RefuseThenTimeoutJevDouble do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request) do
      case Application.get_env(:backend, :refuse_then_verify_count, 0) do
        0 ->
          Application.put_env(:backend, :refuse_then_verify_count, 1)
          {:ok, %{status: :low_confidence, rationale: "First candidate undecided"}}

        _ ->
          {:error, :timeout}
      end
    end

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  defmodule TimeoutJevDouble do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request) do
      {:error, :timeout}
    end

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  defmodule Upstream5xxJevDouble do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request) do
      {:error, {:upstream_5xx, 503}}
    end

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  defmodule BlockingJevDouble do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request) do
      parent =
        Process.get(:blocking_jev_test_pid) ||
          Application.get_env(:backend, :blocking_jev_test_pid)

      if parent, do: send(parent, {:jev_verification_started, self()})

      receive do
        :jev_verification_release ->
          {:ok, %{status: :verified, rationale: "Approved after unblock"}}
      after
        2_000 ->
          {:error, :timeout}
      end
    end

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  defmodule ConfigurableAIAdapter do
    @behaviour Backend.Stations.StationAI

    @impl true
    def next_reply(_package, _context) do
      case Process.get(:custom_ai_reply) do
        nil ->
          {:ok, %{text: "Estou sentindo um aperto no peito há 2 horas.", used_facts: []}}

        reply_fun when is_function(reply_fun, 0) ->
          reply_fun.()

        {:ok, _} = res ->
          res

        {:error, _} = res ->
          res

        text when is_binary(text) ->
          {:ok, %{text: text, used_facts: []}}
      end
    end
  end

  # ============================================================================
  # Setup
  # ============================================================================

  setup do
    prev_ai = Application.get_env(:backend, :station_ai_adapter)
    prev_jev = Application.get_env(:backend, :jev_decision_adapter)

    Application.put_env(:backend, :station_ai_adapter, ConfigurableAIAdapter)
    Application.put_env(:backend, :jev_decision_adapter, VerifyingJevDouble)

    on_exit(fn ->
      if prev_ai,
        do: Application.put_env(:backend, :station_ai_adapter, prev_ai),
        else: Application.delete_env(:backend, :station_ai_adapter)

      if prev_jev,
        do: Application.put_env(:backend, :jev_decision_adapter, prev_jev),
        else: Application.delete_env(:backend, :jev_decision_adapter)

      Application.delete_env(:backend, :blocking_jev_test_pid)
      Application.delete_env(:backend, :refuse_then_verify_count)
    end)

    pkg = StationLoader.active_package()
    session = Stations.create_session(%{audio_consent: true})

    {:ok, session: session, pkg: pkg}
  end

  # ============================================================================
  # Requirement 4(a): Verified candidate passes Context and HTTP Delivery
  # ============================================================================

  describe "Requirement 4(a): Verified candidate delivery" do
    test "verified candidate passes through Stations.create_message/2 and is appended to session history",
         %{session: session} do
      assert {:ok, reply} =
               Stations.create_message(session.session_id, %{
                 role: :learner,
                 modality: :text,
                 text: "Quando começou a dor?"
               })

      assert reply.reply_text == "Estou sentindo um aperto no peito há 2 horas."
      assert reply.reply_audio_url == nil
      assert is_list(reply.used_facts)

      assert {:ok, fetched} = Stations.get_session(session.session_id)
      assert length(fetched.messages) == 2

      learner_msg = Enum.at(fetched.messages, 0)
      assert learner_msg.role == :learner
      assert learner_msg.text == "Quando começou a dor?"

      patient_msg = Enum.at(fetched.messages, 1)
      assert patient_msg.role == :patient
      assert patient_msg.text == reply.reply_text
    end

    test "verified candidate passes through StationController, returns HTTP 200, and is stored in session history",
         %{conn: conn, session: session} do
      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
          "role" => "learner",
          "modality" => "text",
          "text" => "Como está o peito?"
        })

      response = json_response(conn, 200)

      assert %{
               "reply_text" => "Estou sentindo um aperto no peito há 2 horas.",
               "reply_audio_url" => nil,
               "server_now" => server_now_str
             } = response

      assert {:ok, _, _} = DateTime.from_iso8601(server_now_str)

      assert {:ok, fetched} = Stations.get_session(session.session_id)
      assert length(fetched.messages) == 2
      assert hd(fetched.messages).role == :learner
      assert List.last(fetched.messages).role == :patient
      assert List.last(fetched.messages).text == "Estou sentindo um aperto no peito há 2 horas."
    end
  end

  # ============================================================================
  # Requirement 4(b): Denied candidate rejected before Jev, rolled back, HTTP 502
  # ============================================================================

  describe "Requirement 4(b): Denied candidate (deny-first, rollback, HTTP 502, no text leak)" do
    test "malformed / empty reply is rejected before Jev, learner turn rolled back, HTTP 502",
         %{conn: conn, session: session} do
      # Explosive adapter proves deterministic deny checks fire BEFORE Jev
      Application.put_env(:backend, :jev_decision_adapter, ExplosiveJevDouble)
      Process.put(:custom_ai_reply, "")

      assert {:error, {:denied, :malformed}} =
               Stations.create_message(session.session_id, %{
                 role: :learner,
                 modality: :text,
                 text: "Olá paciente"
               })

      # Learner message was rolled back: session messages empty
      assert {:ok, fetched} = Stations.get_session(session.session_id)
      assert fetched.messages == []

      # Via HTTP
      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
          "role" => "learner",
          "modality" => "text",
          "text" => "Olá paciente via HTTP"
        })

      assert json_response(conn, 502) == %{
               "error" => "reply_verification_failed",
               "message" => "A verificação de segurança da resposta do paciente falhou."
             }

      assert {:ok, fetched_after_http} = Stations.get_session(session.session_id)
      assert fetched_after_http.messages == []
    end

    test "roleplay leakage candidate is rejected before Jev, learner turn rolled back, HTTP 502 without text leak",
         %{conn: conn, session: session} do
      Application.put_env(:backend, :jev_decision_adapter, ExplosiveJevDouble)
      leaked_text = "Sou uma IA e não posso sentir dor física real."
      Process.put(:custom_ai_reply, leaked_text)

      assert {:error, {:denied, :roleplay_leakage}} =
               Stations.create_message(session.session_id, %{
                 role: :learner,
                 modality: :text,
                 text: "Você é real?"
               })

      assert {:ok, fetched} = Stations.get_session(session.session_id)
      assert fetched.messages == []

      # Via HTTP: verify no candidate text in response
      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
          "role" => "learner",
          "modality" => "text",
          "text" => "Você é uma inteligência artificial?"
        })

      assert json_response(conn, 502) == %{
               "error" => "reply_verification_failed",
               "message" => "A verificação de segurança da resposta do paciente falhou."
             }

      refute String.contains?(conn.resp_body, "Sou uma IA")
      refute String.contains?(conn.resp_body, leaked_text)

      assert {:ok, fetched_after_http} = Stations.get_session(session.session_id)
      assert fetched_after_http.messages == []
    end

    test "english marker candidate is rejected before Jev, learner turn rolled back, HTTP 502",
         %{conn: conn, session: session} do
      Application.put_env(:backend, :jev_decision_adapter, ExplosiveJevDouble)
      english_text = "Hello, I am experiencing severe chest pain for 2 hours."
      Process.put(:custom_ai_reply, english_text)

      assert {:error, {:denied, :language_containment}} =
               Stations.create_message(session.session_id, %{
                 role: :learner,
                 modality: :text,
                 text: "How are you?"
               })

      assert {:ok, fetched} = Stations.get_session(session.session_id)
      assert fetched.messages == []

      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
          "role" => "learner",
          "modality" => "text",
          "text" => "How are you feeling?"
        })

      assert json_response(conn, 502) == %{
               "error" => "reply_verification_failed",
               "message" => "A verificação de segurança da resposta do paciente falhou."
             }

      refute String.contains?(conn.resp_body, "Hello")
      refute String.contains?(conn.resp_body, english_text)

      assert {:ok, fetched_after_http} = Stations.get_session(session.session_id)
      assert fetched_after_http.messages == []
    end

    test "response rules violation candidate is rejected before Jev",
         %{pkg: pkg} do
      Application.put_env(:backend, :jev_decision_adapter, ExplosiveJevDouble)

      pkg_with_rules =
        Map.put(pkg, "response_rules", [
          %{"id" => "polite"},
          %{"id" => "length-cap", "max_length" => 15}
        ])

      # 1. Polite rule violation
      offensive_text = "Você é um idiota e não sabe nada."

      assert {:error, {:denied, :response_rules}} =
               Stations.verify_patient_reply(pkg_with_rules, offensive_text)

      # 2. Length-cap violation
      long_text = "Esta resposta é muito longa para o limite permitido."

      assert {:error, {:denied, :response_rules}} =
               Stations.verify_patient_reply(pkg_with_rules, long_text)
    end
  end

  # ============================================================================
  # Requirement 4(c): Semantic refusal / low confidence after retry
  # ============================================================================

  describe "Requirement 4(c): Semantic refusal / low confidence after retry" do
    test "semantic refusal exhaust retry budget: no text in history, learner turn kept, HTTP 502",
         %{conn: conn, session: session} do
      Application.put_env(:backend, :jev_decision_adapter, RefusingJevDouble)
      refused_text = "Eu acho que tive um infarto quando era criança no Japão."
      Process.put(:custom_ai_reply, refused_text)

      assert {:error, {:refused, :semantic_refusal, learner_turn}} =
               Stations.create_message(session.session_id, %{
                 role: :learner,
                 modality: :text,
                 text: "Você já infartou antes?"
               })

      assert {:ok, fetched} = Stations.get_session(session.session_id)
      assert fetched.messages == [learner_turn]

      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
          "role" => "learner",
          "modality" => "text",
          "text" => "Você já infartou antes?"
        })

      assert %{
               "error" => "reply_verification_failed",
               "message" => "A verificação de segurança da resposta do paciente falhou.",
               "learner_turn" => %{"role" => "learner", "text" => _}
             } = json_response(conn, 502)

      refute String.contains?(conn.resp_body, "Japão")
      refute String.contains?(conn.resp_body, refused_text)

      assert {:ok, fetched_after_http} = Stations.get_session(session.session_id)
      assert Enum.map(fetched_after_http.messages, & &1.role) == [:learner, :learner]
    end

    test "low confidence exhaust retry budget: no text in history, learner turn kept, HTTP 502",
         %{conn: conn, session: session} do
      Application.put_env(:backend, :jev_decision_adapter, LowConfidenceJevDouble)
      uncertain_text = "Talvez seja meu coração, não sei bem."
      Process.put(:custom_ai_reply, uncertain_text)

      assert {:error, {:refused, :low_confidence, learner_turn}} =
               Stations.create_message(session.session_id, %{
                 role: :learner,
                 modality: :text,
                 text: "O que você acha que é?"
               })

      assert {:ok, fetched} = Stations.get_session(session.session_id)
      assert fetched.messages == [learner_turn]

      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
          "role" => "learner",
          "modality" => "text",
          "text" => "O que você acha que é?"
        })

      assert %{
               "error" => "reply_verification_failed",
               "message" => "A verificação de segurança da resposta do paciente falhou.",
               "learner_turn" => %{"role" => "learner", "text" => _}
             } = json_response(conn, 502)

      refute String.contains?(conn.resp_body, uncertain_text)

      assert {:ok, fetched_after_http} = Stations.get_session(session.session_id)
      assert Enum.map(fetched_after_http.messages, & &1.role) == [:learner, :learner]
    end

    # Issue #256: the regeneration after a refusal cannot be verified in time.
    # The learner turn is kept (#235) and no patient text is stored or returned.
    test "a refusal whose regeneration verification times out keeps the learner turn, HTTP 502",
         %{conn: conn, session: session} do
      Application.put_env(:backend, :jev_decision_adapter, RefuseThenTimeoutJevDouble)
      refused_text = "Meu abdome está flácido e indolor à palpação."
      Process.put(:custom_ai_reply, refused_text)

      assert {:error, {:refused, :low_confidence, learner_turn}} =
               Stations.create_message(session.session_id, %{
                 role: :learner,
                 modality: :text,
                 text: "Examinador, quais os achados do exame abdominal?"
               })

      assert {:ok, fetched} = Stations.get_session(session.session_id)
      assert fetched.messages == [learner_turn]

      Application.put_env(:backend, :refuse_then_verify_count, 0)

      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
          "role" => "learner",
          "modality" => "text",
          "text" => "Examinador, quais os achados do exame abdominal?"
        })

      assert %{
               "error" => "reply_verification_failed",
               "learner_turn" => %{"role" => "learner", "text" => _}
             } = json_response(conn, 502)

      refute String.contains?(conn.resp_body, refused_text)

      assert {:ok, fetched_after_http} = Stations.get_session(session.session_id)
      assert Enum.map(fetched_after_http.messages, & &1.role) == [:learner, :learner]
    end

    test "a refusal whose regeneration outruns the deadline keeps the learner turn",
         %{session: session} do
      Application.put_env(:backend, :jev_decision_adapter, RefusingJevDouble)
      Process.put(:custom_ai_reply, "Tenho dor do lado direito da barriga.")

      slow_regeneration = fn ->
        Process.sleep(80)
        {:ok, %{text: "Resposta tardia que nunca deve aparecer.", used_facts: []}}
      end

      assert {:error, {:refused, :semantic_refusal, learner_turn}} =
               Stations.create_message(session.session_id, %{
                 role: :learner,
                 modality: :text,
                 text: "Examinador, e os exames laboratoriais?",
                 deadline_ms: 50,
                 generator: fn _pkg, _conv, _remaining_ms, _guidance -> slow_regeneration.() end
               })

      assert {:ok, fetched} = Stations.get_session(session.session_id)
      assert fetched.messages == [learner_turn]
      refute Enum.any?(fetched.messages, &(&1.role == :patient))
    end

    test "semantic refusal followed by successful retry delivers verified reply and HTTP 200",
         %{conn: conn, session: session} do
      Application.put_env(:backend, :jev_decision_adapter, RefuseThenVerifyJevDouble)
      Application.put_env(:backend, :refuse_then_verify_count, 0)

      # Generator returns clean text on retry
      Process.put(
        :custom_ai_reply,
        "Estou sentindo um aperto forte no peito há 2 horas."
      )

      assert {:ok, reply} =
               Stations.create_message(session.session_id, %{
                 role: :learner,
                 modality: :text,
                 text: "Descreva seus sintomas"
               })

      assert reply.reply_text == "Estou sentindo um aperto forte no peito há 2 horas."

      assert {:ok, fetched} = Stations.get_session(session.session_id)
      assert length(fetched.messages) == 2
      assert List.last(fetched.messages).text == reply.reply_text

      # Reset count for HTTP test
      Application.put_env(:backend, :refuse_then_verify_count, 0)
      session_http = Stations.create_session(%{audio_consent: true})

      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session_http.session_id}/messages", %{
          "role" => "learner",
          "modality" => "text",
          "text" => "Descreva seus sintomas via HTTP"
        })

      assert json_response(conn, 200)["reply_text"] ==
               "Estou sentindo um aperto forte no peito há 2 horas."

      assert {:ok, fetched_http} = Stations.get_session(session_http.session_id)
      assert length(fetched_http.messages) == 2
    end
  end

  # ============================================================================
  # Requirement 4(d): Technical failures invalidate attempt, no fallback, 502/504
  # ============================================================================

  describe "Requirement 4(d): Technical failures (adapter disabled, upstream 5xx, timeout)" do
    test "adapter disabled invalidates attempt, no fallback fabricated, HTTP 502",
         %{conn: conn, session: session} do
      Application.put_env(
        :backend,
        :jev_decision_adapter,
        Backend.Stations.JevDecision.DisabledAdapter
      )

      assert {:error, {:adapter_disabled, _}} =
               Stations.create_message(session.session_id, %{
                 role: :learner,
                 modality: :text,
                 text: "Qual é o diagnóstico?"
               })

      assert {:ok, fetched} = Stations.get_session(session.session_id)
      assert fetched.messages == []

      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
          "role" => "learner",
          "modality" => "text",
          "text" => "Qual é o diagnóstico?"
        })

      assert json_response(conn, 502) == %{
               "error" => "station_ai_unavailable",
               "message" => "O serviço da estação de IA está temporariamente indisponível."
             }

      # Zero clinical fallback text fabricated (e.g. canonical refusal is NOT emitted)
      refute String.contains?(conn.resp_body, "Não tenho essa informação")
      refute String.contains?(conn.resp_body, "Estou bem")

      assert {:ok, fetched_after_http} = Stations.get_session(session.session_id)
      assert fetched_after_http.messages == []
    end

    test "upstream 5xx invalidates attempt, no fallback fabricated, HTTP 502",
         %{conn: conn, session: session} do
      Application.put_env(:backend, :jev_decision_adapter, Upstream5xxJevDouble)

      assert {:error, {:upstream_5xx, 503}} =
               Stations.create_message(session.session_id, %{
                 role: :learner,
                 modality: :text,
                 text: "Como você se sente?"
               })

      assert {:ok, fetched} = Stations.get_session(session.session_id)
      assert fetched.messages == []

      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
          "role" => "learner",
          "modality" => "text",
          "text" => "Como você se sente?"
        })

      assert json_response(conn, 502) == %{
               "error" => "station_ai_unavailable",
               "message" => "O serviço da estação de IA está temporariamente indisponível."
             }

      refute String.contains?(conn.resp_body, "Não tenho essa informação")

      assert {:ok, fetched_after_http} = Stations.get_session(session.session_id)
      assert fetched_after_http.messages == []
    end

    test "timeout invalidates attempt, no fallback fabricated, HTTP 504",
         %{conn: conn, session: session} do
      Application.put_env(:backend, :jev_decision_adapter, TimeoutJevDouble)

      assert {:error, :timeout} =
               Stations.create_message(session.session_id, %{
                 role: :learner,
                 modality: :text,
                 text: "Dor há quanto tempo?"
               })

      assert {:ok, fetched} = Stations.get_session(session.session_id)
      assert fetched.messages == []

      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
          "role" => "learner",
          "modality" => "text",
          "text" => "Dor há quanto tempo?"
        })

      assert json_response(conn, 504) == %{
               "error" => "timeout",
               "message" => "A verificação da resposta do paciente excedeu o tempo limite."
             }

      refute String.contains?(conn.resp_body, "Não tenho essa informação")

      assert {:ok, fetched_after_http} = Stations.get_session(session.session_id)
      assert fetched_after_http.messages == []
    end
  end

  # ============================================================================
  # Requirement 4(e): Stale / cancelled decisions
  # ============================================================================

  describe "Requirement 4(e): Stale / cancelled decisions" do
    setup do
      original_duration = Application.get_env(:backend, :station_duration_ms)
      original_grace = Application.get_env(:backend, :turn_grace_ms)

      on_exit(fn ->
        if is_nil(original_duration),
          do: Application.delete_env(:backend, :station_duration_ms),
          else: Application.put_env(:backend, :station_duration_ms, original_duration)

        if is_nil(original_grace),
          do: Application.delete_env(:backend, :turn_grace_ms),
          else: Application.put_env(:backend, :turn_grace_ms, original_grace)
      end)

      :ok
    end

    test "session completed by user while verification running: late approval rejected and NOT appended to session",
         %{session: session} do
      Application.put_env(:backend, :jev_decision_adapter, BlockingJevDouble)
      Application.put_env(:backend, :blocking_jev_test_pid, self())
      Application.put_env(:backend, :turn_grace_ms, 50)

      task =
        Task.async(fn ->
          Stations.create_message(session.session_id, %{
            role: :learner,
            modality: :text,
            text: "Conte-me seus sintomas enquanto a sessão conclui"
          })
        end)

      # 1. Wait for verification to start (the learner turn is pending, not yet settled)
      assert_receive {:jev_verification_started, adapter_pid}, 1_000

      # 2. While verification is in-flight, complete session with :user reason.
      #    Completion is deferred for the bounded grace window, then the
      #    unanswered learner turn is rolled back and the session completes.
      assert {:ok, completed_session} = Stations.complete_session(session.session_id, :user)
      assert completed_session.status == :completed
      orig_completed_at = completed_session.completed_at
      orig_completion_reason = completed_session.completion_reason

      # 3. Unblock Jev verification to emit approval
      send(adapter_pid, :jev_verification_release)

      # 4. Await task completion: the late approval is rejected
      assert Task.await(task, 2_000) == {:error, :station_time_elapsed}

      # 5. Verify late approval was NOT appended to session history
      assert {:ok, final_session} = Stations.get_session(session.session_id)
      assert final_session.status == :completed
      assert final_session.completed_at == orig_completed_at
      assert final_session.completion_reason == orig_completion_reason
      assert final_session.messages == []
      refute Enum.any?(final_session.messages, &(&1.role == :patient))
    end

    test "session completed by timer while verification running: late approval rejected and NOT appended to session" do
      Application.put_env(:backend, :jev_decision_adapter, BlockingJevDouble)
      Application.put_env(:backend, :blocking_jev_test_pid, self())
      Application.put_env(:backend, :turn_grace_ms, 50)

      # A deadline inside the timer-finish tolerance window makes the :timer
      # completion legitimate while still leaving room to accept the turn.
      Application.put_env(:backend, :station_duration_ms, 1_000)
      session = Stations.create_session(%{audio_consent: true})

      task =
        Task.async(fn ->
          Stations.create_message(session.session_id, %{
            role: :learner,
            modality: :text,
            text: "O tempo acabou antes da verificação retornar"
          })
        end)

      assert_receive {:jev_verification_started, adapter_pid}, 1_000

      # Complete with :timer reason
      assert {:ok, completed_session} = Stations.complete_session(session.session_id, :timer)
      assert completed_session.status == :completed
      assert completed_session.completion_reason == :timer

      send(adapter_pid, :jev_verification_release)
      assert Task.await(task, 2_000) == {:error, :station_time_elapsed}

      assert {:ok, final_session} = Stations.get_session(session.session_id)
      assert final_session.status == :completed
      assert final_session.completion_reason == :timer
      assert final_session.messages == []
      refute Enum.any?(final_session.messages, &(&1.role == :patient))
    end
  end

  # ============================================================================
  # Requirement 4(f): Voice / TTS coordination (#119–#121)
  # ============================================================================

  describe "Requirement 4(f): Voice / TTS coordination (#119–#121)" do
    test "create_message leaves reply_audio_url: nil and never synthesizes unapproved audio",
         %{conn: conn, session: session} do
      # 1. On successful verification: reply_audio_url is explicitly nil
      assert {:ok, reply} =
               Stations.create_message(session.session_id, %{
                 role: :learner,
                 modality: :text,
                 text: "Sente dor no peito?"
               })

      assert reply.reply_audio_url == nil

      # Via HTTP: reply_audio_url is nil in JSON contract
      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
          "role" => "learner",
          "modality" => "text",
          "text" => "Qual é a intensidade da dor?"
        })

      assert json_response(conn, 200)["reply_audio_url"] == nil

      # 2. When verification fails (denied), zero audio URL is returned
      Application.put_env(:backend, :jev_decision_adapter, ExplosiveJevDouble)
      Process.put(:custom_ai_reply, "Sou uma IA e não sinto dor")

      new_session = Stations.create_session(%{audio_consent: true})

      assert {:error, {:denied, _}} =
               Stations.create_message(new_session.session_id, %{
                 role: :learner,
                 modality: :text,
                 text: "Pergunta teste"
               })

      # Session has no unapproved messages or audio
      assert {:ok, empty_session} = Stations.get_session(new_session.session_id)
      assert empty_session.messages == []
    end
  end

  # ============================================================================
  # Issue #147: Trusted case-state projection (learner_turns)
  # ============================================================================

  describe "trusted case-state projection (issue #147)" do
    defp package_with_templates(pkg, templates),
      do: Map.put(pkg, "approved_templates", templates)

    defp learner_msg(text), do: %{role: :learner, modality: :text, text: text}

    defp patient_msg(text), do: %{role: :patient, modality: :text, text: text}

    test "verify_patient_reply/3 derives learner_turns from the received conversation and bypasses at the turn count",
         %{pkg: pkg} do
      Application.put_env(:backend, :jev_decision_adapter, ExplosiveJevDouble)

      template_text = "Estou sentindo uma dor no peito há duas horas."

      pkg =
        package_with_templates(pkg, [
          %{
            "template_id" => "min-turns-2",
            "text" => template_text,
            "applicability" => %{"type" => "min_learner_turns", "count" => 2}
          }
        ])

      # Two learner turns (one atom-keyed, one string-keyed role label) meet
      # the count of 2; the patient message must not inflate it. ExplosiveJevDouble
      # proves the bypassed candidate never reaches Jev.
      assert {:ok, verified} =
               Stations.verify_patient_reply(pkg, template_text,
                 conversation: [
                   learner_msg("Quando começou a dor?"),
                   patient_msg("Há duas horas."),
                   %{"role" => "learner", "modality" => "text", "text" => "Onde dói?"}
                 ]
               )

      assert verified == template_text
    end

    test "verify_patient_reply/3 routes the same byte-identical candidate to Jev below the turn count",
         %{pkg: pkg} do
      Application.put_env(:backend, :jev_decision_adapter, RefusingJevDouble)

      template_text = "Estou sentindo uma dor no peito há duas horas."

      pkg =
        package_with_templates(pkg, [
          %{
            "template_id" => "min-turns-2",
            "text" => template_text,
            "applicability" => %{"type" => "min_learner_turns", "count" => 2}
          }
        ])

      # Only one learner turn exists, so the predicate fails closed and the
      # candidate routes to Jev (which refuses it).
      assert {:error, {:refused, :semantic_refusal}} =
               Stations.verify_patient_reply(pkg, template_text,
                 conversation: [
                   learner_msg("Quando começou a dor?"),
                   patient_msg("Há duas horas.")
                 ]
               )
    end

    test "learner_turns counts only learner-role messages: a patient-only conversation projects zero",
         %{pkg: pkg} do
      template_text = "Obrigado pela conversa, doutor."

      min_one_pkg =
        package_with_templates(pkg, [
          %{
            "template_id" => "min-turns-1",
            "text" => template_text,
            "applicability" => %{"type" => "min_learner_turns", "count" => 1}
          }
        ])

      max_two_pkg =
        package_with_templates(pkg, [
          %{
            "template_id" => "max-turns-2",
            "text" => template_text,
            "applicability" => %{"type" => "max_learner_turns", "count" => 2}
          }
        ])

      # Three patient messages project learner_turns: 0, so even a count of 1
      # fails closed and routes to Jev.
      Application.put_env(:backend, :jev_decision_adapter, RefusingJevDouble)

      assert {:error, {:refused, :semantic_refusal}} =
               Stations.verify_patient_reply(min_one_pkg, template_text,
                 conversation: [
                   patient_msg("Bom dia."),
                   patient_msg("Há duas horas."),
                   patient_msg("Sim, doutor.")
                 ]
               )

      # Two learner turns plus three patient messages stay at learner_turns: 2;
      # if patient messages were counted, the max-of-2 predicate would fail
      # closed and reach ExplosiveJevDouble.
      Application.put_env(:backend, :jev_decision_adapter, ExplosiveJevDouble)

      assert {:ok, verified} =
               Stations.verify_patient_reply(max_two_pkg, template_text,
                 conversation: [
                   learner_msg("Quando começou?"),
                   patient_msg("Há duas horas."),
                   learner_msg("Onde dói?"),
                   patient_msg("No peito."),
                   patient_msg("Desde ontem.")
                 ]
               )

      assert verified == template_text
    end

    test "verify_patient_reply/3 with no conversation data projects learner_turns: 0 and fails closed",
         %{pkg: pkg} do
      Application.put_env(:backend, :jev_decision_adapter, RefusingJevDouble)

      template_text = "Estou sentindo uma dor no peito há duas horas."

      pkg =
        package_with_templates(pkg, [
          %{
            "template_id" => "min-turns-1",
            "text" => template_text,
            "applicability" => %{"type" => "min_learner_turns", "count" => 1}
          }
        ])

      # Absent conversation is an explicitly empty-safe source: the derived
      # state is %{learner_turns: 0} and the predicate fails closed to Jev.
      assert {:error, {:refused, :semantic_refusal}} =
               Stations.verify_patient_reply(pkg, template_text)
    end
  end
end
