defmodule BackendWeb.Plugs.ClientIPTest do
  @moduledoc """
  The trusted-proxy plug (#380): off by default, it keeps `conn.remote_ip`;
  configured with a header (Fly's `fly-client-ip`), it takes the client IP
  from that header when the header holds a valid address.
  """

  use ExUnit.Case, async: false

  import Plug.Test, only: [conn: 2]
  import Plug.Conn, only: [put_req_header: 3]

  alias BackendWeb.Plugs.ClientIP

  setup do
    previous = Application.get_env(:backend, ClientIP)
    on_exit(fn -> Application.put_env(:backend, ClientIP, previous) end)
    :ok
  end

  defp call(headers) do
    conn = Enum.reduce(headers, conn(:get, "/"), fn {k, v}, c -> put_req_header(c, k, v) end)
    ClientIP.call(%{conn | remote_ip: {127, 0, 0, 1}}, ClientIP.init([]))
  end

  test "keeps the socket address by default, whatever the request headers say" do
    Application.put_env(:backend, ClientIP, header: nil)

    conn = call([{"fly-client-ip", "203.0.113.7"}, {"x-forwarded-for", "198.51.100.1"}])

    assert conn.remote_ip == {127, 0, 0, 1}
  end

  test "takes the client IP from the configured header" do
    Application.put_env(:backend, ClientIP, header: "fly-client-ip")

    assert call([{"fly-client-ip", "203.0.113.7"}]).remote_ip == {203, 0, 113, 7}
    assert call([{"fly-client-ip", " 2001:db8::1 "}]).remote_ip == {8193, 3512, 0, 0, 0, 0, 0, 1}
  end

  test "keeps the socket address when the configured header is missing or invalid" do
    Application.put_env(:backend, ClientIP, header: "fly-client-ip")

    assert call([]).remote_ip == {127, 0, 0, 1}
    assert call([{"fly-client-ip", "not-an-ip"}]).remote_ip == {127, 0, 0, 1}
    assert call([{"x-forwarded-for", "198.51.100.1"}]).remote_ip == {127, 0, 0, 1}
  end
end
