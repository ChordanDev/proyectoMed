defmodule BackendWeb.RevenueCatBodyReader do
  @moduledoc """
  `Plug.Parsers` body reader (#339) that keeps the raw request body of the
  RevenueCat webhook (`POST /webhooks/revenuecat`) so its HMAC signature can
  be verified over the exact bytes RevenueCat signed. Every other request is
  read exactly as `Plug.Conn.read_body/2` reads it and keeps no raw copy.

  The webhook body is capped at `max_length/0` bytes: past it the reader
  answers `{:more, _, _}` and `Plug.Parsers` replies 413.
  """

  @path "/webhooks/revenuecat"
  @max_length 1_000_000
  @key :revenuecat_raw_body

  @doc "The largest webhook body, in bytes, that is read and kept."
  @spec max_length() :: pos_integer()
  def max_length, do: @max_length

  @doc "The kept raw body of a webhook request, or `nil`."
  @spec raw_body(Plug.Conn.t()) :: binary() | nil
  def raw_body(%Plug.Conn{private: private}), do: Map.get(private, @key)

  @doc false
  def read_body(%Plug.Conn{method: "POST", request_path: @path} = conn, opts) do
    length = min(Keyword.get(opts, :length, @max_length), @max_length)

    case Plug.Conn.read_body(conn, Keyword.put(opts, :length, length)) do
      {:ok, body, conn} ->
        {:ok, body, Plug.Conn.put_private(conn, @key, (raw_body(conn) || "") <> body)}

      other ->
        other
    end
  end

  def read_body(conn, opts), do: Plug.Conn.read_body(conn, opts)
end
