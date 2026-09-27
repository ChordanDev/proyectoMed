defmodule Backend.Stations.MediaSession do
  @moduledoc """
  ETS-backed per-session sliding-window rate limiting for LiveKit token
  issuance.

  ponytail: state lives only in this process's ETS table. A restart resets
  every session's counters to zero, which only relaxes the limiter
  momentarily; it never lets a session bypass a cleanup or safety check.
  """

  use GenServer

  @table __MODULE__
  @default_max_tokens 5
  @default_window_ms :timer.seconds(60)

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

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
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
