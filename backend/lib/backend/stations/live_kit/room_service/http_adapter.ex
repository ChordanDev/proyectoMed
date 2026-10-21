defmodule Backend.Stations.LiveKit.RoomService.HTTPAdapter do
  @moduledoc """
  Default `Backend.Stations.LiveKit.RoomService` adapter: LiveKit's Twirp
  RoomService over `Req`, authorized with a short-lived server token that
  only ever carries `roomCreate`/`roomList` grants.
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

  # Bounded so a slow/unreachable LiveKit fails fast instead of holding a
  # caller (e.g. the periodic orphan sweep, or session completion/discard)
  # for Req's much longer 15 s default. Overridable via :livekit_req_options.
  @default_timeout_ms :timer.seconds(3)

  defp request(rpc, payload) do
    with {:ok, config} <- LiveKit.config() do
      url = base_url(config.url) <> "/twirp/livekit.RoomService/" <> rpc
      token = LiveKit.server_token(config)

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
