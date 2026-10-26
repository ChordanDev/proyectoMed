defmodule Backend.Stations.MediaSession do
  @moduledoc """
  ETS-backed per-session sliding-window rate limiting for LiveKit token
  issuance.

  ponytail: state lives only in this process's ETS table. A restart resets
  every session's counters to zero, which only relaxes the limiter
  momentarily; it never lets a session bypass a cleanup or safety check.
  """

  use GenServer
  require Logger

  alias Backend.Stations.Conversation
  alias Backend.Stations.ExamMode
  alias Backend.Stations.LiveKit
  alias Backend.Stations.LiveKit.RoomService

  @table __MODULE__
  @room_prefix "station-session-"
  @default_max_tokens 5
  @default_window_ms :timer.seconds(60)
  @default_sweep_interval_ms :timer.seconds(60)

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records one token-issuance attempt for `session_id` and enforces the
  sliding-window limit. Returns `:ok` when the attempt is allowed, or
  `{:error, :rate_limited}` when the session already used its window.
  """
  @spec check_rate_limit(String.t()) :: :ok | {:error, :rate_limited}
  def check_rate_limit(session_id) do
    GenServer.call(__MODULE__, {:check_rate_limit, session_id})
  end

  @doc """
  Clears a session's rate-limit window, e.g. once its room has been cleaned
  up and the session id can no longer be reused.
  """
  @spec clear_rate_limit(String.t()) :: :ok
  def clear_rate_limit(session_id) do
    GenServer.call(__MODULE__, {:clear_rate_limit, session_id})
  end

  @doc """
  Triggers one orphan-room sweep immediately, in the calling process: lists
  LiveKit rooms, keeps only `station-session-*` rooms, and deletes each whose
  session is no longer active (not found, expired, or completed). Covers
  expiry, invalidation, and backend restarts. Runs outside the GenServer (the
  ETS table is public) so it never contends with `check_rate_limit/1` or
  `clear_rate_limit/1`. Exposed publicly because the periodic sweep is
  disabled in the test environment (see `config/test.exs`).
  """
  @spec sweep_orphans() :: :ok
  def sweep_orphans do
    do_sweep()
  end

  @doc """
  Removes ETS rows whose newest recorded timestamp already fell outside the
  rate-limit window. Runs on every periodic tick regardless of whether
  LiveKit is configured or the orphan sweep is enabled, so a session that
  received a token and never joined cannot leak a row forever. Exposed
  publicly so tests can trigger it deterministically without waiting for the
  tick interval.
  """
  @spec prune_stale_rate_limits() :: :ok
  def prune_stale_rate_limits do
    prune_stale_entries()
    :ok
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    # This process also owns the exam mode table (#364).
    :ok = ExamMode.create_table()
    schedule_tick()
    {:ok, %{sweeping?: false}}
  end

  @impl true
  def handle_call({:check_rate_limit, session_id}, _from, state) do
    now = System.monotonic_time(:millisecond)
    window = window_ms()

    fresh_timestamps =
      session_id
      |> lookup_timestamps()
      |> Enum.filter(fn timestamp -> now - timestamp < window end)

    if length(fresh_timestamps) >= max_tokens() do
      :ets.insert(@table, {session_id, fresh_timestamps})
      {:reply, {:error, :rate_limited}, state}
    else
      :ets.insert(@table, {session_id, [now | fresh_timestamps]})
      {:reply, :ok, state}
    end
  end

  def handle_call({:clear_rate_limit, session_id}, _from, state) do
    :ets.delete(@table, session_id)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    prune_stale_entries()
    state = maybe_start_sweep(state)
    schedule_tick()
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, %{state | sweeping?: false}}
  end

  # The scheduled sweep's HTTP work runs in its own unlinked task so a slow
  # LiveKit never blocks this GenServer's mailbox (and therefore
  # check_rate_limit/1, clear_rate_limit/1). `sweeping?` prevents overlapping
  # sweeps if one tick's task outlives the next tick.
  defp maybe_start_sweep(%{sweeping?: true} = state), do: state

  defp maybe_start_sweep(state) do
    if sweep_enabled?() and LiveKit.configured?() do
      {:ok, pid} = Task.start(fn -> do_sweep() end)
      Process.monitor(pid)
      %{state | sweeping?: true}
    else
      state
    end
  end

  defp do_sweep do
    if LiveKit.configured?() do
      case RoomService.list_rooms() do
        {:ok, rooms} ->
          rooms
          |> Enum.filter(&String.starts_with?(&1, @room_prefix))
          |> Enum.each(&sweep_room/1)

        {:error, _reason} ->
          :ok
      end
    end
  end

  defp sweep_room(room_name) do
    session_id = String.replace_prefix(room_name, @room_prefix, "")

    unless active_session?(session_id) do
      case RoomService.delete_room(room_name) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "LiveKit orphan room cleanup failed for session #{session_id}: #{inspect(reason)}"
          )
      end

      :ets.delete(@table, session_id)
    end
  end

  defp active_session?(session_id) do
    match?({:ok, %{status: :active}}, Conversation.fetch(session_id))
  end

  defp prune_stale_entries do
    now = System.monotonic_time(:millisecond)
    window = window_ms()

    @table
    |> :ets.tab2list()
    |> Enum.each(fn {session_id, timestamps} ->
      newest = Enum.max(timestamps, fn -> now - window end)
      if now - newest >= window, do: :ets.delete(@table, session_id)
    end)
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, sweep_interval_ms())
  end

  defp sweep_enabled? do
    Application.get_env(:backend, :livekit_orphan_sweep_enabled, true)
  end

  defp sweep_interval_ms do
    Application.get_env(:backend, :livekit_sweep_interval_ms, @default_sweep_interval_ms)
  end

  defp lookup_timestamps(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, timestamps}] -> timestamps
      [] -> []
    end
  end

  defp max_tokens do
    Application.get_env(:backend, :livekit_rate_limit_max, @default_max_tokens)
  end

  defp window_ms do
    Application.get_env(:backend, :livekit_rate_limit_window_ms, @default_window_ms)
  end
end
