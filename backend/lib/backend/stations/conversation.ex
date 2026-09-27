defmodule Backend.Stations.Conversation do
  @moduledoc """
  Holds active station conversations in an ephemeral, in-memory session store.

  Sessions are never persisted. A completed session is immutable: calling
  `complete/2` again returns the original completed session.
  """

  use GenServer

  @default_timeout_ms :timer.minutes(30)
  @default_purge_interval_ms :timer.minutes(1)
  @default_station_duration_ms :timer.minutes(10)
  @default_turn_grace_ms :timer.seconds(30)

  @type session :: %{
          optional(:completed_at) => DateTime.t(),
          optional(:completion_reason) => term(),
          session_id: String.t(),
          station_id: String.t(),
          station_version: String.t(),
          audio_consent: boolean(),
          started_at: DateTime.t(),
          expires_at: DateTime.t(),
          deadline_at: DateTime.t(),
          messages: [message()],
          released_impressos: [String.t()],
          impresso_requests: [impresso_request_event()],
          status: :active | :completed
        }

  @type message :: %{role: term(), modality: term(), text: String.t(), at: DateTime.t()}

  @type impresso_request_event :: %{
          request_id: String.t(),
          station_id: String.t(),
          station_version: String.t(),
          order: pos_integer(),
          text: String.t(),
          matched_ids: [String.t()],
          decision: :released | :already_released | :unavailable,
          released_ids: [String.t()],
          at: DateTime.t()
        }

  @type turn_token :: reference()

  @typep turn :: %{
           token: turn_token(),
           learner_message: message(),
           waiters: [GenServer.from()],
           first_reason: term() | nil,
           grace_ref: reference() | nil
         }

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
    GenServer.call(__MODULE__, {:complete, session_id, reason}, call_timeout_ms())
  end

  @doc """
  Begins a turn: accepts a learner message if the session is active and the
  authoritative deadline has not passed, and returns a unique token identifying
  this in-flight turn. While a turn is pending, session completion (manual or
  timer) is deferred until `resolve_turn/3` settles it or the bounded grace
  period elapses.
  """
  @spec begin_turn(String.t(), map()) ::
          {:ok, session(), turn_token()}
          | {:error, :not_found | :expired | :completed | :station_time_elapsed}
  def begin_turn(session_id, message) do
    GenServer.call(__MODULE__, {:begin_turn, session_id, message})
  end

  @doc """
  Resolves a pending turn identified by `token`, either appending the patient
  reply (`{:ok, message}`) or rolling back the learner message (`:rollback`).

  Returns `{:error, :station_time_elapsed}` if the token is no longer pending
  (already rolled back by the grace timer, or unknown/stale).
  """
  @spec resolve_turn(String.t(), turn_token(), {:ok, map()} | :rollback) ::
          {:ok, session()} | {:error, :station_time_elapsed | :not_found | :expired}
  def resolve_turn(session_id, token, resolution) do
    GenServer.call(__MODULE__, {:resolve_turn, session_id, token, resolution}, call_timeout_ms())
  end

  @spec fetch(String.t()) :: {:ok, session()} | {:error, :not_found | :expired}
  def fetch(session_id) do
    GenServer.call(__MODULE__, {:fetch, session_id})
  end

  @doc """
  Atomically records an Impresso request against an active session.

  `matched_ids` are the authored ids (in authored order) that the caller's
  keyword matcher found for `text`. This call decides the release outcome
  against the session's current `released_impressos`, appends the resulting
  event, and updates `released_impressos` — all within a single GenServer
  call, so concurrent requests for the same session never race.

  A repeated `request_id` is idempotent: it returns the originally stored
  event and does not append a new one or change `released_impressos`.
  """
  @spec record_impresso_request(String.t(), String.t(), [String.t()], String.t()) ::
          {:ok, %{event: impresso_request_event(), session: session()}}
          | {:error, :not_found | :expired | :completed}
  def record_impresso_request(session_id, request_id, matched_ids, text) do
    GenServer.call(
      __MODULE__,
      {:record_impresso_request, session_id, request_id, matched_ids, text}
    )
  end

  @doc """
  Pops the last message from an active session if it matches the expected message.
  Returns `{:ok, session}` on success, or `{:error, reason}` if the session is not found,
  expired, completed, or the last message does not match.
  """
  @spec pop_last_message(String.t(), map() | nil) ::
          {:ok, session()} | {:error, :not_found | :expired | :completed | :no_match}
  def pop_last_message(session_id, expected_message \\ nil) do
    GenServer.call(__MODULE__, {:pop_last_message, session_id, expected_message})
  end

  @doc """
  Idempotently discards a session from in-memory storage.
  Returns `:ok` whether the session existed or not.
  """
  @spec discard(String.t()) :: :ok
  def discard(session_id) do
    GenServer.call(__MODULE__, {:discard, session_id})
  end

  @impl true
  def init(_options) do
    :ets.new(__MODULE__, [:named_table, :set, :public, read_concurrency: true])
    schedule_purge()
    {:ok, %{turns: %{}}}
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
      deadline_at: DateTime.add(now, station_duration_ms(), :millisecond),
      messages: [],
      released_impressos: [],
      impresso_requests: [],
      status: :active
    }

    true = :ets.insert(__MODULE__, {session.session_id, session})
    Process.send_after(self(), {:deadline, session.session_id}, station_duration_ms())
    {:reply, session, state}
  end

  def handle_call({:begin_turn, session_id, message}, _from, state) do
    case active_session(session_id) do
      {:ok, %{status: :completed, completion_reason: :timer}} ->
        {:reply, {:error, :station_time_elapsed}, state}

      {:ok, %{status: :completed}} ->
        {:reply, {:error, :completed}, state}

      {:ok, %{status: :active} = session} ->
        now = DateTime.utc_now()

        if DateTime.compare(now, session.deadline_at) != :lt do
          {:reply, {:error, :station_time_elapsed}, state}
        else
          message = Map.put(message, :at, now)
          updated = %{session | messages: session.messages ++ [message]}
          true = :ets.insert(__MODULE__, {session_id, updated})

          token = make_ref()

          turn = %{
            token: token,
            learner_message: message,
            waiters: [],
            first_reason: nil,
            grace_ref: nil
          }

          state = put_in(state, [:turns, session_id], turn)
          {:reply, {:ok, updated, token}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:resolve_turn, session_id, token, resolution}, _from, state) do
    case get_in(state, [:turns, session_id]) do
      %{token: ^token} = turn ->
        if turn.grace_ref, do: Process.cancel_timer(turn.grace_ref)

        case apply_resolution(session_id, turn, resolution) do
          {:ok, session} ->
            state = %{state | turns: Map.delete(state.turns, session_id)}

            {final_session, state} =
              finalize_deferred_completion(session_id, turn, session, state)

            {:reply, {:ok, final_session}, state}

          {:error, reason} ->
            state = %{state | turns: Map.delete(state.turns, session_id)}
            {:reply, {:error, reason}, state}
        end

      _ ->
        {:reply, {:error, :station_time_elapsed}, state}
    end
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

  def handle_call({:complete, session_id, reason}, from, state) do
    case get_in(state, [:turns, session_id]) do
      %{} = turn ->
        turn = %{turn | waiters: [from | turn.waiters]}
        turn = if turn.first_reason, do: turn, else: %{turn | first_reason: reason}
        turn = ensure_grace_timer(session_id, turn)
        state = put_in(state, [:turns, session_id], turn)
        {:noreply, state}

      nil ->
        {:reply, complete_now(session_id, reason), state}
    end
  end

  def handle_call({:fetch, session_id}, _from, state) do
    {:reply, fetch_session(session_id), state}
  end

  def handle_call({:pop_last_message, session_id, expected_message}, _from, state) do
    case active_session(session_id) do
      {:ok, %{status: :active} = session} ->
        {:reply, do_pop_last_message(session, expected_message), state}

      {:ok, %{status: :completed}} ->
        {:reply, {:error, :completed}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(
        {:record_impresso_request, session_id, request_id, matched_ids, text},
        _from,
        state
      ) do
    case active_session(session_id) do
      {:ok, %{status: :active} = session} ->
        {:reply, do_record_impresso_request(session, request_id, matched_ids, text), state}

      {:ok, %{status: :completed}} ->
        {:reply, {:error, :completed}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:discard, session_id}, _from, state) do
    :ets.delete(__MODULE__, session_id)
    {:reply, :ok, state}
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

  def handle_info({:deadline, session_id}, state) do
    case get_in(state, [:turns, session_id]) do
      %{} = turn ->
        turn = if turn.first_reason, do: turn, else: %{turn | first_reason: :timer}
        turn = ensure_grace_timer(session_id, turn)
        state = put_in(state, [:turns, session_id], turn)
        {:noreply, state}

      nil ->
        _ = complete_now(session_id, :timer)
        {:noreply, state}
    end
  end

  def handle_info({:grace_expired, session_id, token}, state) do
    case get_in(state, [:turns, session_id]) do
      %{token: ^token} = turn ->
        rollback_pending_message(session_id, turn)
        reason = turn.first_reason || :timer
        reply_waiters(complete_now(session_id, reason), turn.waiters)
        state = %{state | turns: Map.delete(state.turns, session_id)}
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
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
    loader =
      Process.whereis(Backend.Stations.StationLoader) || Process.whereis(Backend.StationLoader)

    if loader do
      Backend.Stations.StationLoader.active_package(loader)["station_id"]
    else
      "chest-pain-initial-assessment"
    end
  rescue
    _ -> "chest-pain-initial-assessment"
  end

  defp default_station_version do
    loader =
      Process.whereis(Backend.Stations.StationLoader) || Process.whereis(Backend.StationLoader)

    if loader do
      Backend.Stations.StationLoader.active_package(loader)["version"]
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

  defp station_duration_ms do
    Application.get_env(:backend, :station_duration_ms, @default_station_duration_ms)
  end

  defp turn_grace_ms do
    Application.get_env(:backend, :turn_grace_ms, @default_turn_grace_ms)
  end

  defp call_timeout_ms do
    turn_grace_ms() + 5_000
  end

  defp complete_now(session_id, reason) do
    case active_session(session_id) do
      {:ok, %{status: :active} = session} ->
        session =
          Map.merge(session, %{
            status: :completed,
            completed_at: DateTime.utc_now(),
            completion_reason: reason
          })

        true = :ets.insert(__MODULE__, {session_id, session})
        {:ok, session}

      {:ok, %{status: :completed} = session} ->
        {:ok, session}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec ensure_grace_timer(String.t(), turn()) :: turn()
  defp ensure_grace_timer(session_id, %{grace_ref: nil, token: token} = turn) do
    ref = Process.send_after(self(), {:grace_expired, session_id, token}, turn_grace_ms())
    %{turn | grace_ref: ref}
  end

  defp ensure_grace_timer(_session_id, turn), do: turn

  defp finalize_deferred_completion(session_id, turn, session, state) do
    if turn.first_reason do
      result = complete_now(session_id, turn.first_reason)
      reply_waiters(result, turn.waiters)

      case result do
        {:ok, completed} -> {completed, state}
        {:error, _reason} -> {session, state}
      end
    else
      {session, state}
    end
  end

  defp reply_waiters(result, waiters) do
    Enum.each(waiters, fn from -> GenServer.reply(from, result) end)
  end

  defp apply_resolution(session_id, _turn, {:ok, message}) do
    case active_session(session_id) do
      {:ok, session} ->
        message = Map.put(message, :at, DateTime.utc_now())
        updated = %{session | messages: session.messages ++ [message]}
        true = :ets.insert(__MODULE__, {session_id, updated})
        {:ok, updated}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_resolution(session_id, turn, :rollback) do
    case fetch_session(session_id) do
      {:ok, session} ->
        {:ok, do_rollback_pending_message(session_id, session, turn)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp rollback_pending_message(session_id, turn) do
    case fetch_session(session_id) do
      {:ok, session} -> do_rollback_pending_message(session_id, session, turn)
      {:error, _reason} -> :ok
    end
  end

  defp do_rollback_pending_message(session_id, session, turn) do
    updated =
      case List.last(session.messages) do
        last when last == turn.learner_message ->
          %{session | messages: :lists.droplast(session.messages)}

        _ ->
          session
      end

    true = :ets.insert(__MODULE__, {session_id, updated})
    updated
  end

  defp session_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  defp do_record_impresso_request(session, request_id, matched_ids, text) do
    case Enum.find(session.impresso_requests, &(&1.request_id == request_id)) do
      %{} = existing_event ->
        {:ok, %{event: existing_event, session: session}}

      nil ->
        {decision, newly_released} =
          Backend.Stations.Impressos.decide(matched_ids, session.released_impressos)

        event = %{
          request_id: request_id,
          station_id: session.station_id,
          station_version: session.station_version,
          order: length(session.impresso_requests) + 1,
          text: text,
          matched_ids: matched_ids,
          decision: decision,
          released_ids: newly_released,
          at: DateTime.utc_now()
        }

        updated_session = %{
          session
          | impresso_requests: session.impresso_requests ++ [event],
            released_impressos: session.released_impressos ++ newly_released
        }

        true = :ets.insert(__MODULE__, {session.session_id, updated_session})
        {:ok, %{event: event, session: updated_session}}
    end
  end

  defp do_pop_last_message(session, expected_message) do
    case List.last(session.messages) do
      nil ->
        {:error, :no_match}

      last_msg ->
        pop_if_matching(session, last_msg, expected_message)
    end
  end

  defp pop_if_matching(session, last_msg, expected_message) do
    if matches_expected?(last_msg, expected_message) do
      updated_messages = :lists.droplast(session.messages)
      session = %{session | messages: updated_messages}
      true = :ets.insert(__MODULE__, {session.session_id, session})
      {:ok, session}
    else
      {:error, :no_match}
    end
  end

  defp matches_expected?(_msg, nil), do: true

  defp matches_expected?(msg, %{role: role, text: text}) do
    normalize_match_role(msg.role) == normalize_match_role(role) and msg.text == text
  end

  defp matches_expected?(msg, %{"role" => role, "text" => text}) do
    normalize_match_role(msg.role) == normalize_match_role(role) and msg.text == text
  end

  defp matches_expected?(_msg, _), do: true

  defp normalize_match_role(r) when r in [:learner, "learner", :student, "student"], do: :learner
  defp normalize_match_role(r) when r in [:patient, "patient"], do: :patient
  defp normalize_match_role(other), do: other
end

defmodule Backend.Conversation do
  @moduledoc false
  defdelegate start_link(options \\ []), to: Backend.Stations.Conversation
  defdelegate start(attrs \\ %{}), to: Backend.Stations.Conversation
  defdelegate append_message(session_id, message), to: Backend.Stations.Conversation

  defdelegate pop_last_message(session_id, expected_message \\ nil),
    to: Backend.Stations.Conversation

  defdelegate complete(session_id, reason), to: Backend.Stations.Conversation
  defdelegate fetch(session_id), to: Backend.Stations.Conversation
  defdelegate discard(session_id), to: Backend.Stations.Conversation
end
