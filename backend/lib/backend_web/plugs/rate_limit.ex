defmodule BackendWeb.Plugs.RateLimit do
  @moduledoc """
  Throttles an API action per client IP (#380), with `BackendWeb.RateLimit`.
  Beyond the limit it halts with `429`, a `retry-after` header (seconds) and
  the JSON error `rate_limited`:

      plug BackendWeb.Plugs.RateLimit, :device_start when action in [:start]
  """

  @behaviour Plug

  import Plug.Conn

  alias BackendWeb.RateLimit

  @impl true
  def init(action) when is_atom(action), do: action

  @impl true
  def call(conn, action) do
    case RateLimit.check(action, ip: conn.remote_ip) do
      :ok ->
        conn

      {:error, :rate_limited, retry_after} ->
        too_many_requests(
          conn,
          retry_after,
          "Muitas tentativas. Aguarde #{retry_after} s e tente novamente."
        )
    end
  end

  @doc """
  Halts `conn` with `429`, the `retry-after` header (seconds), and the JSON
  error `rate_limited` carrying the pt-BR `message`.
  """
  @spec too_many_requests(Plug.Conn.t(), pos_integer(), String.t()) :: Plug.Conn.t()
  def too_many_requests(conn, retry_after, message) do
    conn
    |> put_resp_header("retry-after", Integer.to_string(retry_after))
    |> put_resp_header("cache-control", "no-store")
    |> put_status(:too_many_requests)
    |> Phoenix.Controller.json(%{error: "rate_limited", message: message})
    |> halt()
  end
end
