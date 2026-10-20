defmodule Backend.Stations.LiveKit.RoomService.HTTPAdapterTest do
  use ExUnit.Case, async: false

  alias Backend.Stations.LiveKit.RoomService

  setup do
    Application.put_env(:backend, :livekit_api_key, "test-api-key")
    Application.put_env(:backend, :livekit_api_secret, "test-api-secret")

    on_exit(fn ->
      Application.delete_env(:backend, :livekit_url)
      Application.delete_env(:backend, :livekit_api_key)
      Application.delete_env(:backend, :livekit_api_secret)
      Application.delete_env(:backend, :livekit_req_options)
    end)

    :ok
  end

  # Opens a TCP listener that accepts the connection but never writes a
  # response, simulating an unreachable/hanging LiveKit server so the
  # adapter's receive timeout (not Req's 15 s default) is what fires.
  defp start_unresponsive_server do
    {:ok, listen_socket} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(listen_socket)

    acceptor =
      spawn(fn ->
        case :gen_tcp.accept(listen_socket, 5_000) do
          {:ok, _socket} -> Process.sleep(:infinity)
          _other -> :ok
        end
      end)

    on_exit(fn ->
      Process.exit(acceptor, :kill)
      :gen_tcp.close(listen_socket)
    end)

    port
  end

  test "requests bound their timeout by default instead of Req's 15 s default" do
    port = start_unresponsive_server()
    Application.put_env(:backend, :livekit_url, "http://127.0.0.1:#{port}")

    {elapsed_us, result} = :timer.tc(fn -> RoomService.list_rooms() end)

    assert {:error, _reason} = result
    assert elapsed_us < 5_000_000
  end

  test "the default timeout is overridable via :livekit_req_options" do
    port = start_unresponsive_server()
    Application.put_env(:backend, :livekit_url, "http://127.0.0.1:#{port}")
    Application.put_env(:backend, :livekit_req_options, receive_timeout: 50)

    {elapsed_us, result} = :timer.tc(fn -> RoomService.list_rooms() end)

    assert {:error, _reason} = result
    assert elapsed_us < 1_000_000
  end
end
