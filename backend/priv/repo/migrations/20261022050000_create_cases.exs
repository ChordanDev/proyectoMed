defmodule Backend.Repo.Migrations.CreateCases do
  use Ecto.Migration

  # Generated cases (issue #331). n8n inserts rows directly with only area,
  # theme and markdown; every other column has a database default, so the
  # insert contract in docs/case-format/README.md holds without Phoenix.
  def change do
    create table(:cases) do
      add :area, :text, null: false
      add :theme, :text, null: false
      add :markdown, :text, null: false
      add :status, :text, null: false, default: "pending"

      timestamps(type: :utc_datetime, default: fragment("timezone('utc', now())"))
    end

    # The human number doctors split work by. GENERATED ALWAYS: Postgres
    # assigns it in insertion order and refuses a value chosen by the caller.
    execute(
      "ALTER TABLE cases ADD COLUMN number bigint GENERATED ALWAYS AS IDENTITY NOT NULL",
      "ALTER TABLE cases DROP COLUMN number"
    )

    create unique_index(:cases, [:number])
    create index(:cases, [:status, :area])

    create constraint(:cases, :cases_status_check,
             check: "status IN ('pending', 'approved', 'disapproved')"
           )
  end
end
