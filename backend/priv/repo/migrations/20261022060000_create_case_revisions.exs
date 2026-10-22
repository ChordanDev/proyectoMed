defmodule Backend.Repo.Migrations.CreateCaseRevisions do
  use Ecto.Migration

  # Admin edits (issue #332). `lock_version` is the optimistic lock of a case:
  # every save checks the version the admin loaded and increments it, so a
  # save over a newer version is refused instead of overwriting it. Its
  # default keeps the n8n insert contract (area, theme, markdown only).
  #
  # `case_revisions` keeps every replaced Markdown with the admin whose save
  # replaced it. `editor_email` is a snapshot, so a revision still names its
  # editor after the account is deleted (`editor_id` becomes null).
  def change do
    alter table(:cases) do
      add :lock_version, :integer, null: false, default: 1
    end

    create table(:case_revisions) do
      add :case_id, references(:cases, on_delete: :delete_all), null: false
      add :markdown, :text, null: false
      add :lock_version, :integer, null: false
      add :editor_id, references(:users, on_delete: :nilify_all)
      add :editor_email, :text, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:case_revisions, [:case_id, :lock_version])
  end
end
