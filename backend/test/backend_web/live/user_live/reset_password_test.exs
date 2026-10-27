defmodule BackendWeb.UserLive.ResetPasswordTest do
  use BackendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Backend.AccountsFixtures

  alias Backend.Accounts

  @generic_info "Se o seu e-mail estiver cadastrado, você receberá em instantes um link para redefinir a senha."

  describe "forgot password page" do
    test "the login page links to it", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      assert has_element?(lv, ~s|a[href="/users/reset-password"]|)
    end

    test "emails a reset link to a registered user", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

      {:ok, _lv, html} =
        lv
        |> form("#reset_password_form", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ @generic_info

      assert Backend.Repo.get_by!(Backend.Accounts.UserToken, user_id: user.id).context ==
               "reset_password"
    end

    test "does not disclose whether the email is registered", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

      {:ok, _lv, html} =
        lv
        |> form("#reset_password_form", user: %{email: "nobody@example.com"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ @generic_info
      assert Backend.Repo.all(Backend.Accounts.UserToken) == []
    end
  end

  describe "reset password page" do
    setup do
      user = user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      %{user: user, token: token}
    end

    test "an invalid link goes back to the login page", %{conn: conn} do
      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/users/reset-password/invalid")

      assert path == ~p"/users/log-in"
      assert flash["error"] == "O link para redefinir a senha é inválido ou expirou."
    end

    test "sets a new password that logs in", %{conn: conn, user: user, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password/#{token}")

      {:ok, conn} =
        lv
        |> form("#new_password_form",
          user: %{password: "a brand new password", password_confirmation: "a brand new password"}
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "Senha redefinida. Entre com a nova senha."

      assert Accounts.get_user_by_email_and_password(user.email, "a brand new password")
      refute Accounts.get_user_by_reset_password_token(token)
    end

    test "refuses a submit once the link stopped being valid", %{
      conn: conn,
      user: user,
      token: token
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password/#{token}")

      # The owner recovers the account elsewhere while this page stays open.
      {:ok, _} = Accounts.reset_user_password(user, %{password: "the owner's new password"})

      {:ok, conn} =
        lv
        |> form("#new_password_form",
          user: %{password: "an attacker password", password_confirmation: "an attacker password"}
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "O link para redefinir a senha é inválido ou expirou."

      refute Accounts.get_user_by_email_and_password(user.email, "an attacker password")
      assert Accounts.get_user_by_email_and_password(user.email, "the owner's new password")
    end

    test "shows the password errors", %{conn: conn, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset-password/#{token}")

      html =
        lv
        |> form("#new_password_form",
          user: %{password: "short", password_confirmation: "other"}
        )
        |> render_submit()

      assert html =~ "deve ter entre 12 e 72 caracteres"
      assert html =~ "não confere com a senha"
    end
  end
end
