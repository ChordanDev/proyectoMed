defmodule BackendWeb.StationControllerTest do
  use BackendWeb.ConnCase, async: false

  alias Backend.Stations
  alias Backend.Stations.Conversation
  alias Backend.Stations.StationLoader

  defmodule TestSuccessAdapter do
    @behaviour Backend.Stations.StationAI
    @impl true
    def next_reply(_package, _context) do
      {:ok, %{text: "Estou com um aperto forte no peito há duas horas."}}
    end
  end

  defmodule TestErrorAdapter do
    @behaviour Backend.Stations.StationAI
    @impl true
    def next_reply(_package, _context) do
      {:error, :provider_down}
    end
  end

  defmodule BlockingStationAIAdapter do
    @behaviour Backend.Stations.StationAI
    @impl true
    def next_reply(_package, _context) do
      parent = Application.get_env(:backend, :blocking_adapter_test_pid)
      send(parent, :station_ai_started)

      receive do
        :station_ai_release ->
          {:ok, %{text: "Resposta do paciente gerada durante conclusão"}}
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

  # Returns the patient verdict configured under :controller_test_jev_patient_result,
  # so one test can drive refusals, technical failures, and recovery.
  defmodule ConfigurableJevAdapter do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request) do
      Application.fetch_env!(:backend, :controller_test_jev_patient_result)
    end

    @impl true
    def decide_rubric(_request) do
      {:error, :not_implemented}
    end
  end

  # Starts its reply with the addressee marker of :controller_test_addressee
  # (#309): the generation decides the addressee.
  defmodule MarkedAddresseeAdapter do
    @behaviour Backend.Stations.StationAI

    @impl true
    def next_reply(_package, _context) do
      case Application.fetch_env!(:backend, :controller_test_addressee) do
        :examiner -> {:ok, %{text: "[EXAMINADOR]"}}
        :patient -> {:ok, %{text: "[PACIENTE] Estou com um aperto forte no peito há duas horas."}}
      end
    end
  end

  # Verifies every patient reply of the addressee tests.
  defmodule AddresseeJevAdapter do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request), do: {:ok, %{status: :verified}}

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  setup do
    prev_jev_adapter = Application.get_env(:backend, :jev_decision_adapter)
    Application.put_env(:backend, :jev_decision_adapter, TestVerifyingJevAdapter)

    on_exit(fn ->
      Application.delete_env(:backend, :controller_test_jev_patient_result)

      if prev_jev_adapter do
        Application.put_env(:backend, :jev_decision_adapter, prev_jev_adapter)
      else
        Application.delete_env(:backend, :jev_decision_adapter)
      end
    end)

    :ok
  end

  describe "GET /api/stations/active" do
    test "returns active station metadata", %{conn: conn} do
      conn = get(conn, ~p"/api/stations/active")

      package = Stations.get_active_package()

      assert json_response(conn, 200) == %{
               "station_id" => "chest-pain-initial-assessment",
               "version" => "2.0.0",
               "language" => "pt-BR",
               "display_title" => "Avaliação inicial de dor torácica",
               "candidate_brief" => package["candidate_brief"],
               "voice_mode" => "turn"
             }
    end

    test "serves the configured voice mode (#270)", %{conn: conn} do
      previous = Application.get_env(:backend, :voice_mode)
      on_exit(fn -> Application.put_env(:backend, :voice_mode, previous) end)

      for mode <- ["realtime", "turn", "off"] do
        Application.put_env(:backend, :voice_mode, mode)
        body = conn |> recycle() |> get(~p"/api/stations/active") |> json_response(200)
        assert body["voice_mode"] == mode
      end
    end

    test "returns the brief and nothing examiner-only (#239)", %{conn: conn} do
      conn = get(conn, ~p"/api/stations/active")

      body = json_response(conn, 200)
      assert %{"scenario" => scenario, "tasks" => [_ | _]} = body["candidate_brief"]
      assert is_binary(scenario) and scenario != ""

      raw = Jason.encode!(body)
      package = Stations.get_active_package()

      hidden =
        ["rubric", "expected_actions", "impressos", "patient_profile", "revealable_facts"] ++
          Enum.map(package["rubric"], & &1["id"]) ++
          Enum.map(package["expected_actions"], & &1["id"]) ++
          Enum.flat_map(package["impressos"] || [], &[&1["id"], &1["title"]]) ++
          [package["patient_profile"]["presenting_context"]]

      for secret <- hidden do
        refute String.contains?(raw, secret), "active station exposes: #{secret}"
      end
    end

    test "returns the boot-loaded active version", %{conn: conn} do
      conn = get(conn, ~p"/api/stations/active")

      assert %{"version" => version} = json_response(conn, 200)
      assert version == Stations.active_version()
    end
  end

  describe "POST /api/stations/active/sessions" do
    test "starts a session with audio_consent=true, persists it, and returns session contract", %{
      conn: conn
    } do
      conn = post(conn, ~p"/api/stations/active/sessions", %{"audio_consent" => true})

      response = json_response(conn, 200)

      assert %{
               "session_id" => session_id,
               "station_id" => station_id,
               "station_version" => station_version,
               "audio_consent" => true,
               "started_at" => started_at_str,
               "expires_at" => expires_at_str,
               "server_now" => server_now_str
             } = response

      active_pkg = Stations.get_active_package()
      assert station_id == active_pkg["station_id"]
      assert station_version == active_pkg["version"]

      assert {:ok, started_at, _} = DateTime.from_iso8601(started_at_str)
      assert {:ok, expires_at, _} = DateTime.from_iso8601(expires_at_str)
      assert {:ok, server_now, _} = DateTime.from_iso8601(server_now_str)

      assert DateTime.diff(expires_at, started_at, :second) == 30 * 60
      assert abs(DateTime.diff(server_now, started_at, :second)) <= 2

      # Verifies persistence in Backend.Stations
      assert {:ok, session} = Stations.get_session(session_id)
      assert session.session_id == session_id
      assert session.station_id == station_id
      assert session.station_version == station_version
      assert session.audio_consent == true
      assert session.status == :active
    end

    test "starts a session with audio_consent=false and persists it", %{conn: conn} do
      conn = post(conn, ~p"/api/stations/active/sessions", %{"audio_consent" => false})

      response = json_response(conn, 200)

      assert %{
               "session_id" => session_id,
               "audio_consent" => false
             } = response

      assert {:ok, session} = Conversation.fetch(session_id)
      assert session.audio_consent == false
    end

    test "rejects request when audio_consent is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/stations/active/sessions", %{})

      assert json_response(conn, 400) == %{
               "error" => "invalid_parameters",
               "message" =>
                 "Parâmetros inválidos: 'audio_consent' é obrigatório e deve ser um booleano."
             }
    end

    test "rejects request when audio_consent is a string", %{conn: conn} do
      conn = post(conn, ~p"/api/stations/active/sessions", %{"audio_consent" => "true"})

      assert json_response(conn, 400) == %{
               "error" => "invalid_parameters",
               "message" =>
                 "Parâmetros inválidos: 'audio_consent' é obrigatório e deve ser um booleano."
             }
    end

    test "rejects request when audio_consent is an integer", %{conn: conn} do
      conn = post(conn, ~p"/api/stations/active/sessions", %{"audio_consent" => 1})

      assert json_response(conn, 400) == %{
               "error" => "invalid_parameters",
               "message" =>
                 "Parâmetros inválidos: 'audio_consent' é obrigatório e deve ser um booleano."
             }
    end

    test "rejects request when audio_consent is nil", %{conn: conn} do
      conn = post(conn, ~p"/api/stations/active/sessions", %{"audio_consent" => nil})

      assert json_response(conn, 400) == %{
               "error" => "invalid_parameters",
               "message" =>
                 "Parâmetros inválidos: 'audio_consent' é obrigatório e deve ser um booleano."
             }
    end
  end

  describe "GET /api/stations/active/sessions/:id" do
    setup do
      pkg = StationLoader.active_package()

      session =
        Conversation.start(%{
          station_id: pkg["station_id"],
          station_version: pkg["version"],
          audio_consent: true
        })

      %{session: session}
    end

    test "returns the session contract for an active session, including its deadline_at", %{
      conn: conn,
      session: session
    } do
      conn = get(conn, ~p"/api/stations/active/sessions/#{session.session_id}")

      response = json_response(conn, 200)

      assert %{
               "session_id" => session_id,
               "station_id" => station_id,
               "station_version" => station_version,
               "audio_consent" => true,
               "started_at" => _started_at,
               "expires_at" => _expires_at,
               "deadline_at" => deadline_at_str,
               "status" => "active",
               "completion_reason" => nil,
               "messages" => [],
               "server_now" => server_now_str
             } = response

      assert session_id == session.session_id
      assert station_id == session.station_id
      assert station_version == session.station_version
      assert {:ok, deadline_at, _} = DateTime.from_iso8601(deadline_at_str)
      assert DateTime.to_iso8601(session.deadline_at) == DateTime.to_iso8601(deadline_at)
      assert {:ok, _, _} = DateTime.from_iso8601(server_now_str)
    end

    test "a refresh/reconnect (repeated GET) returns the same deadline_at (does not reset)", %{
      conn: conn,
      session: session
    } do
      conn1 = get(conn, ~p"/api/stations/active/sessions/#{session.session_id}")
      %{"deadline_at" => deadline_at_1} = json_response(conn1, 200)

      Process.sleep(20)

      conn2 = get(conn, ~p"/api/stations/active/sessions/#{session.session_id}")
      %{"deadline_at" => deadline_at_2} = json_response(conn2, 200)

      assert deadline_at_1 == deadline_at_2
    end

    test "reflects completion_reason once the session is completed", %{
      conn: conn,
      session: session
    } do
      {:ok, _} = Conversation.complete(session.session_id, :user)

      conn = get(conn, ~p"/api/stations/active/sessions/#{session.session_id}")

      assert %{"status" => "completed", "completion_reason" => "user"} = json_response(conn, 200)
    end

    test "includes the transcript so far, so a refresh can restore it", %{
      conn: conn,
      session: session
    } do
      prev_adapter = Application.get_env(:backend, :station_ai_adapter)
      Application.put_env(:backend, :station_ai_adapter, TestSuccessAdapter)

      on_exit(fn ->
        if prev_adapter do
          Application.put_env(:backend, :station_ai_adapter, prev_adapter)
        else
          Application.delete_env(:backend, :station_ai_adapter)
        end
      end)

      post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
        "role" => "learner",
        "modality" => "text",
        "text" => "Bom dia, o que você está sentindo?"
      })

      conn = get(conn, ~p"/api/stations/active/sessions/#{session.session_id}")

      assert %{
               "messages" => [
                 %{
                   "role" => "learner",
                   "modality" => "text",
                   "text" => "Bom dia, o que você está sentindo?",
                   "at" => learner_at
                 },
                 %{
                   "role" => "patient",
                   "modality" => "text",
                   "text" => "Estou com um aperto forte no peito há duas horas.",
                   "at" => patient_at
                 }
               ]
             } = json_response(conn, 200)

      assert {:ok, _, _} = DateTime.from_iso8601(learner_at)
      assert {:ok, _, _} = DateTime.from_iso8601(patient_at)
    end

    test "returns 404 on unknown session id", %{conn: conn} do
      conn = get(conn, ~p"/api/stations/active/sessions/unknown-session")

      assert json_response(conn, 404) == %{
               "error" => "session_not_found",
               "message" => "Sessão não encontrada."
             }
    end

    test "returns 410 on expired session", %{conn: conn} do
      original_timeout = Application.get_env(:backend, :conversation_timeout_ms)
      Application.put_env(:backend, :conversation_timeout_ms, 0)

      expired_session =
        try do
          pkg = StationLoader.active_package()

          Conversation.start(%{
            station_id: pkg["station_id"],
            station_version: pkg["version"],
            audio_consent: false
          })
        after
          if is_nil(original_timeout) do
            Application.delete_env(:backend, :conversation_timeout_ms)
          else
            Application.put_env(:backend, :conversation_timeout_ms, original_timeout)
          end
        end

      conn = get(conn, ~p"/api/stations/active/sessions/#{expired_session.session_id}")

      assert json_response(conn, 410) == %{
               "error" => "session_expired",
               "message" => "A sessão expirou."
             }
    end
  end

  describe "POST /api/stations/active/sessions/:id/messages" do
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

      pkg = StationLoader.active_package()

      session =
        Conversation.start(%{
          station_id: pkg["station_id"],
          station_version: pkg["version"],
          audio_consent: true
        })

      {:ok, session: session}
    end

    test "advances the session conversation and returns bounded reply contract", %{
      conn: conn,
      session: session
    } do
      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
          "role" => "learner",
          "modality" => "text",
          "text" => "Bom dia, o que você está sentindo?"
        })

      response = json_response(conn, 200)

      assert %{
               "reply_text" => "Estou com um aperto forte no peito há duas horas.",
               "reply_audio_url" => nil,
               "server_now" => server_now_str
             } = response

      assert {:ok, server_now, _} = DateTime.from_iso8601(server_now_str)
      assert abs(DateTime.diff(server_now, DateTime.utc_now(), :second)) <= 2

      # Verify conversation history contains both learner message and patient reply
      assert {:ok, updated_session} = Conversation.fetch(session.session_id)
      assert length(updated_session.messages) == 2

      [msg1, msg2] = updated_session.messages
      assert msg1.role == :learner
      assert msg1.modality == :text
      assert msg1.text == "Bom dia, o que você está sentindo?"

      assert msg2.role == :patient
      assert msg2.modality == :text
      assert msg2.text == "Estou com um aperto forte no peito há duas horas."
    end

    test "accepts voice modality", %{conn: conn, session: session} do
      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
          "role" => "learner",
          "modality" => "voice",
          "text" => "Olá, sou o médico."
        })

      assert %{"reply_text" => "Estou com um aperto forte no peito há duas horas."} =
               json_response(conn, 200)

      assert {:ok, updated_session} = Conversation.fetch(session.session_id)
      [msg1, _msg2] = updated_session.messages
      assert msg1.role == :learner
      assert msg1.modality == :voice
    end

    test "rejects a message over 2,000 characters with 422 message_too_long", %{
      conn: conn,
      session: session
    } do
      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
          "role" => "learner",
          "modality" => "text",
          "text" => String.duplicate("a", 2_001)
        })

      assert json_response(conn, 422) == %{
               "error" => "message_too_long",
               "message" => "Mensagem muito longa: o limite é de 2.000 caracteres."
             }

      assert {:ok, unchanged} = Conversation.fetch(session.session_id)
      assert unchanged.messages == []
    end

    test "rejects missing role", %{conn: conn, session: session} do
      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
          "modality" => "text",
          "text" => "Olá"
        })

      assert json_response(conn, 400) == %{
               "error" => "invalid_message",
               "message" =>
                 "Mensagem inválida: 'role' deve ser 'learner', 'modality' deve ser 'voice' ou 'text', e 'text' não pode ser vazio."
             }
    end

    test "rejects invalid role (e.g. patient)", %{conn: conn, session: session} do
      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
          "role" => "patient",
          "modality" => "text",
          "text" => "Olá"
        })

      assert json_response(conn, 400) == %{
               "error" => "invalid_message",
               "message" =>
                 "Mensagem inválida: 'role' deve ser 'learner', 'modality' deve ser 'voice' ou 'text', e 'text' não pode ser vazio."
             }
    end

    test "rejects missing modality", %{conn: conn, session: session} do
      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
          "role" => "learner",
          "text" => "Olá"
        })

      assert json_response(conn, 400) == %{
               "error" => "invalid_message",
               "message" =>
                 "Mensagem inválida: 'role' deve ser 'learner', 'modality' deve ser 'voice' ou 'text', e 'text' não pode ser vazio."
             }
    end

    test "rejects invalid modality", %{conn: conn, session: session} do
      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
          "role" => "learner",
          "modality" => "pigeon",
          "text" => "Olá"
        })

      assert json_response(conn, 400) == %{
               "error" => "invalid_message",
               "message" =>
                 "Mensagem inválida: 'role' deve ser 'learner', 'modality' deve ser 'voice' ou 'text', e 'text' não pode ser vazio."
             }
    end

    test "rejects missing text or empty text", %{conn: conn, session: session} do
      for empty_text <- ["", "   ", "\t\n", nil, 123] do
        conn_attempt =
          post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
            "role" => "learner",
            "modality" => "text",
            "text" => empty_text
          })

        assert json_response(conn_attempt, 400) == %{
                 "error" => "invalid_message",
                 "message" =>
                   "Mensagem inválida: 'role' deve ser 'learner', 'modality' deve ser 'voice' ou 'text', e 'text' não pode ser vazio."
               }
      end
    end

    test "returns 404 on unknown session id", %{conn: conn} do
      conn =
        post(conn, ~p"/api/stations/active/sessions/nonexistent-session-id/messages", %{
          "role" => "learner",
          "modality" => "text",
          "text" => "Olá"
        })

      assert json_response(conn, 404) == %{
               "error" => "session_not_found",
               "message" => "Sessão não encontrada."
             }
    end

    test "returns 410 on expired session", %{conn: conn} do
      original_timeout = Application.get_env(:backend, :conversation_timeout_ms)
      Application.put_env(:backend, :conversation_timeout_ms, 0)

      session =
        try do
          pkg = StationLoader.active_package()

          Conversation.start(%{
            station_id: pkg["station_id"],
            station_version: pkg["version"],
            audio_consent: false
          })
        after
          if is_nil(original_timeout) do
            Application.delete_env(:backend, :conversation_timeout_ms)
          else
            Application.put_env(:backend, :conversation_timeout_ms, original_timeout)
          end
        end

      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
          "role" => "learner",
          "modality" => "text",
          "text" => "Olá"
        })

      assert json_response(conn, 410) == %{
               "error" => "session_expired",
               "message" => "A sessão expirou."
             }
    end

    test "returns 422 on completed session", %{conn: conn, session: session} do
      {:ok, _} = Conversation.complete(session.session_id, "time_up")

      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
          "role" => "learner",
          "modality" => "text",
          "text" => "Olá"
        })

      assert json_response(conn, 422) == %{
               "error" => "session_completed",
               "message" => "A sessão já foi concluída."
             }
    end

    test "returns 502 when StationAI provider fails", %{conn: conn, session: session} do
      Application.put_env(:backend, :station_ai_adapter, TestErrorAdapter)

      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
          "role" => "learner",
          "modality" => "text",
          "text" => "Como você está?"
        })

      assert json_response(conn, 502) == %{
               "error" => "station_ai_unavailable",
               "message" => "O serviço da estação de IA está temporariamente indisponível."
             }
    end

    for refusal <- [:low_confidence, :semantic_refusal] do
      test "returns 502 reply_verification_failed when Jev refuses with #{refusal}, keeping the session active",
           %{conn: conn, session: session} do
        use_configurable_jev({:ok, %{status: unquote(refusal), rationale: "refused"}})

        refused_conn = post_learner_text(conn, session, "Olá, qual é o seu nome?")

        assert %{
                 "error" => "reply_verification_failed",
                 "message" => "A verificação de segurança da resposta do paciente falhou.",
                 "learner_turn" => learner_turn
               } = json_response(refused_conn, 502)

        assert Map.keys(json_response(refused_conn, 502)) ==
                 ["error", "learner_turn", "message"]

        assert %{"role" => "learner", "modality" => "text", "text" => "Olá, qual é o seu nome?"} =
                 learner_turn

        assert {:ok, _at, _offset} = DateTime.from_iso8601(learner_turn["at"])

        refute refused_conn.resp_body =~ "aperto forte no peito"

        # The learner turn is kept without a patient reply and the session
        # stays active; the stored turn is the one returned in the body.
        assert %{"status" => "active", "completion_reason" => nil, "messages" => [^learner_turn]} =
                 conn
                 |> get(~p"/api/stations/active/sessions/#{session.session_id}")
                 |> json_response(200)

        # A follow-up message on the same session is delivered normally.
        use_configurable_jev({:ok, %{status: :verified}})

        retry_conn = post_learner_text(conn, session, "Olá, qual é o seu nome?")

        assert json_response(retry_conn, 200)["reply_text"] ==
                 "Estou com um aperto forte no peito há duas horas."

        assert {:ok, updated_session} = Conversation.fetch(session.session_id)
        assert Enum.map(updated_session.messages, & &1.role) == [:learner, :learner, :patient]
      end
    end

    for failure <- [{:technical_failure, :missing_credentials}, :network_error] do
      test "returns 502 station_ai_unavailable when Jev fails technically with #{inspect(failure)}",
           %{conn: conn, session: session} do
        use_configurable_jev({:error, unquote(Macro.escape(failure))})

        conn = post_learner_text(conn, session, "Olá, qual é o seu nome?")

        assert json_response(conn, 502) == %{
                 "error" => "station_ai_unavailable",
                 "message" => "O serviço da estação de IA está temporariamente indisponível."
               }

        refute conn.resp_body =~ "aperto forte no peito"
        assert {:ok, %{messages: []}} = Conversation.fetch(session.session_id)
      end
    end

    test "returns 409 station_time_elapsed for a turn received at/after the deadline", %{
      conn: conn
    } do
      original_duration = Application.get_env(:backend, :station_duration_ms)
      Application.put_env(:backend, :station_duration_ms, 30)

      on_exit(fn ->
        if is_nil(original_duration) do
          Application.delete_env(:backend, :station_duration_ms)
        else
          Application.put_env(:backend, :station_duration_ms, original_duration)
        end
      end)

      pkg = StationLoader.active_package()

      late_session =
        Conversation.start(%{
          station_id: pkg["station_id"],
          station_version: pkg["version"],
          audio_consent: true
        })

      Process.sleep(60)

      conn =
        post(conn, ~p"/api/stations/active/sessions/#{late_session.session_id}/messages", %{
          "role" => "learner",
          "modality" => "text",
          "text" => "Chegou tarde"
        })

      assert json_response(conn, 409) == %{
               "error" => "station_time_elapsed",
               "message" => "O tempo da estação se esgotou."
             }

      assert {:ok, unchanged} = Conversation.fetch(late_session.session_id)
      assert unchanged.messages == []
    end

    test "accepted pending turn resolves before a racing manual completion finalizes", %{
      conn: conn,
      session: session
    } do
      Application.put_env(:backend, :station_ai_adapter, BlockingStationAIAdapter)
      Application.put_env(:backend, :blocking_adapter_test_pid, self())

      on_exit(fn ->
        Application.delete_env(:backend, :blocking_adapter_test_pid)
      end)

      # Launch create_message in an async task through the HTTP controller seam
      task =
        Task.async(fn ->
          post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
            "role" => "learner",
            "modality" => "text",
            "text" => "Olá, conte-me seus sintomas."
          })
        end)

      # 1. Wait for notification that StationAI has started (learner message append already happened)
      assert_receive :station_ai_started, 1_000

      # Verify learner message was already appended before StationAI returned
      {:ok, session_during_gen} = Conversation.fetch(session.session_id)
      assert length(session_during_gen.messages) == 1
      assert hd(session_during_gen.messages).role == :learner

      # 2. While blocked, a manual completion arrives for the same session. Since a
      # turn is pending (the learner message was accepted before the deadline), the
      # completion call is deferred instead of racing the in-flight reply away —
      # run it from a separate process so this test can still release the barrier.
      complete_task = Task.async(fn -> Conversation.complete(session.session_id, :user) end)

      # 3. Release the adapter barrier
      send(task.pid, :station_ai_release)

      # 4. Await HTTP message request response
      conn_result = Task.await(task, 2_000)

      # Assert response is controlled (200 and expected reply contract)
      assert %{
               "reply_text" => "Resposta do paciente gerada durante conclusão",
               "reply_audio_url" => nil,
               "server_now" => server_now_str
             } = json_response(conn_result, 200)

      assert {:ok, _, _} = DateTime.from_iso8601(server_now_str)

      # 5. The deferred completion finalizes once the turn resolves
      assert {:ok, completed_session} = Task.await(complete_task, 2_000)
      assert completed_session.status == :completed
      assert completed_session.completion_reason == :user

      # Assert the pending patient reply WAS appended before completion, and the
      # session is completed with the manual reason.
      {:ok, final_session} = Conversation.fetch(session.session_id)
      assert final_session.status == :completed
      assert final_session.completion_reason == :user
      assert length(final_session.messages) == 2
      [msg1, msg2] = final_session.messages
      assert msg1.role == :learner
      assert msg2.role == :patient
      assert msg2.text == "Resposta do paciente gerada durante conclusão"
    end
  end

  describe "POST /api/stations/active/sessions/:id/messages addressee (#274, #309)" do
    setup do
      prev_adapter = Application.get_env(:backend, :station_ai_adapter)
      Application.put_env(:backend, :station_ai_adapter, MarkedAddresseeAdapter)
      Application.put_env(:backend, :jev_decision_adapter, AddresseeJevAdapter)

      on_exit(fn ->
        Application.put_env(:backend, :station_ai_adapter, prev_adapter)
        Application.delete_env(:backend, :controller_test_addressee)
      end)

      pkg = StationLoader.active_package()

      session =
        Conversation.start(%{
          station_id: pkg["station_id"],
          station_version: pkg["version"],
          audio_consent: false
        })

      {:ok, session: session}
    end

    test "an examiner-addressed turn answers 200 examiner_acknowledged with the kept turn",
         %{conn: conn, session: session} do
      Application.put_env(:backend, :controller_test_addressee, :examiner)

      body = conn |> post_learner_text(session, "Blumberg positivo.") |> json_response(200)

      assert %{
               "outcome" => "examiner_acknowledged",
               "reply_text" => nil,
               "learner_turn" => %{"role" => "learner", "text" => "Blumberg positivo."},
               "server_now" => _
             } = body

      assert {:ok, %{messages: [%{role: :learner}]}} = Conversation.fetch(session.session_id)
      assert body["newly_released"] == []
    end

    test "an examiner-addressed exam request answers with the newly released impressos (#302)",
         %{conn: conn, session: session} do
      Application.put_env(:backend, :controller_test_addressee, :examiner)

      body =
        conn |> post_learner_text(session, "Solicito hemograma e PCR") |> json_response(200)

      assert %{
               "outcome" => "examiner_acknowledged",
               "newly_released" => [
                 %{
                   "id" => "laboratorio-sangue-enzimas",
                   "title" => "IMPRESSO" <> _,
                   "category" => _,
                   "content" => _
                 }
               ]
             } = body
    end

    test "a patient-addressed turn answers 200 patient_reply with the reply",
         %{conn: conn, session: session} do
      Application.put_env(:backend, :controller_test_addressee, :patient)

      assert %{
               "outcome" => "patient_reply",
               "reply_text" => "Estou com um aperto forte no peito há duas horas."
             } = conn |> post_learner_text(session, "Bom dia.") |> json_response(200)
    end
  end

  describe "POST /api/stations/active/sessions/:id/finish" do
    setup do
      pkg = StationLoader.active_package()

      session =
        Conversation.start(%{
          station_id: pkg["station_id"],
          station_version: pkg["version"],
          audio_consent: true
        })

      %{session: session}
    end

    test "finishes session with reason=user", %{conn: conn, session: session} do
      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/finish", %{
          "reason" => "user"
        })

      assert %{
               "session_id" => session_id,
               "status" => "completed",
               "completed_at" => completed_at_str
             } = json_response(conn, 200)

      assert session_id == session.session_id
      assert {:ok, completed_at, _} = DateTime.from_iso8601(completed_at_str)
      assert DateTime.diff(DateTime.utc_now(), completed_at, :second) <= 2

      {:ok, updated_session} = Conversation.fetch(session.session_id)
      assert updated_session.status == :completed
      assert updated_session.completion_reason == :user
    end

    test "finishes session with reason=timer", %{conn: conn} do
      # Timer finishes are only accepted at/after the deadline (within a small
      # tolerance): shrink station_duration_ms so the deadline is already reached.
      original_duration = Application.get_env(:backend, :station_duration_ms)
      Application.put_env(:backend, :station_duration_ms, 0)

      on_exit(fn ->
        if is_nil(original_duration) do
          Application.delete_env(:backend, :station_duration_ms)
        else
          Application.put_env(:backend, :station_duration_ms, original_duration)
        end
      end)

      pkg = StationLoader.active_package()

      session =
        Conversation.start(%{
          station_id: pkg["station_id"],
          station_version: pkg["version"],
          audio_consent: true
        })

      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/finish", %{
          "reason" => "timer"
        })

      assert %{
               "session_id" => session_id,
               "status" => "completed",
               "completed_at" => completed_at_str
             } = json_response(conn, 200)

      assert session_id == session.session_id
      assert {:ok, _completed_at, _} = DateTime.from_iso8601(completed_at_str)

      {:ok, updated_session} = Conversation.fetch(session.session_id)
      assert updated_session.status == :completed
      assert updated_session.completion_reason == :timer
    end

    test "finishes session with omitted body (defaults to user)", %{
      conn: conn,
      session: session
    } do
      conn = post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/finish")

      assert %{
               "session_id" => session_id,
               "status" => "completed",
               "completed_at" => completed_at_str
             } = json_response(conn, 200)

      assert session_id == session.session_id
      assert {:ok, _completed_at, _} = DateTime.from_iso8601(completed_at_str)

      {:ok, updated_session} = Conversation.fetch(session.session_id)
      assert updated_session.status == :completed
      assert updated_session.completion_reason == :user
    end

    test "rejects invalid or non-string reason", %{conn: conn, session: session} do
      for invalid_reason <- ["timeout", "cancelled", "", 123, true, ["user"], %{}] do
        conn_attempt =
          post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/finish", %{
            "reason" => invalid_reason
          })

        assert json_response(conn_attempt, 400) == %{
                 "error" => "invalid_reason",
                 "message" => "Motivo de finalização inválido: deve ser 'user' ou 'timer'."
               }
      end
    end

    test "returns 404 on unknown session id", %{conn: conn} do
      conn =
        post(conn, ~p"/api/stations/active/sessions/nonexistent-session/finish", %{
          "reason" => "user"
        })

      assert json_response(conn, 404) == %{
               "error" => "session_not_found",
               "message" => "Sessão não encontrada."
             }
    end

    test "returns 410 on expired session", %{conn: conn} do
      original_timeout = Application.get_env(:backend, :conversation_timeout_ms)
      Application.put_env(:backend, :conversation_timeout_ms, 0)

      expired_session =
        try do
          pkg = StationLoader.active_package()

          Conversation.start(%{
            station_id: pkg["station_id"],
            station_version: pkg["version"],
            audio_consent: false
          })
        after
          if is_nil(original_timeout) do
            Application.delete_env(:backend, :conversation_timeout_ms)
          else
            Application.put_env(:backend, :conversation_timeout_ms, original_timeout)
          end
        end

      conn =
        post(conn, ~p"/api/stations/active/sessions/#{expired_session.session_id}/finish", %{
          "reason" => "user"
        })

      assert json_response(conn, 410) == %{
               "error" => "session_expired",
               "message" => "A sessão expirou."
             }
    end

    test "repeated finish is idempotent, preserves original completed_at and completion_reason",
         %{conn: conn, session: session} do
      conn1 =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/finish", %{
          "reason" => "user"
        })

      assert %{
               "session_id" => session_id,
               "status" => "completed",
               "completed_at" => first_completed_at,
               "completion_reason" => "user"
             } = json_response(conn1, 200)

      :timer.sleep(10)

      # Attempt repeated finish with timer
      conn2 =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/finish", %{
          "reason" => "timer"
        })

      assert %{
               "session_id" => ^session_id,
               "status" => "completed",
               "completed_at" => ^first_completed_at,
               "completion_reason" => "user"
             } = json_response(conn2, 200)

      {:ok, stored_session} = Conversation.fetch(session.session_id)
      assert stored_session.completion_reason == :user
      assert DateTime.to_iso8601(stored_session.completed_at) == first_completed_at
    end
  end

  describe "GET /api/stations/active/sessions/:id/result" do
    setup do
      pkg = StationLoader.active_package()

      session =
        Conversation.start(%{
          station_id: pkg["station_id"],
          station_version: pkg["version"],
          audio_consent: true
        })

      %{session: session}
    end

    test "returns 404 on unknown session id", %{conn: conn} do
      conn = get(conn, ~p"/api/stations/active/sessions/unknown-session/result")

      assert json_response(conn, 404) == %{
               "error" => "session_not_found",
               "message" => "Sessão não encontrada."
             }
    end

    test "returns 410 on expired session", %{conn: conn} do
      original_timeout = Application.get_env(:backend, :conversation_timeout_ms)
      Application.put_env(:backend, :conversation_timeout_ms, 0)

      expired_session =
        try do
          pkg = StationLoader.active_package()

          Conversation.start(%{
            station_id: pkg["station_id"],
            station_version: pkg["version"],
            audio_consent: false
          })
        after
          if is_nil(original_timeout) do
            Application.delete_env(:backend, :conversation_timeout_ms)
          else
            Application.put_env(:backend, :conversation_timeout_ms, original_timeout)
          end
        end

      conn = get(conn, ~p"/api/stations/active/sessions/#{expired_session.session_id}/result")

      assert json_response(conn, 410) == %{
               "error" => "session_expired",
               "message" => "A sessão expirou."
             }
    end

    test "returns 422 on active/unfinished session", %{conn: conn, session: session} do
      conn = get(conn, ~p"/api/stations/active/sessions/#{session.session_id}/result")

      assert json_response(conn, 422) == %{
               "error" => "session_not_finished",
               "message" => "A sessão ainda não foi finalizada."
             }
    end

    test "returns per-criterion feedback with string evidence for completed session", %{
      conn: conn,
      session: session
    } do
      # Add messages that will meet criteria
      {:ok, _} =
        Conversation.append_message(session.session_id, %{
          role: :learner,
          modality: :text,
          text: "Quando começou essa dor no peito? Já fez eletrocardiograma ECG?"
        })

      {:ok, _} =
        Conversation.append_message(session.session_id, %{
          role: :patient,
          modality: :text,
          text: "Começou há duas horas."
        })

      {:ok, _} = Conversation.complete(session.session_id, :user)

      conn = get(conn, ~p"/api/stations/active/sessions/#{session.session_id}/result")

      response = json_response(conn, 200)

      assert %{
               "session_id" => session_id,
               "status" => "completed",
               "criteria" => criteria
             } = response

      assert session_id == session.session_id
      assert is_list(criteria)
      assert length(criteria) > 0

      # Each criterion contract check
      for criterion <- criteria do
        assert %{
                 "id" => id,
                 "status" => status,
                 "evidence" => evidence,
                 "recommendation" => recommendation
               } = criterion

        assert is_binary(id) and byte_size(id) > 0
        assert status in ["met", "omitted", "uncertain"]
        assert is_list(evidence)
        assert is_binary(recommendation)

        # Every evidence item MUST be a string (extracted from excerpt maps)
        for ev <- evidence do
          assert is_binary(ev)
        end
      end

      # Verify at least one criterion has string evidence (since we asked about onset / ECG)
      all_evidence = Enum.flat_map(criteria, & &1["evidence"])
      assert length(all_evidence) > 0

      # Explicitly verify NO global score, grade, verdict, pass/fail, or readiness fields anywhere
      refute Map.has_key?(response, "score")
      refute Map.has_key?(response, "global_score")
      refute Map.has_key?(response, "total")
      refute Map.has_key?(response, "grade")
      refute Map.has_key?(response, "verdict")
      refute Map.has_key?(response, "pass")
      refute Map.has_key?(response, "passed")
      refute Map.has_key?(response, "fail")
      refute Map.has_key?(response, "readiness")
      refute Map.has_key?(response, "revalida_readiness")

      for criterion <- criteria do
        refute Map.has_key?(criterion, "score")
        refute Map.has_key?(criterion, "points")
        refute Map.has_key?(criterion, "weight")
      end
    end
  end

  describe "POST /api/stations/active/sessions/:id/impressos/request" do
    setup do
      pkg = StationLoader.active_package()

      session =
        Conversation.start(%{
          station_id: pkg["station_id"],
          station_version: pkg["version"],
          audio_consent: false
        })

      %{session: session}
    end

    test "matches and releases an impresso", %{conn: conn, session: session} do
      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/impressos/request", %{
          "text" => "quero ver os sinais vitais"
        })

      response = json_response(conn, 200)

      assert %{
               "request_id" => request_id,
               "decision" => "released",
               "released_impressos" => released,
               "newly_released" => newly_released,
               "feedback_message" => feedback_message
             } = response

      assert is_binary(request_id)
      assert [%{"id" => "exame-fisico-geral"}] = newly_released
      assert released == newly_released
      assert feedback_message =~ "Impresso liberado:"

      for impresso <- released do
        assert %{"id" => _, "title" => _, "category" => _, "content" => _} = impresso
        refute Map.has_key?(impresso, "keywords")
      end
    end

    test "rejects request text over 2,000 characters with 422 message_too_long", %{
      conn: conn,
      session: session
    } do
      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/impressos/request", %{
          "text" => String.pad_trailing("sinais vitais ", 2_001, "a")
        })

      assert json_response(conn, 422) == %{
               "error" => "message_too_long",
               "message" => "Mensagem muito longa: o limite é de 2.000 caracteres."
             }

      assert {:ok, unchanged} = Conversation.fetch(session.session_id)
      assert unchanged.impresso_requests == []
    end

    test "an unavailable exam returns the exact required message", %{
      conn: conn,
      session: session
    } do
      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/impressos/request", %{
          "text" => "tomografia de crânio"
        })

      assert %{
               "decision" => "unavailable",
               "newly_released" => [],
               "released_impressos" => [],
               "feedback_message" => "Exame não disponível nesta estação"
             } = json_response(conn, 200)
    end

    test "repeating a request_id is idempotent", %{conn: conn, session: session} do
      conn1 =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/impressos/request", %{
          "text" => "sinais vitais",
          "request_id" => "client-1"
        })

      first = json_response(conn1, 200)

      conn2 =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/impressos/request", %{
          "text" => "exames laboratoriais",
          "request_id" => "client-1"
        })

      second = json_response(conn2, 200)

      assert second["request_id"] == "client-1"
      assert second["decision"] == first["decision"]
      assert second["newly_released"] == first["newly_released"]

      {:ok, updated} = Conversation.fetch(session.session_id)
      assert length(updated.impresso_requests) == 1
    end

    test "rejects missing or blank text", %{conn: conn, session: session} do
      for bad_text <- [nil, "", "   "] do
        params = if is_nil(bad_text), do: %{}, else: %{"text" => bad_text}

        conn_attempt =
          post(
            conn,
            ~p"/api/stations/active/sessions/#{session.session_id}/impressos/request",
            params
          )

        assert json_response(conn_attempt, 422) == %{
                 "error" => "invalid_request",
                 "message" => "Requisição inválida: 'text' é obrigatório e não pode ser vazio."
               }
      end
    end

    test "returns 404 on unknown session id", %{conn: conn} do
      conn =
        post(conn, ~p"/api/stations/active/sessions/nonexistent/impressos/request", %{
          "text" => "ecg"
        })

      assert json_response(conn, 404) == %{
               "error" => "session_not_found",
               "message" => "Sessão não encontrada."
             }
    end

    test "returns 410 on expired session", %{conn: conn} do
      original_timeout = Application.get_env(:backend, :conversation_timeout_ms)
      Application.put_env(:backend, :conversation_timeout_ms, 0)

      expired_session =
        try do
          pkg = StationLoader.active_package()

          Conversation.start(%{
            station_id: pkg["station_id"],
            station_version: pkg["version"],
            audio_consent: false
          })
        after
          if is_nil(original_timeout) do
            Application.delete_env(:backend, :conversation_timeout_ms)
          else
            Application.put_env(:backend, :conversation_timeout_ms, original_timeout)
          end
        end

      conn =
        post(
          conn,
          ~p"/api/stations/active/sessions/#{expired_session.session_id}/impressos/request",
          %{"text" => "ecg"}
        )

      assert json_response(conn, 410) == %{
               "error" => "session_expired",
               "message" => "A sessão expirou."
             }
    end

    test "returns 409 on completed session", %{conn: conn, session: session} do
      {:ok, _} = Conversation.complete(session.session_id, :user)

      conn =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/impressos/request", %{
          "text" => "ecg"
        })

      assert json_response(conn, 409) == %{
               "error" => "session_completed",
               "message" => "A sessão já foi concluída."
             }
    end
  end

  describe "GET /api/stations/active/sessions/:id/impressos" do
    setup do
      pkg = StationLoader.active_package()

      session =
        Conversation.start(%{
          station_id: pkg["station_id"],
          station_version: pkg["version"],
          audio_consent: false
        })

      %{session: session}
    end

    test "returns released impressos in release order", %{conn: conn, session: session} do
      {:ok, _} =
        Stations.request_impresso(session.session_id, %{"text" => "sinais vitais"})

      {:ok, _} =
        Stations.request_impresso(session.session_id, %{"text" => "ecg"})

      conn = get(conn, ~p"/api/stations/active/sessions/#{session.session_id}/impressos")

      assert %{"released_impressos" => released} = json_response(conn, 200)
      assert Enum.map(released, & &1["id"]) == ["exame-fisico-geral", "laudo-eletrocardiograma"]
    end

    test "is allowed on a completed session", %{conn: conn, session: session} do
      {:ok, _} = Stations.request_impresso(session.session_id, %{"text" => "ecg"})
      {:ok, _} = Conversation.complete(session.session_id, :user)

      conn = get(conn, ~p"/api/stations/active/sessions/#{session.session_id}/impressos")

      assert %{"released_impressos" => [%{"id" => "laudo-eletrocardiograma"}]} =
               json_response(conn, 200)
    end

    test "returns 404 on unknown session id", %{conn: conn} do
      conn = get(conn, ~p"/api/stations/active/sessions/nonexistent/impressos")

      assert json_response(conn, 404) == %{
               "error" => "session_not_found",
               "message" => "Sessão não encontrada."
             }
    end

    test "returns 410 on expired session", %{conn: conn} do
      original_timeout = Application.get_env(:backend, :conversation_timeout_ms)
      Application.put_env(:backend, :conversation_timeout_ms, 0)

      expired_session =
        try do
          pkg = StationLoader.active_package()

          Conversation.start(%{
            station_id: pkg["station_id"],
            station_version: pkg["version"],
            audio_consent: false
          })
        after
          if is_nil(original_timeout) do
            Application.delete_env(:backend, :conversation_timeout_ms)
          else
            Application.put_env(:backend, :conversation_timeout_ms, original_timeout)
          end
        end

      conn = get(conn, ~p"/api/stations/active/sessions/#{expired_session.session_id}/impressos")

      assert json_response(conn, 410) == %{
               "error" => "session_expired",
               "message" => "A sessão expirou."
             }
    end
  end

  describe "POST /api/stations/active/sessions/:id/discard" do
    setup do
      pkg = StationLoader.active_package()

      session =
        Conversation.start(%{
          station_id: pkg["station_id"],
          station_version: pkg["version"],
          audio_consent: true
        })

      %{session: session}
    end

    test "discards an active session returning 204 and denies subsequent operations", %{
      conn: conn,
      session: session
    } do
      conn_discard = post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/discard")
      assert response(conn_discard, 204) == ""

      # Subsequent session retrieval is denied with 404
      conn_show = get(conn, ~p"/api/stations/active/sessions/#{session.session_id}")

      assert json_response(conn_show, 404) == %{
               "error" => "session_not_found",
               "message" => "Sessão não encontrada."
             }

      # Subsequent message posting is denied with 404
      conn_msg =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
          "role" => "learner",
          "modality" => "text",
          "text" => "Mensagem após descarte"
        })

      assert json_response(conn_msg, 404) == %{
               "error" => "session_not_found",
               "message" => "Sessão não encontrada."
             }

      # Subsequent finish is denied with 404
      conn_finish =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/finish", %{
          "reason" => "user"
        })

      assert json_response(conn_finish, 404) == %{
               "error" => "session_not_found",
               "message" => "Sessão não encontrada."
             }

      # Subsequent result retrieval is denied with 404
      conn_result = get(conn, ~p"/api/stations/active/sessions/#{session.session_id}/result")

      assert json_response(conn_result, 404) == %{
               "error" => "session_not_found",
               "message" => "Sessão não encontrada."
             }

      # Subsequent impresso request is denied with 404
      conn_impresso =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/impressos/request", %{
          "text" => "ecg"
        })

      assert json_response(conn_impresso, 404) == %{
               "error" => "session_not_found",
               "message" => "Sessão não encontrada."
             }
    end

    test "discards a completed session returning 204 and denies subsequent result retrieval", %{
      conn: conn,
      session: session
    } do
      # Finish the session first
      conn_finish =
        post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/finish", %{
          "reason" => "user"
        })

      assert json_response(conn_finish, 200)["status"] == "completed"

      # Result is accessible prior to discard
      conn_result_before =
        get(conn, ~p"/api/stations/active/sessions/#{session.session_id}/result")

      assert json_response(conn_result_before, 200)["session_id"] == session.session_id

      # Discard the completed session
      conn_discard = post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/discard")
      assert response(conn_discard, 204) == ""

      # Result retrieval is now denied with 404
      conn_result_after =
        get(conn, ~p"/api/stations/active/sessions/#{session.session_id}/result")

      assert json_response(conn_result_after, 404) == %{
               "error" => "session_not_found",
               "message" => "Sessão não encontrada."
             }

      # Session retrieval is also denied with 404
      conn_show = get(conn, ~p"/api/stations/active/sessions/#{session.session_id}")

      assert json_response(conn_show, 404) == %{
               "error" => "session_not_found",
               "message" => "Sessão não encontrada."
             }
    end

    test "returns identical 204 for unknown session id", %{conn: conn} do
      conn_discard = post(conn, ~p"/api/stations/active/sessions/non-existent-session-id/discard")
      assert response(conn_discard, 204) == ""
    end

    test "repeated discard returns identical 204 without error", %{
      conn: conn,
      session: session
    } do
      conn1 = post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/discard")
      assert response(conn1, 204) == ""

      conn2 = post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/discard")
      assert response(conn2, 204) == ""

      conn3 = post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/discard")
      assert response(conn3, 204) == ""
    end

    test "discards an expired session returning identical 204", %{conn: conn} do
      original_timeout = Application.get_env(:backend, :conversation_timeout_ms)
      Application.put_env(:backend, :conversation_timeout_ms, 0)

      expired_session =
        try do
          pkg = StationLoader.active_package()

          Conversation.start(%{
            station_id: pkg["station_id"],
            station_version: pkg["version"],
            audio_consent: false
          })
        after
          if is_nil(original_timeout) do
            Application.delete_env(:backend, :conversation_timeout_ms)
          else
            Application.put_env(:backend, :conversation_timeout_ms, original_timeout)
          end
        end

      conn_discard =
        post(conn, ~p"/api/stations/active/sessions/#{expired_session.session_id}/discard")

      assert response(conn_discard, 204) == ""

      conn_show = get(conn, ~p"/api/stations/active/sessions/#{expired_session.session_id}")

      assert json_response(conn_show, 404) == %{
               "error" => "session_not_found",
               "message" => "Sessão não encontrada."
             }
    end

    test "releases pending finish waiters when session is discarded via HTTP", %{
      conn: conn,
      session: session
    } do
      assert {:ok, _session, _token} =
               Conversation.begin_turn(session.session_id, %{
                 role: :learner,
                 modality: :text,
                 text: "Em andamento"
               })

      finish_task =
        Task.async(fn ->
          post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/finish", %{
            "reason" => "user"
          })
        end)

      Process.sleep(20)

      discard_conn = post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/discard")
      assert response(discard_conn, 204) == ""

      finish_conn = Task.await(finish_task, 1_000)

      assert json_response(finish_conn, 404) == %{
               "error" => "session_not_found",
               "message" => "Sessão não encontrada."
             }
    end
  end

  describe "GET /stations and GET /api/stations catalog (issue #333)" do
    test "returns empty list when no approved cases exist", %{conn: conn} do
      for path <- ["/stations", "/api/stations"] do
        conn = get(conn, path)
        assert json_response(conn, 200) == []
      end
    end

    test "returns approved cases with id, area, theme, actors (without examiner secrets)", %{
      conn: conn
    } do
      admin = Backend.AccountsFixtures.admin_fixture()
      case_markdown = File.read!("priv/stations/acute-appendicitis/case.md")
      {:ok, package} = Backend.Stations.parse_case(case_markdown)

      # Insert case and approve it
      kase =
        Backend.Content.get_case_by_number(1) ||
          (
            %{rows: [[num]]} =
              Backend.Repo.query!(
                "INSERT INTO cases (area, theme, markdown) VALUES ($1, $2, $3) RETURNING number",
                ["Cirurgia Geral", "Apendicite aguda", case_markdown]
              )

            Backend.Content.get_case_by_number(num)
          )

      {:ok, _approved} = Backend.Content.approve_case(kase, package, admin)

      for path <- ["/stations", "/api/stations"] do
        conn = get(conn, path)
        [station] = json_response(conn, 200)

        assert station["id"] == kase.number
        assert station["version"] == 1
        assert station["slug"] == "acute-appendicitis"

        assert Map.keys(station) |> Enum.sort() == [
                 "actors",
                 "area",
                 "id",
                 "slug",
                 "theme",
                 "version"
               ]

        assert station["area"] == package["area"]
        assert station["theme"] == package["theme"]
        assert is_list(station["actors"])
        assert length(station["actors"]) == length(package["actors"])

        for actor <- station["actors"] do
          assert Map.keys(actor) |> Enum.sort() == ["age", "id", "name", "role", "voice"]
          refute Map.has_key?(actor, "fact_ids")
          refute Map.has_key?(actor, "explicit_fact_ids")
          refute Map.has_key?(actor, "mandatory_question_ids")
          refute Map.has_key?(actor, "persona")
          refute Map.has_key?(actor, "tone")
          refute Map.has_key?(actor, "presenting_context")
        end
      end
    end

    test "two approved cases sharing one [ESTAÇÃO] slug are two entries with distinct ids", %{
      conn: conn
    } do
      admin = Backend.AccountsFixtures.admin_fixture()
      case_markdown = File.read!("priv/stations/acute-appendicitis/case.md")
      {:ok, package} = Backend.Stations.parse_case(case_markdown)

      [num1, num2] =
        for theme <- ["Apendicite aguda", "Apendicite aguda (variante)"] do
          %{rows: [[num]]} =
            Backend.Repo.query!(
              "INSERT INTO cases (area, theme, markdown) VALUES ($1, $2, $3) RETURNING number",
              ["Cirurgia Geral", theme, case_markdown]
            )

          {:ok, _} =
            Backend.Content.approve_case(Backend.Content.get_case_by_number(num), package, admin)

          num
        end

      for path <- ["/stations", "/api/stations"] do
        stations = json_response(get(conn, path), 200)

        assert Enum.map(stations, & &1["id"]) == [num1, num2]
        assert Enum.map(stations, & &1["slug"]) == ["acute-appendicitis", "acute-appendicitis"]
        assert Enum.map(stations, & &1["version"]) == [1, 1]
      end
    end

    test "disapproving hides the case from the catalog", %{conn: conn} do
      admin = Backend.AccountsFixtures.admin_fixture()
      case_markdown = File.read!("priv/stations/acute-appendicitis/case.md")
      {:ok, package} = Backend.Stations.parse_case(case_markdown)

      %{rows: [[num]]} =
        Backend.Repo.query!(
          "INSERT INTO cases (area, theme, markdown) VALUES ($1, $2, $3) RETURNING number",
          ["Cirurgia Geral", "Apendicite aguda", case_markdown]
        )

      kase = Backend.Content.get_case_by_number(num)
      {:ok, approved} = Backend.Content.approve_case(kase, package, admin)

      assert length(json_response(get(conn, "/stations"), 200)) == 1

      {:ok, _disapproved} = Backend.Content.disapprove_case(approved)

      assert json_response(get(conn, "/stations"), 200) == []
      assert json_response(get(conn, "/api/stations"), 200) == []
    end
  end

  defp use_configurable_jev(patient_result) do
    Application.put_env(:backend, :controller_test_jev_patient_result, patient_result)
    Application.put_env(:backend, :jev_decision_adapter, ConfigurableJevAdapter)
  end

  defp post_learner_text(conn, session, text) do
    post(conn, ~p"/api/stations/active/sessions/#{session.session_id}/messages", %{
      "role" => "learner",
      "modality" => "text",
      "text" => text
    })
  end
end
