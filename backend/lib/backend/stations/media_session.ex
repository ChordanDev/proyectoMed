defmodule Backend.Stations.MediaSession do
  @moduledoc """
  ETS-backed per-session sliding-window rate limiting for LiveKit token
  issuance.

  ponytail: state lives only in this process's ETS table. A restart resets
  every session's counters to zero, which only relaxes the limiter
  momentarily; it never lets a session bypass a cleanup or safety check.
  """

  use GenServer

  alias Backend.Stations.Conversation
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
  Triggers one orphan-room sweep immediately: lists LiveKit rooms, keeps only
  `station-session-*` rooms, and deletes each whose session is no longer
  active (not found, expired, or completed). Covers expiry, invalidation,
  and backend restarts. Exposed publicly because the periodic sweep is
  disabled in the test environment (see `config/test.exs`).
  """
  @spec sweep_orphans() :: :ok
  def sweep_orphans do
    GenServer.call(__MODULE__, :sweep_orphans, :infinity)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    if sweep_enabled?(), do: schedule_sweep()
    {:ok, %{}}
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

  def handle_call(:sweep_orphans, _from, state) do
    do_sweep()
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:scheduled_sweep, state) do
    do_sweep()
    schedule_sweep()
    {:noreply, state}
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
      RoomService.delete_room(room_name)
      :ets.delete(@table, session_id)
    end
  end

  defp active_session?(session_id) do
    match?({:ok, %{status: :active}}, Conversation.fetch(session_id))
  end

  defp schedule_sweep do
    Process.send_after(self(), :scheduled_sweep, sweep_interval_ms())
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
