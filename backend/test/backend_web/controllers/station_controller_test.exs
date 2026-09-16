defmodule BackendWeb.StationControllerTest do
  use BackendWeb.ConnCase, async: false

  alias Backend.Conversation
  alias Backend.StationLoader

  defmodule TestSuccessAdapter do
    @behaviour Backend.StationAI
    @impl true
    def next_reply(_package, _context) do
      {:ok, %{text: "Estou com um aperto forte no peito há duas horas."}}
    end
  end

  defmodule TestErrorAdapter do
    @behaviour Backend.StationAI
    @impl true
    def next_reply(_package, _context) do
      {:error, :provider_down}
    end
  end

  describe "GET /api/stations/active" do
    test "returns active station metadata", %{conn: conn} do
      conn = get(conn, ~p"/api/stations/active")

      assert json_response(conn, 200) == %{
               "station_id" => "chest-pain-initial-assessment",
               "version" => "1.0.0",
               "language" => "pt-BR",
               "display_title" => "Avaliação inicial de dor torácica"
             }
    end

    test "returns the boot-loaded active version", %{conn: conn} do
      conn = get(conn, ~p"/api/stations/active")

      assert %{"version" => version} = json_response(conn, 200)
      assert version == StationLoader.active_version()
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

      active_pkg = StationLoader.active_package()
      assert station_id == active_pkg["station_id"]
      assert station_version == active_pkg["version"]

      assert {:ok, started_at, _} = DateTime.from_iso8601(started_at_str)
      assert {:ok, expires_at, _} = DateTime.from_iso8601(expires_at_str)
      assert {:ok, server_now, _} = DateTime.from_iso8601(server_now_str)

      assert DateTime.diff(expires_at, started_at, :second) == 30 * 60
      assert abs(DateTime.diff(server_now, started_at, :second)) <= 2

      # Verifies persistence in Backend.Conversation
      assert {:ok, session} = Conversation.fetch(session_id)
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
  end
end
