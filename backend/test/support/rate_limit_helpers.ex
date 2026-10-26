defmodule BackendWeb.RateLimitHelpers do
  @moduledoc """
  Turns `BackendWeb.RateLimit` on for one test (#380). The limiter is off in
  the test config because every test conn comes from `127.0.0.1`; a module
  that turns it on must be `async: false` so no async test shares the counters.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  @doc """
  Enables the limiter with `limits` merged over the defaults, clears every
  counter, and restores the previous config when the test exits.
  """
  def enable_rate_limit(limits \\ []) do
    previous = Backend.AppEnvHelpers.snapshot(BackendWeb.RateLimit)

    Application.put_env(:backend, BackendWeb.RateLimit, enabled: true, limits: limits)
    BackendWeb.RateLimit.reset()

    on_exit(fn ->
      Backend.AppEnvHelpers.restore(BackendWeb.RateLimit, previous)
      BackendWeb.RateLimit.reset()
    end)

    :ok
  end

  @doc """
  Moves the limiter's clock `ms` milliseconds forward (#395), so a test can
  script minutes of requests without waiting. Call it after
  `enable_rate_limit/1`, which restores the clock when the test exits.
  """
  def advance_rate_limit_clock(ms) when is_integer(ms) and ms >= 0 do
    config = Application.get_env(:backend, BackendWeb.RateLimit, [])
    offset = Keyword.get(config, :clock_offset_ms, 0) + ms

    Application.put_env(
      :backend,
      BackendWeb.RateLimit,
      Keyword.put(config, :clock_offset_ms, offset)
    )
  end
end
