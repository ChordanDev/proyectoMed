defmodule Backend.Accounts.DeviceToken do
  @moduledoc """
  One device login of a learner (#337): the hashes of its current access and
  refresh tokens with their expiries. A refresh rotates both and keeps the
  previous refresh token's hash, so reusing a rotated refresh token is
  detected and revokes the login.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "device_tokens" do
    field :access_token_hash, :binary
    field :access_expires_at, :utc_datetime
    field :refresh_token_hash, :binary
    field :refresh_expires_at, :utc_datetime
    field :previous_refresh_token_hash, :binary
    belongs_to :user, Backend.Accounts.User

    timestamps(type: :utc_datetime)
  end
end
