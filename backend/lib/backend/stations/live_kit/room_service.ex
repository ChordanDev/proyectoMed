defmodule Backend.Stations.LiveKit.RoomService do
  @moduledoc """
  Behaviour for the LiveKit RoomService external seam: deleting a room on
  session completion/discard, and listing rooms for the orphan sweep.

  The default adapter (`Backend.Stations.LiveKit.RoomService.HTTPAdapter`)
  speaks Twirp over `Req`. Override with the `:backend, :livekit_room_service`
  application env, mirroring how `Backend.Stations.StationAI` adapters are
  selected.
  """

  @callback delete_room(room :: String.t()) :: :ok | {:error, term()}
  @callback list_rooms() :: {:ok, [String.t()]} | {:error, term()}

  alias Backend.Stations.LiveKit.RoomService.HTTPAdapter

  @spec delete_room(String.t()) :: :ok | {:error, term()}
  def delete_room(room), do: adapter().delete_room(room)

  @spec list_rooms() :: {:ok, [String.t()]} | {:error, term()}
  def list_rooms, do: adapter().list_rooms()

  defp adapter do
    Application.get_env(:backend, :livekit_room_service, HTTPAdapter)
  end
end
