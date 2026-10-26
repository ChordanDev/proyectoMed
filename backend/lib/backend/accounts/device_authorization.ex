defmodule Backend.Accounts.DeviceAuthorization do
  @moduledoc """
  A pending device login (#337, RFC 8628 shape): the hashes of the device code
  the client polls with and of the user code the learner types in the browser,
  the polling interval and the expiry. `user_id` is set when the learner
  approves or denies it.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "device_authorizations" do
    field :device_code_hash, :binary
    field :user_code_hash, :binary
    field :status, Ecto.Enum, values: [:pending, :approved, :denied], default: :pending
    field :interval, :integer
    field :expires_at, :utc_datetime
    field :last_polled_at, :utc_datetime_usec
    belongs_to :user, Backend.Accounts.User

    timestamps(type: :utc_datetime)
  end
end
