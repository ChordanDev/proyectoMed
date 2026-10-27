defmodule Backend.Repo.Migrations.AddRefundedAtToBillingSubscriptions do
  use Ecto.Migration

  # A refund or chargeback ends simulator access at the event time (#388).
  # `refunded_at` is the time of the refund event that ended access, so the
  # account page can say why; a later purchase clears it. Nullable, no backfill.
  def change do
    alter table(:billing_subscriptions) do
      add :refunded_at, :utc_datetime_usec
    end
  end
end
