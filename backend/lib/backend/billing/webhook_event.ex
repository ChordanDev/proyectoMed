defmodule Backend.Billing.WebhookEvent do
  @moduledoc """
  A processed RevenueCat webhook event id (#339). The unique `event_id` makes a
  redelivery a no-op; it is inserted in the same transaction as the event's
  effect, so a failed effect leaves no id behind and the retry still applies.
  `outcome` is `applied` or `ignored`.
  """

  use Ecto.Schema

  schema "billing_webhook_events" do
    field :event_id, :string
    field :type, :string
    field :outcome, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
