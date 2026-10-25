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
end
