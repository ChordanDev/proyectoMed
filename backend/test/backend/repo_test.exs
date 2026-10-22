defmodule Backend.RepoTest do
  @moduledoc """
  The Repo reaches the test database through the SQL sandbox (issue #329).
  """

  use Backend.DataCase, async: true

  test "queries the Postgres test database" do
    assert %{rows: [[1]]} = Repo.query!("SELECT 1")
    assert %{rows: [[database]]} = Repo.query!("SELECT current_database()")
    assert String.starts_with?(database, "backend_test")
  end

  test "runs every test inside the SQL sandbox" do
    assert Repo.config()[:pool] == Ecto.Adapters.SQL.Sandbox
  end

  test "reads migrations from priv/repo/migrations" do
    assert Ecto.Migrator.migrations_path(Repo) ==
             Application.app_dir(:backend, "priv/repo/migrations")
  end

  # Holds trivially until the first migration lands; from then on it guards
  # that the `test` alias migrated the test database.
  test "leaves no migration pending in the test database" do
    refute Enum.any?(Ecto.Migrator.migrations(Repo), fn {status, _version, _name} ->
             status == :down
           end)
  end
end
