defmodule Backend.Repo.Migrations.CreateSessionUsages do
  use Ecto.Migration

  # One content-free row per finished station session (issue #342): provider
  # usage counts and the estimated cost. No user id and no conversation content
  # (ADR-001, ADR-009); the session id is the ephemeral station session's id.
  def change do
    create table(:session_usages, primary_key: false) do
      add :session_id, :string, primary_key: true
      add :station_id, :string, null: false
      add :station_version, :string, null: false
      add :station_version_id, :bigint
      add :started_at, :utc_datetime_usec, null: false
      add :finished_at, :utc_datetime_usec, null: false
      add :claude_usage, :map, null: false, default: %{}
      add :jev_calls, :integer, null: false, default: 0
      add :deepgram_audio_seconds, :float, null: false, default: 0.0
      add :elevenlabs_characters, :integer, null: false, default: 0
      add :livekit_participant_minutes, :float, null: false, default: 0.0
      add :cost_by_provider, :map, null: false, default: %{}
      add :unpriced_models, {:array, :string}, null: false, default: []
      add :estimated_cost_usd, :decimal, precision: 12, scale: 6, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:session_usages, [:finished_at])
    create index(:session_usages, [:station_id, :finished_at])
  end
end
