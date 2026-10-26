defmodule Backend.Repo.Migrations.AddLegalAcceptanceToUsers do
  use Ecto.Migration

  # Learner sign-up (#336): the version of the terms of use and of the privacy
  # policy the learner accepted, and when. Admins (provisioned by seeds) have none.
  def change do
    alter table(:users) do
      add :terms_version, :string
      add :terms_accepted_at, :utc_datetime
      add :privacy_version, :string
      add :privacy_accepted_at, :utc_datetime
    end
  end
end
