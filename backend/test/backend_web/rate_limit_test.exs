defmodule BackendWeb.RateLimitTest do
  @moduledoc """
  The in-memory limiter of the public authentication endpoints (#380): a
  window of `limit` requests per key opens on the first request.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import BackendWeb.RateLimitHelpers

  alias BackendWeb.RateLimit

  @ip {10, 0, 0, 1}

  test "refuses requests beyond the limit and allows them again after the window" do
    enable_rate_limit(device_start: [ip: {2, 200}])

    assert :ok = RateLimit.check(:device_start, ip: @ip)
    assert :ok = RateLimit.check(:device_start, ip: @ip)
    assert {:error, :rate_limited, retry_after} = RateLimit.check(:device_start, ip: @ip)
    assert retry_after in 1..1

    Process.sleep(250)

    assert :ok = RateLimit.check(:device_start, ip: @ip)
  end

  test "counts every key and every action apart" do
    enable_rate_limit(login: [ip: {1, 60_000}, email: {1, 60_000}], sign_up: [ip: {1, 60_000}])

    assert :ok = RateLimit.check(:login, ip: @ip, email: "a@example.com")
    assert {:error, :rate_limited, _} = RateLimit.check(:login, ip: @ip, email: "b@example.com")

    assert {:error, :rate_limited, _} =
             RateLimit.check(:login, ip: {10, 0, 0, 2}, email: "a@example.com")

    assert :ok = RateLimit.check(:login, ip: {10, 0, 0, 3}, email: "c@example.com")
    assert :ok = RateLimit.check(:sign_up, ip: @ip)
  end

  test "treats an email the same whatever its case and surrounding spaces" do
    enable_rate_limit(login: [email: {1, 60_000}])

    assert :ok = RateLimit.check(:login, email: "Learner@Example.com")
    assert {:error, :rate_limited, _} = RateLimit.check(:login, email: "  learner@example.com ")
  end

  test "ignores a missing key value" do
    enable_rate_limit(login: [ip: {1, 60_000}, email: {1, 60_000}])

    assert :ok = RateLimit.check(:login, ip: @ip, email: nil)
    assert :ok = RateLimit.check(:login, ip: {10, 0, 0, 2}, email: nil)
  end

  test "allows everything when disabled" do
    enable_rate_limit(device_start: [ip: {1, 60_000}])

    Application.put_env(:backend, RateLimit,
      enabled: false,
      limits: [device_start: [ip: {1, 60_000}]]
    )

    for _ <- 1..5, do: assert(:ok = RateLimit.check(:device_start, ip: @ip))
  end

  test "logs the action and the key kind, never the key" do
    enable_rate_limit(login: [email: {1, 60_000}])
    :ok = RateLimit.check(:login, email: "secret-learner@example.com")

    log =
      capture_log([level: :warning], fn ->
        assert {:error, :rate_limited, _} =
                 RateLimit.check(:login, email: "secret-learner@example.com")
      end)

    assert log =~ "rate limited"
    assert log =~ "login"
    assert log =~ "email"
    refute log =~ "secret-learner"
  end

  test "sweeps the windows that already expired" do
    enable_rate_limit(device_start: [ip: {1, 1}])
    :ok = RateLimit.check(:device_start, ip: @ip)
    Process.sleep(5)

    assert RateLimit.sweep() >= 1
  end
end
