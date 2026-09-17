defmodule BackendWeb.StationControllerTest do
  use BackendWeb.ConnCase, async: true

  alias Backend.StationLoader

  test "GET /api/stations/active returns active station metadata", %{conn: conn} do
    conn = get(conn, ~p"/api/stations/active")

    assert json_response(conn, 200) == %{
             "station_id" => "chest-pain-initial-assessment",
             "version" => "1.0.0",
             "language" => "pt-BR",
             "display_title" => "Avaliação inicial de dor torácica"
           }
  end

  test "GET /api/stations/active returns the boot-loaded active version", %{conn: conn} do
    conn = get(conn, ~p"/api/stations/active")

    assert %{"version" => version} = json_response(conn, 200)
    assert version == StationLoader.active_version()
  end
end
