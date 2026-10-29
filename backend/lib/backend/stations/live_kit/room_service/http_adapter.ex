defmodule Backend.Stations.LiveKit.RoomService.HTTPAdapter do
  @moduledoc """
  Default `Backend.Stations.LiveKit.RoomService` adapter: LiveKit's Twirp
  RoomService over `Req`, authorized with a short-lived server token that
  only ever carries `roomCreate`/`roomList` grants, or, to send data, the
  `roomAdmin` grant of that one room.
  """

  @behaviour Backend.Stations.LiveKit.RoomService

  alias Backend.Stations.LiveKit

  @impl true
  def delete_room(room) do
    case request("DeleteRoom", %{"room" => room}) do
      {:ok, _body} -> :ok
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def list_rooms do
    case request("ListRooms", %{}) do
      {:ok, body} -> {:ok, extract_room_names(body)}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def send_data(room, data, opts) do
    payload =
      %{
        "room" => room,
        "data" => Base.encode64(data),
        "kind" => "RELIABLE",
        # LiveKit drops a repeated nonce, so a retried request is delivered once.
        "nonce" => Base.encode64(:crypto.strong_rand_bytes(16)),
        "destination_identities" => Keyword.get(opts, :destination_identities, [])
      }
      |> maybe_put("topic", Keyword.get(opts, :topic))

    case request("SendData", payload, &LiveKit.room_admin_token(&1, room)) do
      {:ok, _body} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Bounded so a slow/unreachable LiveKit fails fast instead of holding a
  # caller (e.g. the periodic orphan sweep, or session completion/discard)
  # for Req's much longer 15 s default. Overridable via :livekit_req_options.
  @default_timeout_ms :timer.seconds(3)

  defp request(rpc, payload, sign \\ &LiveKit.server_token/1) do
    with {:ok, config} <- LiveKit.config() do
      url = base_url(config.url) <> "/twirp/livekit.RoomService/" <> rpc
      token = sign.(config)

      req_opts =
        [auth: {:bearer, token}, json: payload, retry: false]
        |> Keyword.merge(
          receive_timeout: @default_timeout_ms,
          connect_options: [timeout: @default_timeout_ms]
        )
        |> Keyword.merge(req_options())

      handle_response(Req.post(url, req_opts))
    end
  end

  defp handle_response({:ok, %Req.Response{status: 404}}), do: {:error, :not_found}

  defp handle_response({:ok, %Req.Response{status: s, body: %{"code" => "not_found"}}})
       when s in 200..599,
       do: {:error, :not_found}

  defp handle_response({:ok, %Req.Response{status: s, body: body}}) when s in 200..299,
    do: {:ok, body}

  defp handle_response({:ok, %Req.Response{}}), do: {:error, :livekit_unavailable}
  defp handle_response({:error, _reason}), do: {:error, :livekit_unavailable}

  defp base_url(ws_url) do
    ws_url
    |> String.replace_leading("wss://", "https://")
    |> String.replace_leading("ws://", "http://")
    |> String.trim_trailing("/")
  end

  defp extract_room_names(%{"rooms" => rooms}) when is_list(rooms) do
    rooms
    |> Enum.map(fn
      %{"name" => name} -> name
      _other -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_room_names(_body), do: []

  defp req_options do
    Application.get_env(:backend, :livekit_req_options, [])
  end
end
