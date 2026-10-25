defmodule Backend.Billing.Subscription do
  @moduledoc """
  A learner's RevenueCat customer and simulator entitlement (#339).

  `app_user_id` is a random UUIDv4 created on first use and sent to RevenueCat
  in every purchase link; it is never the email or the primary key. `status`
  is what the last applied webhook event set (`:none`, `:active`,
  `:cancelled` or `:expired`); access also requires `expires_at` in the
  future, so an unpaid Pix period lapses cleanly without an event.
  `last_event_at` is the `event_timestamp_ms` of the last applied event: older
  events are ignored. `refunded_at` is the time of the refund or chargeback
  event that ended access (#388), cleared by a later granting event.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "billing_subscriptions" do
    field :user_id, :id
    field :app_user_id, :string
    field :status, Ecto.Enum, values: [:none, :active, :cancelled, :expired], default: :none
    field :product_id, :string
    field :store, :string
    field :environment, :string
    field :expires_at, :utc_datetime_usec
    field :last_event_at, :utc_datetime_usec
    field :refunded_at, :utc_datetime_usec

    timestamps(type: :utc_datetime)
  end
end
