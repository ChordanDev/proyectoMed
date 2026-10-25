defmodule BackendWeb.DeviceRateLimitTest do
  @moduledoc """
  Throttling of the unauthenticated `POST /device/start` per client IP (#380):
  beyond the limit it answers `429` with the `rate_limited` error.
  """

  use BackendWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import BackendWeb.RateLimitHelpers

  defp start(conn, ip), do: post(%{conn | remote_ip: ip}, ~p"/device/start")

  test "answers 429 rate_limited beyond the limit and allows starts again after the window",
       %{conn: conn} do
    enable_rate_limit(device_start: [ip: {2, 300}])
    ip = {10, 1, 0, 1}

    assert %{"user_code" => _} = conn |> start(ip) |> json_response(200)
    assert %{"user_code" => _} = build_conn() |> start(ip) |> json_response(200)

    {limited, log} = with_log(fn -> build_conn() |> start(ip) end)

    assert %{"error" => "rate_limited", "message" => message} = json_response(limited, 429)
    assert message =~ "Muitas tentativas"
    assert [retry_after] = get_resp_header(limited, "retry-after")
    assert String.to_integer(retry_after) >= 1
    refute log =~ "10.1.0.1"

    # Another client is not affected.
    assert %{"user_code" => _} = build_conn() |> start({10, 1, 0, 2}) |> json_response(200)

    Process.sleep(350)

    assert %{"user_code" => _} = build_conn() |> start(ip) |> json_response(200)
  end

  test "never throttles one Unreal client polling at the advertised interval", %{conn: conn} do
    enable_rate_limit()
    ip = {10, 1, 0, 3}

    body = conn |> start(ip) |> json_response(200)

    # Every poll the client may send during the code's lifetime.
    polls = div(body["expires_in"], body["interval"])

    for _ <- 1..polls do
      response =
        build_conn()
        |> Map.put(:remote_ip, ip)
        |> post(~p"/device/token", %{device_code: body["device_code"]})

      refute response.status == 429
    end

    # The client may restart the login a few times.
    for _ <- 1..3,
        do: assert(%{"user_code" => _} = build_conn() |> start(ip) |> json_response(200))
  end
end
