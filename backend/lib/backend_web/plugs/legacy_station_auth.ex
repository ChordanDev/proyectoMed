defmodule BackendWeb.Plugs.LegacyStationAuth do
  @moduledoc """
  The deprecated `/api/stations/...` routes (issue #334) stay unauthenticated
  for the frozen web harness and the E2E suite only where
  `:legacy_station_api_unauthenticated` is true (dev and test). Elsewhere, as
  in production, they require the device access token and the session's
  owner like the `/sessions` routes (#337).
  """

  @behaviour Plug

  alias BackendWeb.Plugs.{DeviceAuth, SessionOwner}

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if Application.get_env(:backend, :legacy_station_api_unauthenticated, false) do
      conn
    else
      conn = DeviceAuth.call(conn, [])
      if conn.halted, do: conn, else: SessionOwner.call(conn, [])
    end
  end
end
