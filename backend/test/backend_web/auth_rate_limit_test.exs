defmodule BackendWeb.AuthRateLimitTest do
  @moduledoc """
  Throttling of the browser authentication endpoints (#380): password and
  link login (`POST /users/log-in`), login-link and password-reset emails,
  sign-up, and the user-code lookups of `/device`. Beyond the limit the page
  shows a pt-BR flash and does nothing else; after the window it works again.
  """

  use BackendWeb.ConnCase, async: false

  import Ecto.Query, only: [from: 2]
  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest
  import Backend.AccountsFixtures
  import BackendWeb.RateLimitHelpers

  alias Backend.Accounts

  @limited "Muitas tentativas"

  defp from_ip(conn, ip), do: %{conn | remote_ip: ip}

  defp tokens(user, context) do
    Backend.Repo.aggregate(
      from(t in Accounts.UserToken, where: t.user_id == ^user.id and t.context == ^context),
      :count
    )
  end

  defp password_login(ip, email, password) do
    build_conn()
    |> from_ip(ip)
    |> post(~p"/users/log-in", %{"user" => %{"email" => email, "password" => password}})
  end

  describe "POST /users/log-in" do
    test "refuses logins beyond the per-email limit, even with the right password, until the window ends" do
      enable_rate_limit(login: [email: {2, 400}])
      user = user_fixture() |> set_password()

      for ip <- [{10, 2, 0, 1}, {10, 2, 0, 2}] do
        conn = password_login(ip, user.email, "wrong password!")
        assert Phoenix.Flash.get(conn.assigns.flash, :error) == "E-mail ou senha inválidos"
      end

      {conn, log} =
        with_log(fn -> password_login({10, 2, 0, 3}, user.email, valid_user_password()) end)

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ @limited
      refute get_session(conn, :user_token)
      refute log =~ user.email

      Process.sleep(450)

      conn = password_login({10, 2, 0, 3}, user.email, valid_user_password())
      assert get_session(conn, :user_token)
    end

    test "refuses logins beyond the per-IP limit, whatever the email" do
      enable_rate_limit(login: [ip: {1, 60_000}])
      user = user_fixture() |> set_password()
      ip = {10, 2, 0, 4}

      password_login(ip, "someone@example.com", "wrong password!")
      conn = password_login(ip, user.email, valid_user_password())

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ @limited
      refute get_session(conn, :user_token)
    end

    test "refuses link logins beyond the per-IP limit" do
      enable_rate_limit(login: [ip: {1, 60_000}])
      user = user_fixture()
      ip = {10, 2, 0, 5}

      first = generate_user_magic_link_token(user_fixture()) |> elem(0)
      build_conn() |> from_ip(ip) |> post(~p"/users/log-in", %{"user" => %{"token" => first}})
      token = generate_user_magic_link_token(user) |> elem(0)

      conn =
        build_conn() |> from_ip(ip) |> post(~p"/users/log-in", %{"user" => %{"token" => token}})

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ @limited
      refute get_session(conn, :user_token)
    end

    test "never throttles one learner who mistypes the password twice and then logs in" do
      enable_rate_limit()
      user = user_fixture() |> set_password()
      ip = {10, 2, 0, 6}

      password_login(ip, user.email, "wrong password!")
      password_login(ip, user.email, "wrong password!")
      conn = password_login(ip, user.email, valid_user_password())

      assert get_session(conn, :user_token)
    end
  end

  describe "login-link email" do
    defp request_link(ip, email) do
      {:ok, lv, _html} = build_conn() |> from_ip(ip) |> live(~p"/users/log-in")
      lv |> form("#login_form_magic", user: %{email: email}) |> render_submit()
    end

    test "refuses requests beyond the per-email limit and sends nothing, until the window ends" do
      enable_rate_limit(magic_link_email: [email: {1, 400}])
      user = user_fixture()

      assert {:error, {:live_redirect, _}} = request_link({10, 3, 0, 1}, user.email)
      assert tokens(user, "login") == 1

      {html, log} = with_log(fn -> request_link({10, 3, 0, 2}, user.email) end)

      assert html =~ @limited
      assert tokens(user, "login") == 1
      refute log =~ user.email

      Process.sleep(450)

      assert {:error, {:live_redirect, _}} = request_link({10, 3, 0, 2}, user.email)
      assert tokens(user, "login") == 2
    end

    test "refuses requests beyond the per-IP limit, whatever the email" do
      enable_rate_limit(magic_link_email: [ip: {1, 60_000}])
      user = user_fixture()

      request_link({10, 3, 0, 3}, "someone@example.com")
      html = request_link({10, 3, 0, 3}, user.email)

      assert html =~ @limited
      assert tokens(user, "login") == 0
    end
  end

  describe "password-reset email" do
    defp request_reset(ip, email) do
      {:ok, lv, _html} = build_conn() |> from_ip(ip) |> live(~p"/users/reset-password")
      lv |> form("#reset_password_form", user: %{email: email}) |> render_submit()
    end

    test "refuses requests beyond the per-email limit and sends nothing, until the window ends" do
      enable_rate_limit(reset_password_email: [email: {1, 400}])
      user = user_fixture()

      assert {:error, {:live_redirect, _}} = request_reset({10, 4, 0, 1}, user.email)
      assert tokens(user, "reset_password") == 1

      {html, log} = with_log(fn -> request_reset({10, 4, 0, 2}, user.email) end)

      assert html =~ @limited
      assert tokens(user, "reset_password") == 1
      refute log =~ user.email

      Process.sleep(450)

      assert {:error, {:live_redirect, _}} = request_reset({10, 4, 0, 2}, user.email)
      assert tokens(user, "reset_password") == 2
    end

    test "refuses requests beyond the per-IP limit, whatever the email" do
      enable_rate_limit(reset_password_email: [ip: {1, 60_000}])
      user = user_fixture()

      request_reset({10, 4, 0, 3}, "someone@example.com")
      html = request_reset({10, 4, 0, 3}, user.email)

      assert html =~ @limited
      assert tokens(user, "reset_password") == 0
    end
  end

  describe "sign-up" do
    defp sign_up(ip, email) do
      {:ok, lv, _html} = build_conn() |> from_ip(ip) |> live(~p"/users/register")

      lv
      |> form("#registration_form",
        user: %{email: email, terms_accepted: "true", privacy_accepted: "true"}
      )
      |> render_submit()
    end

    test "refuses sign-ups beyond the per-IP limit until the window ends" do
      enable_rate_limit(sign_up: [ip: {1, 400}])
      ip = {10, 5, 0, 1}

      assert {:error, {:live_redirect, _}} = sign_up(ip, unique_user_email())

      email = unique_user_email()
      {html, log} = with_log(fn -> sign_up(ip, email) end)

      assert html =~ @limited
      refute Accounts.get_user_by_email(email)
      refute log =~ email

      # Another client is not affected.
      assert {:error, {:live_redirect, _}} = sign_up({10, 5, 0, 2}, unique_user_email())

      Process.sleep(450)

      assert {:error, {:live_redirect, _}} = sign_up(ip, email)
      assert Accounts.get_user_by_email(email)
    end
  end

  describe "/device user-code lookups" do
    setup :register_and_log_in_user

    defp lookup(lv, user_code) do
      lv |> form("#device-code-form", device: %{user_code: user_code}) |> render_submit()
    end

    test "refuses lookups beyond the per-user limit, even of a valid code, until the window ends",
         %{conn: conn} do
      enable_rate_limit(device_lookup: [user: {2, 400}])
      {:ok, start} = Accounts.start_device_authorization()
      {:ok, lv, _html} = conn |> from_ip({10, 6, 0, 1}) |> live(~p"/device")

      assert lookup(lv, "AAAA-AAAA") =~ "Código inválido ou expirado"
      assert lookup(lv, "BBBB-BBBB") =~ "Código inválido ou expirado"

      {html, log} = with_log(fn -> lookup(lv, start.user_code) end)

      assert html =~ @limited
      refute html =~ "Autorizar"
      refute log =~ start.user_code

      Process.sleep(450)

      assert lookup(lv, start.user_code) =~ "Autorizar"
    end

    test "refuses lookups beyond the per-IP limit, including from the verification link",
         %{conn: conn} do
      enable_rate_limit(device_lookup: [ip: {1, 60_000}])
      {:ok, start} = Accounts.start_device_authorization()
      conn = from_ip(conn, {10, 6, 0, 2})

      # The verification link looks the code up on the static and the live render.
      {:ok, _lv, html} = live(conn, ~p"/device?#{[user_code: start.user_code]}")

      assert html =~ @limited
      refute html =~ "Autorizar"
    end

    test "never throttles one learner following the verification link", %{conn: conn} do
      enable_rate_limit()
      {:ok, start} = Accounts.start_device_authorization()

      {:ok, lv, html} =
        conn |> from_ip({10, 6, 0, 3}) |> live(~p"/device?#{[user_code: start.user_code]}")

      assert html =~ "Autorizar"
      assert lv |> element("#device-approve") |> render_click() =~ "Pronto!"
    end
  end

  test "never throttles one learner signing up, asking for a link and logging in" do
    enable_rate_limit()
    ip = {10, 7, 0, 1}
    email = unique_user_email()

    assert {:error, {:live_redirect, _}} = sign_up(ip, email)
    user = Accounts.get_user_by_email(email)

    assert {:error, {:live_redirect, _}} = request_link(ip, email)
    assert {:error, {:live_redirect, _}} = request_reset(ip, email)

    token = generate_user_magic_link_token(user) |> elem(0)

    conn =
      build_conn() |> from_ip(ip) |> post(~p"/users/log-in", %{"user" => %{"token" => token}})

    assert get_session(conn, :user_token)
  end
end
