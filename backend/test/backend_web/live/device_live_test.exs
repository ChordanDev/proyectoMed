defmodule BackendWeb.DeviceLiveTest do
  @moduledoc """
  The browser page of the device login (#337): the learner logs in, sees the
  user code of the Unreal client and approves or denies it.
  """

  use BackendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Backend.AccountsFixtures

  alias Backend.Accounts

  setup do
    {:ok, start} = Accounts.start_device_authorization()
    %{start: start}
  end

  test "asks an anonymous visitor to log in and comes back to the code", %{
    conn: conn,
    start: start
  } do
    path = ~p"/device?#{[user_code: start.user_code]}"

    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, path)

    conn = get(conn, path)
    assert redirected_to(conn) == ~p"/users/log-in"
    assert get_session(conn, :user_return_to) == path
  end

  describe "a logged-in learner" do
    setup :register_and_log_in_user

    test "approves the code from the verification link", %{conn: conn, start: start} do
      {:ok, lv, html} = live(conn, ~p"/device?#{[user_code: start.user_code]}")

      assert html =~ start.user_code
      assert html =~ "Autorizar"

      html = lv |> element("#device-approve") |> render_click()
      assert html =~ "Pronto"

      assert {:ok, _tokens} = Accounts.poll_device_authorization(start.device_code)
    end

    test "types the code, then denies it", %{conn: conn, start: start} do
      {:ok, lv, html} = live(conn, ~p"/device")
      assert html =~ "Código do aplicativo"

      html =
        lv
        |> form("#device-code-form", device: %{user_code: String.downcase(start.user_code)})
        |> render_submit()

      assert html =~ start.user_code

      html = lv |> element("#device-deny") |> render_click()
      assert html =~ "Acesso negado"

      assert {:error, :access_denied} = Accounts.poll_device_authorization(start.device_code)
    end

    test "rejects an unknown or expired code", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/device")

      html =
        lv
        |> form("#device-code-form", device: %{user_code: "BBBB-BBBB"})
        |> render_submit()

      assert html =~ "Código inválido ou expirado"

      {:ok, _lv, html} = live(conn, ~p"/device?user_code=BBBB-BBBB")
      assert html =~ "Código inválido ou expirado"
    end
  end

  test "an admin may not use the device login", %{conn: conn, start: start} do
    conn = log_in_user(conn, admin_fixture())

    {:ok, _lv, html} = live(conn, ~p"/device?#{[user_code: start.user_code]}")

    assert html =~ "Contas de administrador não podem entrar no aplicativo"
    refute html =~ "device-approve"

    assert {:error, :authorization_pending} =
             Accounts.poll_device_authorization(start.device_code)
  end
end
