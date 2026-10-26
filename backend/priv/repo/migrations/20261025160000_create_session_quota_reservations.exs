defmodule Backend.Repo.Migrations.CreateSessionQuotaReservations do
  use Ecto.Migration

  # Daily quota reservations (#340). Starting a session reserves one slot of
  # the learner's daily quota until the session is graded (its stored
  # Educational Result then counts) or expires (an abandoned or technically
  # failed session releases it). Rows cascade with the user.
  def change do
    create table(:session_quota_reservations) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :session_id, :string, null: false
      add :expires_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:session_quota_reservations, [:session_id])
    create index(:session_quota_reservations, [:user_id, :expires_at])
  end
end
