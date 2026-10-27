defmodule Backend.Repo.Migrations.CreateDeviceLoginTables do
  use Ecto.Migration

  # Device login of the Unreal client (#337, RFC 8628 shape). Only SHA-256
  # hashes of codes and tokens are stored; rows cascade with their user so
  # deleting an account revokes its device logins (#336).
  def change do
    create table(:device_authorizations) do
      add :device_code_hash, :binary, null: false
      add :user_code_hash, :binary, null: false
      add :status, :string, null: false, default: "pending"
      add :interval, :integer, null: false
      add :expires_at, :utc_datetime, null: false
      add :last_polled_at, :utc_datetime_usec
      add :user_id, references(:users, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:device_authorizations, [:device_code_hash])
    create unique_index(:device_authorizations, [:user_code_hash])
    create index(:device_authorizations, [:expires_at])

    create constraint(:device_authorizations, :device_authorizations_status_check,
             check: "status IN ('pending', 'approved', 'denied')"
           )

    create table(:device_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :access_token_hash, :binary, null: false
      add :access_expires_at, :utc_datetime, null: false
      add :refresh_token_hash, :binary, null: false
      add :refresh_expires_at, :utc_datetime, null: false
      add :previous_refresh_token_hash, :binary

      timestamps(type: :utc_datetime)
    end

    create index(:device_tokens, [:user_id])
    create unique_index(:device_tokens, [:access_token_hash])
    create unique_index(:device_tokens, [:refresh_token_hash])
    create index(:device_tokens, [:previous_refresh_token_hash])
  end
end
