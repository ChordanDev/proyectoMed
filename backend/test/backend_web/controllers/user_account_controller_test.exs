defmodule BackendWeb.UserAccountControllerTest do
  use BackendWeb.ConnCase, async: true

  import Backend.AccountsFixtures

  alias Backend.Accounts

  describe "POST /users/delete-account" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "deletes the account and logs out", %{conn: conn, user: user} do
      conn = post(conn, ~p"/users/delete-account", %{"user" => %{"email" => user.email}})

      assert redirected_to(conn) == ~p"/users/log-in"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Sua conta foi excluída."
      refute Accounts.get_user_by_email(user.email)
    end

    test "keeps the account when the typed email does not match", %{conn: conn, user: user} do
      conn = post(conn, ~p"/users/delete-account", %{"user" => %{"email" => "other@example.com"}})

      assert redirected_to(conn) == ~p"/users/settings"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Digite o seu e-mail para confirmar a exclusão da conta."

      assert Accounts.get_user_by_email(user.email)
    end

    test "asks to log in again outside sudo mode", %{user: user} do
      conn =
        build_conn()
        |> log_in_user(user,
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -21, :minute)
        )
        |> post(~p"/users/delete-account", %{"user" => %{"email" => user.email}})

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Accounts.get_user_by_email(user.email)
    end

    test "never deletes an admin account" do
      admin = admin_fixture()

      conn =
        build_conn()
        |> log_in_user(admin)
        |> post(~p"/users/delete-account", %{"user" => %{"email" => admin.email}})

      assert redirected_to(conn) == ~p"/users/settings"
      assert Accounts.get_user_by_email(admin.email)
    end

    test "requires a logged-in user" do
      conn = post(build_conn(), ~p"/users/delete-account", %{"user" => %{"email" => "a@b.c"}})

      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end
end
