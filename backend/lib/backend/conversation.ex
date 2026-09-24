defmodule Backend.Conversation do
  @moduledoc """
  Holds active station conversations in an ephemeral, in-memory session store.

  Sessions are never persisted. A completed session is immutable: calling
  `complete/2` again returns the original completed session.
  """

  use GenServer

  @default_timeout_ms :timer.minutes(30)
  @default_purge_interval_ms :timer.minutes(1)

  @type session :: %{
          optional(:completed_at) => DateTime.t(),
          optional(:completion_reason) => term(),
          session_id: String.t(),
          station_id: String.t(),
          station_version: String.t(),
          audio_consent: boolean(),
          started_at: DateTime.t(),
          expires_at: DateTime.t(),
          messages: [message()],
          status: :active | :completed
        }

  @type message :: %{role: term(), modality: term(), text: String.t(), at: DateTime.t()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @doc """
  Starts a session. `:audio_consent` defaults to `false`: audio transcription is
  refused until the learner explicitly grants it.
  """
  @spec start(map() | keyword()) :: session()
  def start(attrs \\ %{}) do
    GenServer.call(__MODULE__, {:start, attrs})
  end

  @spec append_message(String.t(), %{role: term(), modality: term(), text: String.t()}) ::
          {:ok, session()} | {:error, :not_found | :expired | :completed}
  def append_message(session_id, message) do
    GenServer.call(__MODULE__, {:append_message, session_id, message})
  end

  @spec complete(String.t(), term()) :: {:ok, session()} | {:error, :not_found | :expired}
  def complete(session_id, reason) do
    GenServer.call(__MODULE__, {:complete, session_id, reason})
  end

  @spec fetch(String.t()) :: {:ok, session()} | {:error, :not_found | :expired}
  def fetch(session_id) do
    GenServer.call(__MODULE__, {:fetch, session_id})
  end

  @impl true
  def init(_options) do
    :ets.new(__MODULE__, [:named_table, :set, :private, read_concurrency: true])
    schedule_purge()
    {:ok, %{}}
  end

  @impl true
  def handle_call(:start, from, state) do
    handle_call({:start, %{}}, from, state)
  end

  def handle_call({:start, attrs}, _from, state) when is_map(attrs) or is_list(attrs) do
    attrs = if is_list(attrs), do: Enum.into(attrs, %{}), else: attrs
    now = DateTime.utc_now()

    station_id =
      Map.get(attrs, :station_id) || Map.get(attrs, "station_id") || default_station_id()

    station_version =
      Map.get(attrs, :station_version) || Map.get(attrs, "station_version") ||
        default_station_version()

    audio_consent =
      Map.get(attrs, :audio_consent, Map.get(attrs, "audio_consent", false)) == true

    session = %{
      session_id: session_id(),
      station_id: station_id,
      station_version: station_version,
      audio_consent: audio_consent,
      started_at: now,
      expires_at: DateTime.add(now, timeout_ms(), :millisecond),
      messages: [],
      status: :active
    }

    true = :ets.insert(__MODULE__, {session.session_id, session})
    {:reply, session, state}
  end

  def handle_call({:append_message, session_id, message}, _from, state) do
    case active_session(session_id) do
      {:ok, session} ->
        case session.status do
          :active ->
            message = Map.put(message, :at, DateTime.utc_now())
            session = %{session | messages: session.messages ++ [message]}
            true = :ets.insert(__MODULE__, {session_id, session})
            {:reply, {:ok, session}, state}

          :completed ->
            {:reply, {:error, :completed}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:complete, session_id, reason}, _from, state) do
    case active_session(session_id) do
      {:ok, session} ->
        case session.status do
          :active ->
            session =
              Map.merge(session, %{
                status: :completed,
                completed_at: DateTime.utc_now(),
                completion_reason: reason
              })

            true = :ets.insert(__MODULE__, {session_id, session})
            {:reply, {:ok, session}, state}

          :completed ->
            {:reply, {:ok, session}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:fetch, session_id}, _from, state) do
    {:reply, fetch_session(session_id), state}
  end

  @impl true
  def handle_info(:purge_expired, state) do
    now = DateTime.utc_now()

    for {session_id, session} <- :ets.tab2list(__MODULE__), expired?(session, now) do
      :ets.delete(__MODULE__, session_id)
    end

    schedule_purge()
    {:noreply, state}
  end

  defp active_session(session_id) do
    case fetch_session(session_id) do
      {:ok, session} -> {:ok, session}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_session(session_id) do
    case :ets.lookup(__MODULE__, session_id) do
      [] ->
        {:error, :not_found}

      [{^session_id, session}] ->
        if expired?(session, DateTime.utc_now()) do
          :ets.delete(__MODULE__, session_id)
          {:error, :expired}
        else
          {:ok, session}
        end
    end
  end

  defp expired?(session, now) do
    DateTime.compare(session.expires_at, now) != :gt
  end

  defp schedule_purge do
    Process.send_after(self(), :purge_expired, purge_interval_ms())
  end

  defp default_station_id do
    if Process.whereis(Backend.StationLoader) do
      Backend.StationLoader.active_package()["station_id"]
    else
      "chest-pain-initial-assessment"
    end
  rescue
    _ -> "chest-pain-initial-assessment"
  end

  defp default_station_version do
    if Process.whereis(Backend.StationLoader) do
      Backend.StationLoader.active_package()["version"]
    else
      "1.0.0"
    end
  rescue
    _ -> "1.0.0"
  end

  defp timeout_ms do
    Application.get_env(:backend, :conversation_timeout_ms, @default_timeout_ms)
  end

  defp purge_interval_ms do
    Application.get_env(:backend, :conversation_purge_interval_ms, @default_purge_interval_ms)
  end

  defp session_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
