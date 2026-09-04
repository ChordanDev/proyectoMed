defmodule Backend.StationLoader do
  @moduledoc """
  Loads and holds the active validated Station Package for runtime consumers.
  """

  use GenServer

  alias Backend.StationPackage

  require Logger

  @active_station_id "chest-pain-initial-assessment"

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
  @spec init(keyword()) :: {:ok, map()} | {:stop, {:station_package_load_failed, String.t()}}
  def init(options) do
    path = Keyword.get(options, :package_path, default_package_path())

    case load_package(path) do
      {:ok, package} ->
        {:ok, package}

      {:error, message} ->
        Logger.error(message)
        {:stop, {:station_package_load_failed, message}}
    end
  end

  @impl true
  def handle_call(:active_package, _from, package), do: {:reply, package, package}

  def handle_call(:active_version, _from, %{"version" => version} = package),
    do: {:reply, version, package}

  defp default_package_path do
    Application.app_dir(:backend, "priv/stations/#{@active_station_id}/package.json")
  end

  defp load_package(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, package} <- Jason.decode(contents),
         {:ok, package} <- StationPackage.validate(package) do
      {:ok, package}
    else
      {:error, :enoent} ->
        {:error, "Falha ao carregar o pacote da estação em #{path}: arquivo não encontrado."}

      {:error, %Jason.DecodeError{}} ->
        {:error, "Falha ao carregar o pacote da estação em #{path}: JSON inválido."}

      {:error, errors} when is_list(errors) ->
        {:error,
         "Falha ao validar o pacote da estação em #{path}: o conteúdo não atende ao contrato obrigatório."}

      {:error, _reason} ->
        {:error,
         "Falha ao carregar o pacote da estação em #{path}: não foi possível ler o arquivo."}
    end
  end
end
