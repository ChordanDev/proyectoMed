defmodule Backend.Stations.LiveKit.RoomService do
  @moduledoc """
  Behaviour for the LiveKit RoomService external seam: deleting a room on
  session completion/discard, listing rooms for the orphan sweep, and sending
  data into a room, such as an approved typed reply for the voice worker to
  speak (#325).

  The default adapter (`Backend.Stations.LiveKit.RoomService.HTTPAdapter`)
  speaks Twirp over `Req`. Override with the `:backend, :livekit_room_service`
  application env, mirroring how `Backend.Stations.StationAI` adapters are
  selected.
  """

  @callback delete_room(room :: String.t()) :: :ok | {:error, term()}
  @callback list_rooms() :: {:ok, [String.t()]} | {:error, term()}

  @typedoc """
  `:topic` names the data topic; `:destination_identities` limits delivery to
  those participants (every participant when absent).
  """
  @type send_option :: {:topic, String.t()} | {:destination_identities, [String.t()]}

  @callback send_data(room :: String.t(), data :: binary(), [send_option()]) ::
              :ok | {:error, term()}

  alias Backend.Stations.LiveKit.RoomService.HTTPAdapter

  @spec delete_room(String.t()) :: :ok | {:error, term()}
  def delete_room(room), do: adapter().delete_room(room)

  @spec list_rooms() :: {:ok, [String.t()]} | {:error, term()}
  def list_rooms, do: adapter().list_rooms()

  @doc "Sends `data` reliably into `room`; see `t:send_option/0`."
  @spec send_data(String.t(), binary(), [send_option()]) :: :ok | {:error, term()}
  def send_data(room, data, opts), do: adapter().send_data(room, data, opts)

  defp adapter do
    Application.get_env(:backend, :livekit_room_service, HTTPAdapter)
  end
end
