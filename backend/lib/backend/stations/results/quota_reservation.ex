defmodule Backend.Stations.Results.QuotaReservation do
  @moduledoc """
  One slot of a learner's daily quota held by a session in flight (#340),
  from its start until it is graded or `expires_at`, the session's expiry.
  """

  use Ecto.Schema

  schema "session_quota_reservations" do
    belongs_to :user, Backend.Accounts.User
    field :session_id, :string
    field :expires_at, :utc_datetime_usec

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
