defmodule BackendWeb.AdminLiveTest do
  @moduledoc """
  The placeholder admin LiveView renders inside the root layout (issue #329)
  for a logged-in admin (issue #331).
  """

  use BackendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Backend.AccountsFixtures

  test "renders the placeholder admin page in pt-BR", %{conn: conn} do
    conn = conn |> log_in_user(admin_fixture()) |> get(~p"/admin")
    html = html_response(conn, 200)

    assert html =~ ~s(lang="pt-BR")
    assert html =~ ~s(<meta name="csrf-token")
    assert html =~ "Painel administrativo"

    {:ok, view, _html} = live(conn)

    assert has_element?(view, "#admin-status", "Backend em funcionamento")
  end
end
