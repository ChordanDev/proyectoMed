defmodule BackendWeb.AdminAccessTest do
  @moduledoc """
  Only admins open the admin panel (issue #331, ADR-015 #347): an anonymous
  visitor goes to the login page and a student is sent away with a message.
  """

  use BackendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Backend.AccountsFixtures

  test "an anonymous visitor is redirected to the login page", %{conn: conn} do
    conn = get(conn, ~p"/admin")

    assert redirected_to(conn) == ~p"/users/log-in"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Entre"
  end

  test "a student is redirected away from the panel", %{conn: conn} do
    conn = conn |> log_in_user(user_fixture()) |> get(~p"/admin")

    assert redirected_to(conn) == ~p"/users/settings"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "administradores"
  end

  test "a student is redirected by a live navigation too", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())

    assert {:error, {:redirect, %{to: "/users/settings"}}} = live(conn, ~p"/admin")
  end

  test "an admin opens the panel", %{conn: conn} do
    conn = log_in_user(conn, admin_fixture())

    assert {:ok, _view, html} = live(conn, ~p"/admin")
    assert html =~ "Casos"
  end

  test "an admin lands on the panel after logging in with a password", %{conn: conn} do
    admin = admin_fixture()

    conn =
      post(conn, ~p"/users/log-in", %{
        "user" => %{"email" => admin.email, "password" => valid_user_password()}
      })

    assert redirected_to(conn) == ~p"/admin"
  end
end
