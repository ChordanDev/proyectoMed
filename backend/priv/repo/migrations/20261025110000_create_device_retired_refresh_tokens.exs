defmodule Backend.Repo.Migrations.CreateDeviceRetiredRefreshTokens do
  use Ecto.Migration

  # Every refresh token a device login rotated away (#337 review): presenting
  # any of them again revokes that login, however many rotations ago it was
  # retired. Only SHA-256 hashes are stored; rows cascade with their login.
  def change do
    create table(:device_retired_refresh_tokens) do
      add :device_token_id, references(:device_tokens, on_delete: :delete_all), null: false
      add :refresh_token_hash, :binary, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:device_retired_refresh_tokens, [:refresh_token_hash])
    create index(:device_retired_refresh_tokens, [:device_token_id])

    drop index(:device_tokens, [:previous_refresh_token_hash])

    alter table(:device_tokens) do
      remove :previous_refresh_token_hash, :binary
    end
  end
end
