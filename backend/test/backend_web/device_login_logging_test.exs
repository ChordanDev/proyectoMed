defmodule BackendWeb.DeviceLoginLoggingTest do
  @moduledoc """
  No device code, user code or token of the device login (#337) appears in
  the logs, even at debug level where Phoenix logs request parameters.
  """

  # Changes the global Logger level: not async.
  use BackendWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest
  import Backend.AccountsFixtures

  setup do
    user = user_fixture()
    level = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: level) end)
    %{user: user}
  end

  test "the whole flow logs no code or token", %{conn: conn, user: user} do
    browser = log_in_user(build_conn(), user)
    {:ok, agent} = Agent.start_link(fn -> [] end)
    remember = fn values -> Agent.update(agent, &(values ++ &1)) end

    log =
      capture_log(fn ->
        start = conn |> post(~p"/device/start") |> json_response(200)
        remember.([start["device_code"], start["user_code"]])

        post(conn, ~p"/device/token", %{device_code: start["device_code"]})

        {:ok, lv, _html} = live(browser, ~p"/device?#{[user_code: start["user_code"]]}")
        lv |> element("#device-approve") |> render_click()

        {:ok, lv, _html} = live(browser, ~p"/device")

        lv
        |> form("#device-code-form", device: %{user_code: start["user_code"]})
        |> render_submit()

        tokens =
          conn
          |> post(~p"/device/token", %{device_code: start["device_code"]})
          |> json_response(200)

        refreshed =
          conn
          |> post(~p"/device/refresh", %{refresh_token: tokens["refresh_token"]})
          |> json_response(200)

        remember.([tokens["access_token"], tokens["refresh_token"]])
        remember.([refreshed["access_token"], refreshed["refresh_token"]])

        conn
        |> put_req_header("authorization", "Bearer " <> refreshed["access_token"])
        |> get(~p"/stations")

        conn
        |> put_req_header("authorization", "Bearer " <> refreshed["access_token"])
        |> post(~p"/device/logout")
      end)

    secrets = Agent.get(agent, & &1)
    assert length(secrets) == 6
    assert log =~ "/device/token"

    for secret <- secrets do
      refute log =~ secret
      refute log =~ String.replace(secret, "-", "")
    end
  end
end
