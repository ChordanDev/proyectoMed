defmodule Backend.Repo.Migrations.CreateStationVersions do
  use Ecto.Migration

  # Published Station versions (issue #333, spec #326).
  #
  # Approving a case records who approved it (`approved_by_id`, `approved_by_email`)
  # and when (`approved_at`) on the case, and publishes an immutable Station
  # version snapshot with the full parsed package.
  #
  # Deleting an admin account keeps their approval record (`approved_by_id`
  # becomes null, `approved_by_email` preserves their identity). Deleting a case
  # cascades to its station versions.
  def change do
    alter table(:cases) do
      add :approved_by_id, references(:users, on_delete: :nilify_all)
      add :approved_by_email, :text
      add :approved_at, :utc_datetime
    end

    create table(:station_versions) do
      add :case_id, references(:cases, on_delete: :delete_all), null: false
      add :case_revision_id, references(:case_revisions, on_delete: :nilify_all)
      add :version_number, :integer, null: false
      add :station_id, :text, null: false
      add :area, :text, null: false
      add :theme, :text, null: false
      add :markdown, :text, null: false
      add :package, :map, null: false
      add :approved_by_id, references(:users, on_delete: :nilify_all)
      add :approved_by_email, :text, null: false
      add :approved_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:station_versions, [:case_id, :version_number])
    create index(:station_versions, [:station_id])
    create index(:station_versions, [:case_revision_id])
    create index(:cases, [:approved_by_id])
    create index(:station_versions, [:approved_by_id])
  end
end
