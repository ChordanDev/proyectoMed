defmodule BackendWeb.StationControllerTest do
  use BackendWeb.ConnCase, async: true

  alias Backend.Conversation
  alias Backend.StationLoader

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
end
