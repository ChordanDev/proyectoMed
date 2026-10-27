defmodule Backend.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BackendWeb.Telemetry,
      Backend.Repo,
      # Inside a release, run pending migrations before serving requests (#329).
      {Ecto.Migrator,
       repos: Application.fetch_env!(:backend, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:backend, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Backend.PubSub},
      Backend.Stations.StationLoader,
      Backend.Stations.Conversation,
      Backend.Stations.MediaSession,
      # In-memory counters of the auth and device-login rate limits (#380).
      BackendWeb.RateLimit,
      # Start a worker by calling: Backend.Worker.start_link(arg)
      # {Backend.Worker, arg},
      # Start to serve requests, typically the last entry
      BackendWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Backend.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Mix runs migrations itself (`mix ecto.migrate`, and the `test` alias), so
  # only a release, which sets `RELEASE_NAME`, migrates on boot.
  @doc false
  def skip_migrations? do
    System.get_env("RELEASE_NAME") == nil
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BackendWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
