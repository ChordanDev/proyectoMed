defmodule Backend.Repo.Migrations.CreateEducationalResults do
  use Ecto.Migration

  # The learner's results history (#338, ADR-014 #346): one row per finished
  # session that reached a graded Educational Result. `result` is the v2
  # Educational Result served at the end of the session: criteria with status,
  # points, recommendations and the cited learner phrases; never audio or the
  # full transcript. Rows cascade with their user, so deleting an account
  # deletes its history (#336). The station identity is copied on the row, so
  # deleting a case keeps the history (`station_version_id` becomes null).
  def change do
    create table(:educational_results) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :session_id, :text, null: false
      add :station_version_id, references(:station_versions, on_delete: :nilify_all)
      add :case_number, :bigint, null: false
      add :version_number, :integer, null: false
      add :station_slug, :text
      add :area, :text
      add :theme, :text
      add :display_title, :text
      add :finished_at, :utc_datetime_usec, null: false
      add :result, :map, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:educational_results, [:session_id])
    create index(:educational_results, [:user_id, :finished_at])
    create index(:educational_results, [:station_version_id])
  end
end
