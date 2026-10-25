defmodule Backend.Accounts.DeviceRetiredRefreshToken do
  @moduledoc """
  The hash of a refresh token a device login (#337) rotated away. Presenting
  it again is a reuse and revokes that login (`Backend.Accounts.DeviceToken`).
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "device_retired_refresh_tokens" do
    field :refresh_token_hash, :binary
    belongs_to :device_token, Backend.Accounts.DeviceToken

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
