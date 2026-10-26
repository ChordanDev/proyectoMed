defmodule Backend.Release do
  @moduledoc """
  Tasks run inside the production release (#344), where Mix is not available.

  `bin/backend eval` starts a fresh VM without the application, so the eval
  tasks start only what they need:

      bin/backend eval "Backend.Release.migrate()"
      bin/backend eval "Backend.Release.rollback(Backend.Repo, 20261025190000)"
      ADMIN_EMAIL=... ADMIN_PASSWORD=... bin/backend eval "Backend.Release.create_admin()"

  The `rel/overlays/bin` scripts (`migrate`, `create_admin`) wrap them. See
  `docs/operations/deploy.md`.
  """

  alias Backend.Accounts
  alias Backend.Stations

  @app :backend

  @doc "Runs every pending migration of every repo."
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @doc "Rolls `repo` back to `version` (a migration timestamp)."
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
    :ok
  end

  @doc """
  Provisions an admin from `ADMIN_EMAIL` and `ADMIN_PASSWORD` (issue #331) and
  prints the outcome by email. Idempotent: an existing account with that email
  is left unchanged. The password is never printed.
  """
  def create_admin(env \\ System.get_env()) do
    load_app()

    result =
      case Ecto.Migrator.with_repo(Backend.Repo, fn _repo -> provision_admin(env) end) do
        {:ok, result, _apps} -> result
        {:error, reason} -> {:error, {:repo, reason}}
      end

    report_admin(result, String.trim(env["ADMIN_EMAIL"] || ""))
    result
  end

  @doc """
  Creates the admin `env` names (`ADMIN_EMAIL`, `ADMIN_PASSWORD`), with the
  repo already started: `{:ok, :created}`, `{:ok, :exists}` when the email is
  taken, `{:error, :missing_env}` or `{:error, {:invalid, errors}}`.
  """
  def provision_admin(env) do
    email = String.trim(env["ADMIN_EMAIL"] || "")
    password = env["ADMIN_PASSWORD"] || ""

    cond do
      email == "" or password == "" ->
        {:error, :missing_env}

      Accounts.get_user_by_email(email) ->
        {:ok, :exists}

      true ->
        case Accounts.create_admin(%{email: email, password: password}) do
          {:ok, _admin} ->
            {:ok, :created}

          {:error, changeset} ->
            {:error, {:invalid, Ecto.Changeset.traverse_errors(changeset, &error_message/1)}}
        end
    end
  end

  # The message template only, never the interpolated values: a password
  # error must not echo the password.
  defp error_message({message, _opts}), do: message

  defp report_admin({:ok, :created}, email), do: IO.puts("admin #{email} created")

  defp report_admin({:ok, :exists}, email),
    do: IO.puts("admin #{email} already exists, left unchanged")

  defp report_admin({:error, :missing_env}, _email),
    do: IO.puts("ADMIN_EMAIL and ADMIN_PASSWORD must both be set; no admin created")

  defp report_admin({:error, {:invalid, errors}}, email),
    do: IO.puts("admin #{email} not created: #{inspect(errors)}")

  defp report_admin({:error, {:repo, reason}}, _email),
    do: IO.puts("no admin created: the database is unavailable (#{inspect(reason)})")

  @doc """
  Switches the running node to "no new sessions" for a deploy (#344) and
  prints its state. Runs inside the running node through `bin/drain start`
  (`bin/backend rpc`), never through `eval`.
  """
  def drain do
    :ok = Stations.start_draining()
    print_drain_status()
  end

  @doc "Admits new sessions again (`bin/drain stop`) and prints the node state."
  def resume do
    :ok = Stations.resume_sessions()
    print_drain_status()
  end

  @doc """
  Prints `draining=<true|false> active_sessions=<n>` for the running node
  (`bin/drain status`); `rel/deploy.sh` parses this line.
  """
  def drain_status, do: print_drain_status()

  defp print_drain_status do
    %{draining: draining, active_sessions: active} = Stations.drain_status()
    IO.puts("draining=#{draining} active_sessions=#{active}")
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    # TLS to Neon needs :ssl before the repo connects.
    {:ok, _apps} = Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
