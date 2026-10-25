defmodule Backend.Repo.Migrations.CreateBillingTables do
  use Ecto.Migration

  # RevenueCat entitlements (#339). One subscription row per learner holds the
  # random UUIDv4 app_user_id sent to RevenueCat (never the email) and the
  # simulator entitlement as the webhook last set it. Each processed webhook
  # event id is recorded under a unique index, in the same transaction as its
  # effect, so a redelivery is a no-op. Rows cascade with the user.
  def change do
    create table(:billing_subscriptions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :app_user_id, :string, null: false
      add :status, :string, null: false, default: "none"
      add :product_id, :string
      add :store, :string
      add :environment, :string
      add :expires_at, :utc_datetime_usec
      add :last_event_at, :utc_datetime_usec

      timestamps(type: :utc_datetime)
    end

    create unique_index(:billing_subscriptions, [:user_id])
    create unique_index(:billing_subscriptions, [:app_user_id])

    create table(:billing_webhook_events) do
      add :event_id, :string, null: false
      add :type, :string, null: false
      add :outcome, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:billing_webhook_events, [:event_id])
  end
end
