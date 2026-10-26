defmodule BackendWeb.Plugs.ClientIP do
  @moduledoc """
  The trusted-proxy plug (#380): sets `conn.remote_ip` from one configured
  request header, for the rate limits of `BackendWeb.RateLimit`.

  Off by default (`config :backend, BackendWeb.Plugs.ClientIP, header: nil`):
  `conn.remote_ip` stays the socket peer. Behind Fly's proxy that peer is the
  proxy, and the real client IP is the `Fly-Client-IP` header, which the proxy
  sets itself; `TRUSTED_CLIENT_IP_HEADER=fly-client-ip` turns it on
  (`config/runtime.exs`). Enable it only when every request goes through that
  proxy, since a client that reaches the app directly can send the header
  itself. `X-Forwarded-For` is never read: clients can prepend to it.

  A missing or invalid header value keeps the socket peer.
  """

  @behaviour Plug

  import Plug.Conn, only: [get_req_header: 2]

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case Application.get_env(:backend, __MODULE__, [])[:header] do
      header when is_binary(header) and header != "" -> from_header(conn, header)
      _off -> conn
    end
  end

  defp from_header(conn, header) do
    with [value | _] <- get_req_header(conn, String.downcase(header)),
         {:ok, ip} <-
           value |> String.trim() |> String.to_charlist() |> :inet.parse_strict_address() do
      %{conn | remote_ip: ip}
    else
      _ -> conn
    end
  end
end
