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

  describe "send_data/3" do
    test "sends a reliable message to the named participants of one room" do
      Application.put_env(:backend, :livekit_url, "ws://127.0.0.1:7880")
      test_pid = self()

      Application.put_env(:backend, :livekit_req_options,
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          [auth] = Plug.Conn.get_req_header(conn, "authorization")
          send(test_pid, {:request, conn.request_path, auth, Jason.decode!(body)})
          Req.Test.json(conn, %{})
        end
      )

      assert :ok =
               RoomService.send_data("station-session-abc", ~s({"text":"Olá"}),
                 topic: "typed-reply",
                 destination_identities: ["voice-worker"]
               )

      assert_receive {:request, "/twirp/livekit.RoomService/SendData", "Bearer " <> token, body}
      assert body["room"] == "station-session-abc"
      assert Base.decode64!(body["data"]) == ~s({"text":"Olá"})
      assert body["kind"] == "RELIABLE"
      assert body["topic"] == "typed-reply"
      assert body["destination_identities"] == ["voice-worker"]
      assert byte_size(Base.decode64!(body["nonce"])) == 16

      [_header, claims, _signature] = String.split(token, ".")
      claims = claims |> Base.url_decode64!(padding: false) |> Jason.decode!()
      assert claims["video"] == %{"roomAdmin" => true, "room" => "station-session-abc"}
    end

    test "reports an unreachable LiveKit as unavailable" do
      Application.put_env(:backend, :livekit_url, "ws://127.0.0.1:7880")

      Application.put_env(:backend, :livekit_req_options,
        plug: fn conn -> Plug.Conn.send_resp(conn, 503, "") end
      )

      assert {:error, :livekit_unavailable} =
               RoomService.send_data("station-session-abc", "{}", topic: "typed-reply")
    end
  end
end
