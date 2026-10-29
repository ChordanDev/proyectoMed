defmodule BackendWeb.SessionControllerTest do
  @moduledoc """
  The multi-station session API (issue #334, ADR-013 amendment on #209):
  `POST /sessions` starts a session on a published Station version and every
  station route is addressed by session id under `/sessions/:id`.
  """

  # Session state lives in the shared Conversation table and the tests swap
  # application adapters: not async.
  use BackendWeb.ConnCase, async: false

  alias Backend.Content
  alias Backend.Stations

  @reference_case File.read!("priv/stations/acute-appendicitis/case.md")
  @imaging_request "Solicito uma ultrassonografia de abdome"
  @imaging_impresso "impresso-3-exame-de-imagem"

  defmodule PatientAdapter do
    @behaviour Backend.Stations.StationAI
    @impl true
    def next_reply(_package, _context) do
      {:ok, %{text: "[PACIENTE] A dor começou ontem à noite, em volta do umbigo."}}
    end
  end

  # The station API requires a learner's device access token (#337), and
  # starting a session an active entitlement (#339).
  setup :register_and_log_in_device
  setup %{device_user: user}, do: %{device_user: Backend.BillingFixtures.subscribe_user(user)}

  setup do
    previous =
      for key <- [:jev_decision_adapter, :station_ai_adapter],
          do: {key, Application.fetch_env(:backend, key)}

    Application.put_env(:backend, :jev_decision_adapter, Backend.E2ESupport.ApprovingJevAdapter)
    Application.put_env(:backend, :station_ai_adapter, PatientAdapter)

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, value} -> Application.put_env(:backend, key, value)
          :error -> Application.delete_env(:backend, key)
        end
      end
    end)

    admin = Backend.AccountsFixtures.admin_fixture()
    {:ok, package} = Stations.parse_case(@reference_case)
    %{admin: admin, package: package}
  end

  defp publish!(package, admin, area \\ "Cirurgia Geral") do
    %{rows: [[id]]} =
      Backend.Repo.query!(
        "INSERT INTO cases (area, theme, markdown) VALUES ($1, $2, $3) RETURNING id",
        [area, "Tema", @reference_case]
      )

    {:ok, approved} =
      Content.approve_case(Content.get_case!(id), Map.put(package, "area", area), admin)

    approved
  end

  describe "GET /pre-station-notice" do
    test "serves the notice with every active provider", %{conn: conn} do
      body = conn |> get(~p"/pre-station-notice") |> json_response(200)

      assert body == Jason.decode!(Jason.encode!(Stations.pre_station_notice()))
      assert body["body"] =~ "Não insira dados de pacientes reais"
      assert is_list(body["providers"])
    end
  end

  describe "POST /sessions past the daily quota (#340)" do
    test "answers 429 daily_quota_exhausted with the reset time", %{
      conn: conn,
      admin: admin,
      package: package
    } do
      kase = publish!(package, admin)

      {:ok, _quota} =
        Backend.Billing.set_daily_quota(Backend.BillingFixtures.card_product_id(), 1)

      params = %{"station_id" => kase.number, "audio_consent" => true}

      %{"session_id" => session_id} = conn |> post(~p"/sessions", params) |> json_response(201)
      on_exit(fn -> Stations.discard_session(session_id) end)

      resets_at = Backend.Billing.quota_day().resets_at
      refused = post(conn, ~p"/sessions", params)

      assert json_response(refused, 429) == %{
               "error" => "daily_quota_exhausted",
               "message" =>
                 "Você usou todas as simulações de hoje. A cota renova à meia-noite (horário de Brasília).",
               "daily_quota" => 1,
               "resets_at" => DateTime.to_iso8601(resets_at)
             }

      [retry_after] = get_resp_header(refused, "retry-after")
      assert String.to_integer(retry_after) in 1..86_400
    end

    test "a subscription is still checked first: 402 before 429", %{
      admin: admin,
      package: package
    } do
      kase = publish!(package, admin)

      {:ok, _quota} =
        Backend.Billing.set_daily_quota(Backend.BillingFixtures.card_product_id(), 0)

      assert %{"error" => "subscription_required"} =
               build_conn()
               |> log_in_device(Backend.AccountsFixtures.user_fixture())
               |> post(~p"/sessions", %{"station_id" => kase.number, "audio_consent" => true})
               |> json_response(402)
    end
  end

  describe "POST /sessions without an active subscription" do
    test "answers 402 subscription_required", %{
      admin: admin,
      package: package
    } do
      kase = publish!(package, admin)
      unsubscribed = Backend.AccountsFixtures.user_fixture()

      body =
        build_conn()
        |> log_in_device(unsubscribed)
        |> post(~p"/sessions", %{"station_id" => kase.number, "audio_consent" => true})
        |> json_response(402)

      assert body == %{
               "error" => "subscription_required",
               "message" => "Assine um plano para usar o simulador."
             }
    end

    test "answers 402 once the entitlement has expired", %{admin: admin, package: package} do
      kase = publish!(package, admin)
      lapsed = Backend.AccountsFixtures.user_fixture()

      Backend.BillingFixtures.subscribe_user(lapsed,
        product_id: Backend.BillingFixtures.pix_product_id(),
        expiration_at_ms: Backend.BillingFixtures.now_ms() - 1_000
      )

      assert %{"error" => "subscription_required"} =
               build_conn()
               |> log_in_device(lapsed)
               |> post(~p"/sessions", %{"random" => true, "audio_consent" => false})
               |> json_response(402)
    end

    test "invalid parameters are still reported first as 400", %{conn: _conn} do
      unsubscribed = Backend.AccountsFixtures.user_fixture()

      assert %{"error" => "invalid_parameters"} =
               build_conn()
               |> log_in_device(unsubscribed)
               |> post(~p"/sessions", %{"audio_consent" => true})
               |> json_response(400)
    end
  end

  describe "POST /sessions" do
    test "starts a session on a station id with its public station and brief",
         %{conn: conn, admin: admin, package: package} do
      kase = publish!(package, admin)

      body =
        conn
        |> post(~p"/sessions", %{"station_id" => kase.number, "audio_consent" => true})
        |> json_response(201)

      assert %{
               "session_id" => session_id,
               "station_id" => station_id,
               "station_version" => 1,
               "audio_consent" => true,
               "status" => "active",
               "voice_mode" => "turn",
               "station" => station
             } = body

      assert station_id == kase.number

      assert station["id"] == kase.number
      assert station["version"] == 1
      assert station["slug"] == "acute-appendicitis"
      assert station["area"] == "Cirurgia Geral"
      assert station["display_title"] == package["display_title"]

      assert station["candidate_brief"] ==
               Map.take(package["candidate_brief"], ["scenario", "tasks"])

      assert [%{"id" => "paciente", "role" => "patient"} = actor] = station["actors"]
      assert Map.keys(actor) |> Enum.sort() == ["age", "id", "name", "role", "voice"]

      for field <- ["started_at", "expires_at", "deadline_at", "server_now"] do
        assert {:ok, _, _} = DateTime.from_iso8601(body[field])
      end

      raw = Jason.encode!(body)

      for secret <-
            Enum.map(package["rubric"], & &1["id"]) ++
              Enum.map(package["impressos"], & &1["id"]) ++ ["revealable_facts", "rubric"] do
        refute String.contains?(raw, secret), "session start exposes: #{secret}"
      end

      assert {:ok, %{station_id: ^station_id}} = Stations.get_session(session_id)
    end

    test "accepts the station id as a numeric string", %{
      conn: conn,
      admin: admin,
      package: package
    } do
      kase = publish!(package, admin)

      body =
        conn
        |> post(~p"/sessions", %{"station_id" => "#{kase.number}", "audio_consent" => false})
        |> json_response(201)

      assert body["station_id"] == kase.number
      assert body["audio_consent"] == false
    end

    test "draws a random station within an area, or from any area",
         %{conn: conn, admin: admin, package: package} do
      _surgery = publish!(package, admin, "Cirurgia Geral")
      pediatrics = publish!(package, admin, "Pediatria")

      body =
        conn
        |> post(~p"/sessions", %{
          "random" => true,
          "area" => "Pediatria",
          "audio_consent" => false
        })
        |> json_response(201)

      assert body["station_id"] == pediatrics.number
      assert body["station"]["area"] == "Pediatria"

      body =
        conn
        |> recycle()
        |> post(~p"/sessions", %{"random" => true, "audio_consent" => false})
        |> json_response(201)

      assert body["station"]["area"] in ["Cirurgia Geral", "Pediatria"]
    end

    test "an unknown station id is station_not_found", %{conn: conn} do
      body =
        conn
        |> post(~p"/sessions", %{"station_id" => 999_999, "audio_consent" => true})
        |> json_response(404)

      assert body == %{"error" => "station_not_found", "message" => "Estação não encontrada."}
    end

    test "a station id beyond the bigint range is station_not_found, not a server error",
         %{conn: conn} do
      for station_id <- [99_999_999_999_999_999_999, "99999999999999999999"] do
        body =
          conn
          |> post(~p"/sessions", %{"station_id" => station_id, "audio_consent" => true})
          |> json_response(404)

        assert body == %{"error" => "station_not_found", "message" => "Estação não encontrada."}
      end
    end

    test "an area without a published station is no_published_station",
         %{conn: conn, admin: admin, package: package} do
      _surgery = publish!(package, admin, "Cirurgia Geral")

      body =
        conn
        |> post(~p"/sessions", %{"random" => true, "area" => "Pediatria", "audio_consent" => true})
        |> json_response(404)

      assert body == %{
               "error" => "no_published_station",
               "message" => "Nenhuma estação publicada para esta área."
             }
    end

    test "rejects a request without a station choice or a boolean audio consent", %{conn: conn} do
      for params <- [
            %{"audio_consent" => true},
            %{"station_id" => "abc", "audio_consent" => true},
            %{"station_id" => 1.5, "audio_consent" => true},
            %{"random" => "yes", "audio_consent" => true},
            %{"random" => true, "area" => 7, "audio_consent" => true},
            %{"station_id" => 1, "random" => true, "audio_consent" => true},
            %{"station_id" => 1},
            %{"random" => true, "audio_consent" => "true"}
          ] do
        body = conn |> recycle() |> post(~p"/sessions", params) |> json_response(400)
        assert body["error"] == "invalid_parameters", "accepted #{inspect(params)}"
      end
    end
  end

  describe "the reference acute-appendicitis case end to end" do
    test "plays text turns, an impresso, finish and the educational result per session",
         %{conn: conn, admin: admin, package: package} do
      kase = publish!(package, admin)

      %{"session_id" => id} =
        conn
        |> post(~p"/sessions", %{"station_id" => kase.number, "audio_consent" => false})
        |> json_response(201)

      # A patient-addressed text turn.
      assert %{"outcome" => "patient_reply", "reply_text" => reply} =
               conn
               |> recycle()
               |> post(~p"/sessions/#{id}/messages", %{
                 "role" => "learner",
                 "modality" => "text",
                 "text" => "Quando começou a dor?"
               })
               |> json_response(200)

      assert reply =~ "umbigo"

      # An exam request in a turn is examiner-addressed, flagged and releases
      # nothing (#351): only the impresso route releases.
      assert %{
               "outcome" => "examiner_acknowledged",
               "reply_text" => nil,
               "newly_released" => [],
               "exam_request" => true
             } =
               conn
               |> recycle()
               |> post(~p"/sessions/#{id}/messages", %{
                 "role" => "learner",
                 "modality" => "text",
                 "text" => @imaging_request
               })
               |> json_response(200)

      assert %{"released_impressos" => []} =
               conn |> recycle() |> get(~p"/sessions/#{id}/impressos") |> json_response(200)

      # The impresso route releases the exam the dialogue named, then the labs.
      assert %{"decision" => "released", "newly_released" => [%{"id" => @imaging_impresso}]} =
               conn
               |> recycle()
               |> post(~p"/sessions/#{id}/impressos/request", %{"text" => @imaging_request})
               |> json_response(200)

      assert %{"decision" => "released", "newly_released" => [_ | _]} =
               conn
               |> recycle()
               |> post(~p"/sessions/#{id}/impressos/request", %{"text" => "Solicito hemograma"})
               |> json_response(200)

      assert %{"released_impressos" => [%{"id" => @imaging_impresso} | _]} =
               conn |> recycle() |> get(~p"/sessions/#{id}/impressos") |> json_response(200)

      assert %{"status" => "active", "messages" => [_, _, _]} =
               conn |> recycle() |> get(~p"/sessions/#{id}") |> json_response(200)

      assert %{"status" => "completed", "completion_reason" => "user"} =
               conn
               |> recycle()
               |> post(~p"/sessions/#{id}/finish", %{"reason" => "user"})
               |> json_response(200)

      result = conn |> recycle() |> get(~p"/sessions/#{id}/result") |> json_response(200)

      assert result["schema_version"] == "2"
      assert result["session_id"] == id
      assert Enum.map(result["criteria"], & &1["id"]) == Enum.map(package["rubric"], & &1["id"])
      assert result["coverage"]["assessed"] > 0
      assert is_binary(result["estimates"]["eligible_max"])

      assert conn |> recycle() |> post(~p"/sessions/#{id}/discard") |> response(204)

      assert %{"error" => "session_not_found"} =
               conn |> recycle() |> get(~p"/sessions/#{id}") |> json_response(404)
    end
  end

  describe "Station Mode: training or simulated exam (#421)" do
    test "a session started without a mode is a training, as before",
         %{conn: conn, admin: admin, package: package} do
      kase = publish!(package, admin)

      for consent <- [true, false] do
        body =
          conn
          |> recycle()
          |> post(~p"/sessions", %{"station_id" => kase.number, "audio_consent" => consent})
          |> json_response(201)

        assert body["mode"] == "training"
        assert body["audio_consent"] == consent

        shown =
          conn |> recycle() |> get(~p"/sessions/#{body["session_id"]}") |> json_response(200)

        assert shown["mode"] == "training"
        assert {:ok, %{mode: :training}} = Stations.get_session(body["session_id"])
      end
    end

    test "a null or explicit training mode is a training",
         %{conn: conn, admin: admin, package: package} do
      kase = publish!(package, admin)

      for mode <- [nil, "training"] do
        body =
          conn
          |> recycle()
          |> post(~p"/sessions", %{
            "station_id" => kase.number,
            "audio_consent" => false,
            "mode" => mode
          })
          |> json_response(201)

        assert body["mode"] == "training", "mode #{inspect(mode)}"
      end
    end

    test "a simulated exam is recorded, returned and kept for the whole run",
         %{conn: conn, admin: admin, package: package} do
      kase = publish!(package, admin)

      body =
        conn
        |> post(~p"/sessions", %{
          "station_id" => kase.number,
          "audio_consent" => true,
          "mode" => "simulated_exam"
        })
        |> json_response(201)

      assert %{"session_id" => id, "mode" => "simulated_exam", "audio_consent" => true} = body
      assert {:ok, %{mode: :simulated_exam}} = Stations.get_session(id)

      assert %{"mode" => "simulated_exam"} =
               conn |> recycle() |> get(~p"/sessions/#{id}") |> json_response(200)

      assert %{"reply_text" => _} =
               conn
               |> recycle()
               |> post(~p"/sessions/#{id}/messages", %{
                 "role" => "learner",
                 "modality" => "voice",
                 "text" => "Quando começou a dor?"
               })
               |> json_response(200)

      assert %{"mode" => "simulated_exam"} =
               conn |> recycle() |> get(~p"/sessions/#{id}") |> json_response(200)

      assert %{"status" => "completed", "mode" => "simulated_exam"} =
               conn |> recycle() |> post(~p"/sessions/#{id}/finish") |> json_response(200)

      assert %{"status" => "completed", "mode" => "simulated_exam"} =
               conn |> recycle() |> get(~p"/sessions/#{id}") |> json_response(200)
    end

    test "a simulated exam cannot start without audio consent",
         %{conn: conn, admin: admin, package: package} do
      kase = publish!(package, admin)
      sessions_before = :ets.info(Backend.Stations.Conversation, :size)

      body =
        conn
        |> post(~p"/sessions", %{
          "station_id" => kase.number,
          "audio_consent" => false,
          "mode" => "simulated_exam"
        })
        |> json_response(400)

      assert body == %{
               "error" => "audio_consent_required",
               "message" =>
                 "A prova simulada é feita só por voz: é preciso consentir com o uso do áudio."
             }

      assert :ets.info(Backend.Stations.Conversation, :size) == sessions_before
    end

    test "rejects an unknown mode", %{conn: conn, admin: admin, package: package} do
      kase = publish!(package, admin)

      for mode <- ["exam", "Simulated_Exam", "", 1, true, %{"a" => 1}] do
        body =
          conn
          |> recycle()
          |> post(~p"/sessions", %{
            "station_id" => kase.number,
            "audio_consent" => true,
            "mode" => mode
          })
          |> json_response(400)

        assert body["error"] == "invalid_parameters", "accepted mode #{inspect(mode)}"
      end
    end
  end

  describe "session routes" do
    test "a running session keeps its version after the case is re-published",
         %{conn: conn, admin: admin, package: package} do
      kase = publish!(package, admin)

      %{"session_id" => id} =
        conn
        |> post(~p"/sessions", %{"station_id" => kase.number, "audio_consent" => false})
        |> json_response(201)

      {:ok, edited} = Content.update_case_markdown(kase, @reference_case <> "\n", admin)
      {:ok, _} = Content.approve_case(edited, package, admin)

      body = conn |> recycle() |> get(~p"/sessions/#{id}") |> json_response(200)
      assert body["station_version"] == 1
      assert body["station"]["version"] == 1

      fresh =
        conn
        |> recycle()
        |> post(~p"/sessions", %{"station_id" => kase.number, "audio_consent" => false})
        |> json_response(201)

      assert fresh["station_version"] == 2
    end

    test "voice routes are addressed by session", %{conn: conn, admin: admin, package: package} do
      kase = publish!(package, admin)

      %{"session_id" => id} =
        conn
        |> post(~p"/sessions", %{"station_id" => kase.number, "audio_consent" => true})
        |> json_response(201)

      assert %{"error" => "voice_unavailable"} =
               conn |> recycle() |> post(~p"/sessions/#{id}/voice") |> json_response(503)
    end

    test "an unknown session is session_not_found on every session route", %{conn: conn} do
      for {method, path} <- [
            {:get, "/sessions/nope"},
            {:get, "/sessions/nope/impressos"},
            {:get, "/sessions/nope/result"},
            {:post, "/sessions/nope/finish"},
            {:post, "/sessions/nope/impressos/request"}
          ] do
        params = if path =~ "request", do: %{"text" => "hemograma"}, else: %{}
        conn = conn |> recycle() |> dispatch(@endpoint, method, path, params)
        assert %{"error" => "session_not_found"} = json_response(conn, 404), path
      end
    end

    test "the deprecated active-station aliases serve a database session",
         %{conn: conn, admin: admin, package: package} do
      kase = publish!(package, admin)

      %{"session_id" => id} =
        conn
        |> post(~p"/sessions", %{"station_id" => kase.number, "audio_consent" => false})
        |> json_response(201)

      assert %{"newly_released" => [%{"id" => @imaging_impresso}]} =
               conn
               |> recycle()
               |> post(~p"/api/stations/active/sessions/#{id}/impressos/request", %{
                 "text" => @imaging_request
               })
               |> json_response(200)

      assert %{"session_id" => ^id} =
               conn
               |> recycle()
               |> get(~p"/api/stations/active/sessions/#{id}")
               |> json_response(200)
    end
  end

  describe "exam mode for a spoken request (#364)" do
    setup %{conn: conn, admin: admin, package: package} do
      kase = publish!(package, admin)

      start = fn consent ->
        conn
        |> recycle()
        |> post(~p"/sessions", %{"station_id" => kase.number, "audio_consent" => consent})
        |> json_response(201)
        |> Map.fetch!("session_id")
      end

      %{start: start}
    end

    test "POST arms the next utterance as an impresso request", %{conn: conn, start: start} do
      id = start.(true)

      body = conn |> recycle() |> post(~p"/sessions/#{id}/exam-mode") |> json_response(200)
      assert %{"status" => "armed", "expires_at" => expires_at, "server_now" => _} = body
      assert {:ok, _, _} = DateTime.from_iso8601(expires_at)

      assert {:ok, {:impresso, %{decision: "released", request_id: "voice-exam-1"}}} =
               Stations.process_voice_turn(id, 1, @imaging_request)

      assert {:ok, %{messages: [], released_impressos: [@imaging_impresso]}} =
               Stations.get_session(id)
    end

    test "DELETE disarms it", %{conn: conn, start: start} do
      id = start.(true)
      conn |> recycle() |> post(~p"/sessions/#{id}/exam-mode") |> json_response(200)

      assert %{"status" => "disarmed"} =
               conn |> recycle() |> delete(~p"/sessions/#{id}/exam-mode") |> json_response(200)

      assert {:ok, {:kept, %{addressee: :examiner}}} =
               Stations.process_voice_turn(id, 1, @imaging_request)

      assert {:ok, %{impresso_requests: []}} = Stations.get_session(id)
    end

    test "needs audio consent and an active session", %{conn: conn, start: start} do
      no_consent = start.(false)

      assert %{"error" => "no_consent"} =
               conn
               |> recycle()
               |> post(~p"/sessions/#{no_consent}/exam-mode")
               |> json_response(403)

      finished = start.(true)
      conn |> recycle() |> post(~p"/sessions/#{finished}/finish") |> json_response(200)

      assert %{"error" => "session_completed"} =
               conn
               |> recycle()
               |> post(~p"/sessions/#{finished}/exam-mode")
               |> json_response(409)
    end

    test "an unknown session is session_not_found", %{conn: conn} do
      for method <- [:post, :delete] do
        conn = conn |> recycle() |> dispatch(@endpoint, method, "/sessions/nope/exam-mode", %{})
        assert %{"error" => "session_not_found"} = json_response(conn, 404)
      end
    end

    test "needs the device access token" do
      for method <- [:post, :delete] do
        conn = dispatch(build_conn(), @endpoint, method, "/sessions/nope/exam-mode", %{})
        assert json_response(conn, 401)
      end
    end
  end

  describe "without the file station loader (production)" do
    setup do
      :ok = Supervisor.terminate_child(Backend.Supervisor, Backend.Stations.StationLoader)

      on_exit(fn ->
        {:ok, _pid} = Supervisor.restart_child(Backend.Supervisor, Backend.Stations.StationLoader)
      end)

      :ok
    end

    test "the deprecated active-station routes answer no_active_station", %{conn: conn} do
      expected = %{
        "error" => "no_active_station",
        "message" => "Nenhuma estação ativa: inicie a sessão por POST /sessions."
      }

      assert conn |> get(~p"/api/stations/active") |> json_response(404) == expected

      assert conn
             |> recycle()
             |> post(~p"/api/stations/active/sessions", %{"audio_consent" => true})
             |> json_response(404) == expected
    end

    test "POST /sessions still plays a published station",
         %{conn: conn, admin: admin, package: package} do
      kase = publish!(package, admin)

      %{"session_id" => id} =
        conn
        |> post(~p"/sessions", %{"station_id" => kase.number, "audio_consent" => false})
        |> json_response(201)

      assert %{"outcome" => "patient_reply"} =
               conn
               |> recycle()
               |> post(~p"/sessions/#{id}/messages", %{
                 "role" => "learner",
                 "modality" => "text",
                 "text" => "Quando começou a dor?"
               })
               |> json_response(200)

      assert %{"released_impressos" => []} =
               conn |> recycle() |> get(~p"/sessions/#{id}/impressos") |> json_response(200)
    end
  end
end
