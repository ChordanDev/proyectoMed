defmodule Backend.Stations.StationLoader do
  @moduledoc """
  Loads and holds the active validated Station Package for runtime consumers.

  The active station is read at boot from the `:active_station_id` application
  setting (`ACTIVE_STATION_ID`, see `config/runtime.exs`) and defaults to
  `chest-pain-initial-assessment`. The id must be a plain station directory
  name under `priv/stations`; a malformed id, an unknown id or an invalid
  package fails the boot with an error that names the id.
  """

  use GenServer

  alias Backend.Stations.StationPackage

  require Logger

  @default_station_id "chest-pain-initial-assessment"
  @station_id_format ~r/\A[a-z0-9-]+\z/

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

  @spec load_active() :: map()
  def load_active do
    station_id = active_station_id()

    case load_station(station_id) do
      {:ok, package} ->
        package

      {:error, message} ->
        Logger.error(message)
        raise RuntimeError, message
    end
  end

  # Production turns the file loader off (`:file_station_loader`, issue #334):
  # it then never starts, and stations come only from the database.
  @impl true
  @spec init(keyword()) :: {:ok, map()} | :ignore
  def init(_options) do
    if Application.get_env(:backend, :file_station_loader, true) do
      {:ok, load_active()}
    else
      :ignore
    end
  end

  @doc "Whether the file loader is running and serves an active station."
  @spec running?(GenServer.server()) :: boolean()
  def running?(server \\ __MODULE__), do: GenServer.whereis(server) != nil

  @impl true
  def handle_call(:active_package, _from, package), do: {:reply, package, package}

  def handle_call(:active_version, _from, %{"version" => version} = package),
    do: {:reply, version, package}

  defp active_station_id do
    case Application.get_env(:backend, :active_station_id) do
      id when id in [nil, ""] -> @default_station_id
      id -> id
    end
  end

  defp load_station(station_id) do
    if is_binary(station_id) and Regex.match?(@station_id_format, station_id) do
      station_id
      |> package_path()
      |> load_package(station_id)
    else
      {:error,
       "Identificador de estação ativa inválido: #{inspect(station_id)}. " <>
         "Use apenas letras minúsculas, números e hífens."}
    end
  end

  defp package_path(station_id) do
    Application.app_dir(:backend, "priv/stations/#{station_id}/package.json")
  end

  defp load_package(path, station_id) do
    prefix = "Falha ao carregar o pacote ativo da estação #{inspect(station_id)}"

    with {:ok, contents} <- File.read(path),
         {:ok, package} <- Jason.decode(contents),
         {:ok, package} <- StationPackage.validate(package) do
      {:ok, package}
    else
      {:error, :enoent} ->
        {:error, "#{prefix}: arquivo não encontrado."}

      {:error, %Jason.DecodeError{}} ->
        {:error, "#{prefix}: JSON inválido."}

      {:error, errors} when is_list(errors) ->
        Logger.error(
          "Falha ao validar o pacote da estação #{inspect(station_id)}: #{Enum.join(errors, "; ")}"
        )

        {:error,
         "Falha ao validar o pacote ativo da estação #{inspect(station_id)}: " <>
           "o conteúdo não atende ao contrato obrigatório."}

      {:error, _reason} ->
        {:error, "#{prefix}: não foi possível ler o arquivo."}
    end
  end
end

defmodule Backend.StationLoader do
  @moduledoc false
  defdelegate start_link(options \\ []), to: Backend.Stations.StationLoader

  defdelegate active_package(server \\ Backend.Stations.StationLoader),
    to: Backend.Stations.StationLoader

  defdelegate active_version(server \\ Backend.Stations.StationLoader),
    to: Backend.Stations.StationLoader

  defdelegate load_active(), to: Backend.Stations.StationLoader
end
