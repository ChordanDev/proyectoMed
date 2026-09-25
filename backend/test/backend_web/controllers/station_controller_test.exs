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
end
