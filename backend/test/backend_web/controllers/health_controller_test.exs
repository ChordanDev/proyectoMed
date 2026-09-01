defmodule BackendWeb.HealthControllerTest do
  use BackendWeb.ConnCase, async: true

  test "GET / returns the health status", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert json_response(conn, 200) == %{"status" => "ok"}
  end
end
