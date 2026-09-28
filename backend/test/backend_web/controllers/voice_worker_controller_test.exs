defmodule BackendWeb.VoiceWorkerControllerTest do
  use BackendWeb.ConnCase, async: false

  alias Backend.Stations

  @secret "test-worker-secret"

  setup %{conn: conn} do
    Application.put_env(:backend, :voice_worker_secret, @secret)
    on_exit(fn -> Application.delete_env(:backend, :voice_worker_secret) end)
    {:ok, conn: put_req_header(conn, "authorization", "Bearer " <> @secret)}
  end

  defp context_path(id), do: ~p"/api/internal/voice/sessions/#{id}"
  defp transcripts_path(id), do: ~p"/api/internal/voice/sessions/#{id}/transcripts"

  describe "authentication" do
    test "rejects a missing or wrong bearer token", %{conn: conn} do
      session = Stations.create_session(%{audio_consent: true})

      conn =
        conn
        |> put_req_header("authorization", "Bearer nope")
        |> get(context_path(session.session_id))

      assert %{"error" => "unauthorized"} = json_response(conn, 401)

      conn = build_conn() |> get(context_path(session.session_id))
      assert json_response(conn, 401)
    end

    test "rejects every request when no secret is configured", %{conn: conn} do
      Application.delete_env(:backend, :voice_worker_secret)
      session = Stations.create_session(%{audio_consent: true})

      conn =
        conn
        |> put_req_header("authorization", "Bearer ")
        |> get(context_path(session.session_id))

      assert json_response(conn, 401)
    end
  end

  describe "GET context" do
    test "returns pt-BR, station keyterms and last_turn_id for a consented active session",
         %{conn: conn} do
      session = Stations.create_session(%{audio_consent: true})

      body = conn |> get(context_path(session.session_id)) |> json_response(200)

      assert body["session_id"] == session.session_id
      assert body["language"] == "pt-BR"
      assert body["last_turn_id"] == 0
      assert is_list(body["keyterms"]) and body["keyterms"] != []
    end

    test "refuses sessions without audio consent", %{conn: conn} do
      session = Stations.create_session(%{audio_consent: false})

      assert %{"error" => "no_consent"} =
               conn |> get(context_path(session.session_id)) |> json_response(403)
    end

    test "refuses unknown and completed sessions", %{conn: conn} do
      assert json_response(get(conn, context_path("missing")), 404)

      session = Stations.create_session(%{audio_consent: true})
      {:ok, _} = Stations.complete_session(session.session_id)
      assert json_response(get(conn, context_path(session.session_id)), 422)
    end
  end

  describe "POST transcripts" do
    test "commits a final transcript once and reports duplicates", %{conn: conn} do
      session = Stations.create_session(%{audio_consent: true})
      id = session.session_id

      assert %{"status" => "committed", "turn_id" => 1} =
               conn
               |> post(transcripts_path(id), %{turn_id: 1, text: "Onde dói?"})
               |> json_response(201)

      assert %{"status" => "duplicate", "turn_id" => 1} =
               conn
               |> post(transcripts_path(id), %{turn_id: 1, text: "Onde dói?"})
               |> json_response(200)

      {:ok, stored} = Stations.get_session(id)
      assert [%{role: :learner, modality: :voice, text: "Onde dói?"}] = stored.messages

      assert %{"last_turn_id" => 1} = conn |> get(context_path(id)) |> json_response(200)
    end

    test "treats an older turn_id as a duplicate so reordering never appends twice",
         %{conn: conn} do
      session = Stations.create_session(%{audio_consent: true})
      id = session.session_id

      assert json_response(post(conn, transcripts_path(id), %{turn_id: 2, text: "segunda"}), 201)

      assert %{"status" => "duplicate"} =
               json_response(
                 post(conn, transcripts_path(id), %{turn_id: 1, text: "primeira"}),
                 200
               )

      {:ok, stored} = Stations.get_session(id)
      assert [%{text: "segunda"}] = stored.messages
    end

    test "rejects malformed payloads", %{conn: conn} do
      session = Stations.create_session(%{audio_consent: true})
      id = session.session_id

      for body <- [
            %{turn_id: 0, text: "x"},
            %{turn_id: "1", text: "x"},
            %{turn_id: 1, text: "  "},
            %{turn_id: 1}
          ] do
        assert %{"error" => "invalid_transcript"} =
                 json_response(post(conn, transcripts_path(id), body), 400)
      end
    end

    test "refuses transcripts for sessions without consent or no longer active", %{conn: conn} do
      no_consent = Stations.create_session(%{audio_consent: false})

      assert json_response(
               post(conn, transcripts_path(no_consent.session_id), %{turn_id: 1, text: "x"}),
               403
             )

      done = Stations.create_session(%{audio_consent: true})
      {:ok, _} = Stations.complete_session(done.session_id)

      assert json_response(
               post(conn, transcripts_path(done.session_id), %{turn_id: 1, text: "x"}),
               422
             )
    end
  end
end
