defmodule Backend.Stations.LiveKit.RoomServiceTest do
  use ExUnit.Case, async: false

  alias Backend.Stations.LiveKit.RoomService

  @api_key "test-api-key"
  @api_secret "test-api-secret"

  setup do
    Application.put_env(:backend, :livekit_url, "wss://revalida.livekit.cloud")
    Application.put_env(:backend, :livekit_api_key, @api_key)
    Application.put_env(:backend, :livekit_api_secret, @api_secret)

    on_exit(fn ->
      Application.delete_env(:backend, :livekit_url)
      Application.delete_env(:backend, :livekit_api_key)
      Application.delete_env(:backend, :livekit_api_secret)
      Application.delete_env(:backend, :livekit_req_options)
    end)

    :ok
  end

  defp stub_livekit(stub, fun) do
    Req.Test.stub(stub, fun)
    Application.put_env(:backend, :livekit_req_options, plug: {Req.Test, stub})
  end

  defp decode_bearer_video(auth_header) do
    ["Bearer " <> token] = auth_header
    [_header, claims_b64, _sig] = String.split(token, ".")
    claims_b64 |> Base.url_decode64!(padding: false) |> Jason.decode!() |> Map.fetch!("video")
  end

  test "delete_room/1 posts the Twirp DeleteRoom request with a roomCreate/roomList-only token" do
    test_pid = self()

    stub_livekit(DeleteStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(
        test_pid,
        {:req, conn.request_path, Plug.Conn.get_req_header(conn, "authorization"), body}
      )

      Req.Test.json(conn, %{})
    end)

    assert RoomService.delete_room("station-session-abc") == :ok

    assert_receive {:req, path, auth, body}
    assert path == "/twirp/livekit.RoomService/DeleteRoom"
    assert %{"room" => "station-session-abc"} = Jason.decode!(body)

    video = decode_bearer_video(auth)
    assert video == %{"roomCreate" => true, "roomList" => true}
  end

  test "delete_room/1 treats a Twirp not_found response as success (idempotent)" do
    stub_livekit(NotFoundStub, fn conn ->
      conn
      |> Plug.Conn.put_status(404)
      |> Req.Test.json(%{"code" => "not_found", "msg" => "room does not exist"})
    end)

    assert RoomService.delete_room("station-session-gone") == :ok
  end

  test "delete_room/1 returns an error on an upstream failure" do
    stub_livekit(BoomStub, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

    assert {:error, _reason} = RoomService.delete_room("station-session-x")
  end

  test "list_rooms/0 posts the Twirp ListRooms request and extracts room names" do
    stub_livekit(ListStub, fn conn ->
      Req.Test.json(conn, %{
        "rooms" => [%{"name" => "station-session-a"}, %{"name" => "station-session-b"}]
      })
    end)

    assert RoomService.list_rooms() == {:ok, ["station-session-a", "station-session-b"]}
  end

  test "list_rooms/0 returns an empty list when there are no rooms" do
    stub_livekit(EmptyListStub, fn conn -> Req.Test.json(conn, %{"rooms" => []}) end)

    assert RoomService.list_rooms() == {:ok, []}
  end

  test "the adapter is overridable via :livekit_room_service application env" do
    defmodule DoubleAdapter do
      @behaviour Backend.Stations.LiveKit.RoomService

      @impl true
      def delete_room(_room), do: :ok

      @impl true
      def list_rooms, do: {:ok, ["station-session-double"]}
    end

    Application.put_env(:backend, :livekit_room_service, DoubleAdapter)
    on_exit(fn -> Application.delete_env(:backend, :livekit_room_service) end)

    assert RoomService.list_rooms() == {:ok, ["station-session-double"]}
    assert RoomService.delete_room("anything") == :ok
  end
end
