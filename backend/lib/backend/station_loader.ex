defmodule Backend.StationLoader do
  @moduledoc """
  Loads and holds the active validated Station Package for runtime consumers.
  """

  use GenServer

  alias Backend.StationPackage

  @type validation_error :: {:invalid_station_package, Path.t(), [String.t()]}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options \\ []) do
    {name, options} = Keyword.pop(options, :name, __MODULE__)
    GenServer.start_link(__MODULE__, options, name: name)
  end

  @spec active_package(GenServer.server()) :: map()
  def active_package(server \\ __MODULE__) do
    GenServer.call(server, :active_package)
  end

  @spec active_version(GenServer.server()) :: String.t()
  def active_version(server \\ __MODULE__) do
    GenServer.call(server, :active_version)
  end

  @impl true
  @spec init(keyword()) :: {:ok, map()} | {:stop, validation_error() | term()}
  def init(options) do
    path = Keyword.get(options, :package_path, default_package_path())

    with {:ok, contents} <- File.read(path),
         {:ok, package} <- Jason.decode(contents),
         {:ok, package} <- StationPackage.validate(package) do
      {:ok, package}
    else
      {:error, errors} when is_list(errors) -> {:stop, {:invalid_station_package, path, errors}}
      {:error, reason} -> {:stop, {:station_package_load_failed, path, reason}}
    end
  end

  @impl true
  def handle_call(:active_package, _from, package), do: {:reply, package, package}

  def handle_call(:active_version, _from, %{"version" => version} = package),
    do: {:reply, version, package}

  defp default_package_path do
    Application.get_env(
      :backend,
      :station_package_path,
      Application.app_dir(:backend, "priv/stations/fixtures/valid-package.json")
    )
  end
end
