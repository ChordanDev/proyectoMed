defmodule Backend.Stations.Conversation do
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
          optional(:last_voice_turn_id) => pos_integer(),
          optional(:active_generation_id) => pos_integer() | nil,
          optional(:active_voice_turn_id) => pos_integer() | nil,
          optional(:next_generation_id) => pos_integer(),
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
  Atomically appends a learner voice turn unless `turn_id` is not greater than
  the last committed voice turn, which makes reconnects, retries and
  reordered provider finals idempotent.

  Preserves the base #118 return shape `{:ok, :committed | :duplicate}` for existing
  callers such as Backend.Stations.commit_voice_transcript and VoiceWorkerController.
  """
  @spec commit_voice_turn(String.t(), pos_integer(), String.t()) ::
          {:ok, :committed | :duplicate}
          | {:error, :not_found | :expired | :completed}
  def commit_voice_turn(session_id, turn_id, text) do
    GenServer.call(__MODULE__, {:commit_voice_turn, session_id, turn_id, text})
  end

  @doc """
  Atomically commits an accepted learner voice turn and assigns a session-scoped
  monotonic generation identity for bounded real-time turns (#119).

  Invalidates any previously pending generation on an accepted final turn.
  Returns `{:ok, :committed, generation_id}` on accepted turns, or `{:ok, :duplicate}`
  if turn_id is not greater than the last committed voice turn.
  """
  @spec begin_voice_turn(String.t(), pos_integer(), String.t()) ::
          {:ok, :committed, pos_integer()}
          | {:ok, :duplicate}
          | {:error, :not_found | :expired | :completed}
  def begin_voice_turn(session_id, turn_id, text) do
    GenServer.call(__MODULE__, {:begin_voice_turn, session_id, turn_id, text})
  end

  @doc """
  Atomically resolves a verified patient reply against the active generation identity.
  Refuses invalid replies (non-binary or empty text), stale generations,
  completed sessions, expired sessions, and missing/discarded sessions.
  """
  @spec resolve_patient_reply(String.t(), pos_integer(), String.t()) ::
          {:ok, session()}
          | {:error, :not_found | :expired | :completed | :stale_generation | :invalid_reply}
  def resolve_patient_reply(session_id, generation_id, reply_text) do
    GenServer.call(__MODULE__, {:resolve_patient_reply, session_id, generation_id, reply_text})
  end

  @doc """
  Explicitly cancels a pending generation. When `generation_id` is provided,
  cancels only if that generation is still active, protecting against races with newer turns.
  """
  @spec cancel_generation(String.t(), pos_integer() | nil) ::
          {:ok, :cancelled}
          | {:error, :not_found | :expired | :completed | :stale_generation}
  def cancel_generation(session_id, generation_id \\ nil) do
    GenServer.call(__MODULE__, {:cancel_generation, session_id, generation_id})
  end

  @doc """
  Explicitly cancels a pending voice turn by expected turn_id (#119).
  Cancels only if `turn_id` matches the currently active voice turn.
  """
  @spec cancel_voice_turn(String.t(), pos_integer() | keyword() | map() | nil) ::
          {:ok, :cancelled}
          | {:error, :not_found | :expired | :completed | :stale_generation}
  def cancel_voice_turn(session_id, criteria \\ nil)

  def cancel_voice_turn(session_id, turn_id) when is_integer(turn_id) and turn_id > 0 do
    GenServer.call(__MODULE__, {:cancel_voice_turn, session_id, turn_id})
  end

  def cancel_voice_turn(session_id, criteria) when is_list(criteria) or is_map(criteria) do
    GenServer.call(__MODULE__, {:cancel_by_criteria, session_id, criteria})
  end

  def cancel_voice_turn(session_id, nil) do
    cancel_generation(session_id, nil)
  end

  @doc """
  Returns the current active generation identity for the session, or nil if none is pending.
  """
  @spec active_generation(String.t()) ::
          {:ok, pos_integer() | nil}
          | {:error, :not_found | :expired | :completed}
  def active_generation(session_id) do
    GenServer.call(__MODULE__, {:active_generation, session_id})
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
      status: :active,
      last_voice_turn_id: 0,
      active_generation_id: nil,
      active_voice_turn_id: nil,
      next_generation_id: 1
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
                completion_reason: reason,
                active_generation_id: nil,
                active_voice_turn_id: nil
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

  def handle_call({:commit_voice_turn, session_id, turn_id, text}, _from, state) do
    do_voice_turn(session_id, turn_id, text, :legacy, state)
  end

  def handle_call({:begin_voice_turn, session_id, turn_id, text}, _from, state) do
    do_voice_turn(session_id, turn_id, text, :with_generation, state)
  end

  def handle_call({:resolve_patient_reply, session_id, generation_id, reply_text}, _from, state) do
    case active_session(session_id) do
      {:ok, %{status: :completed}} ->
        {:reply, {:error, :completed}, state}

      {:ok, session} ->
        active_gen = Map.get(session, :active_generation_id)

        cond do
          not valid_reply_text?(reply_text) ->
            {:reply, {:error, :invalid_reply}, state}

          is_nil(active_gen) or active_gen != generation_id ->
            {:reply, {:error, :stale_generation}, state}

          true ->
            patient_msg = %{
              role: :patient,
              modality: :voice,
              text: reply_text,
              at: DateTime.utc_now()
            }

            session =
              session
              |> Map.put(:messages, session.messages ++ [patient_msg])
              |> Map.put(:active_generation_id, nil)
              |> Map.put(:active_voice_turn_id, nil)

            true = :ets.insert(__MODULE__, {session_id, session})
            {:reply, {:ok, session}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:cancel_generation, session_id, generation_id}, _from, state) do
    case active_session(session_id) do
      {:ok, %{status: :completed}} ->
        {:reply, {:error, :completed}, state}

      {:ok, session} ->
        active_gen = Map.get(session, :active_generation_id)

        if generation_id != nil and active_gen != generation_id do
          {:reply, {:error, :stale_generation}, state}
        else
          session =
            session
            |> Map.put(:active_generation_id, nil)
            |> Map.put(:active_voice_turn_id, nil)

          true = :ets.insert(__MODULE__, {session_id, session})
          {:reply, {:ok, :cancelled}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:cancel_voice_turn, session_id, expected_turn_id}, from, state) do
    handle_call({:cancel_by_criteria, session_id, [turn_id: expected_turn_id]}, from, state)
  end

  def handle_call({:cancel_by_criteria, session_id, criteria}, _from, state) do
    case active_session(session_id) do
      {:ok, %{status: :completed}} ->
        {:reply, {:error, :completed}, state}

      {:ok, session} ->
        active_turn = Map.get(session, :active_voice_turn_id)
        active_gen = Map.get(session, :active_generation_id)

        expected_turn =
          get_criterion(criteria, :turn_id) || get_criterion(criteria, :expected_turn_id)

        expected_gen = get_criterion(criteria, :generation_id)

        stale? =
          cond do
            expected_turn != nil and (active_turn != expected_turn or is_nil(active_gen)) -> true
            expected_gen != nil and active_gen != expected_gen -> true
            true -> false
          end

        if stale? do
          {:reply, {:error, :stale_generation}, state}
        else
          session =
            session
            |> Map.put(:active_generation_id, nil)
            |> Map.put(:active_voice_turn_id, nil)

          true = :ets.insert(__MODULE__, {session_id, session})
          {:reply, {:ok, :cancelled}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:active_generation, session_id}, _from, state) do
    case active_session(session_id) do
      {:ok, %{status: :completed}} ->
        {:reply, {:error, :completed}, state}

      {:ok, session} ->
        {:reply, {:ok, Map.get(session, :active_generation_id)}, state}

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

  defp do_voice_turn(session_id, turn_id, text, return_mode, state) do
    case active_session(session_id) do
      {:ok, %{status: :completed}} ->
        {:reply, {:error, :completed}, state}

      {:ok, session} ->
        reply = commit_voice_turn(session_id, session, turn_id, text, return_mode)
        {:reply, reply, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp commit_voice_turn(session_id, session, turn_id, text, return_mode) do
    if turn_id <= Map.get(session, :last_voice_turn_id, 0) do
      {:ok, :duplicate}
    else
      gen_id = Map.get(session, :next_generation_id, 1)
      message = %{role: :learner, modality: :voice, text: text, at: DateTime.utc_now()}

      session =
        session
        |> Map.put(:messages, session.messages ++ [message])
        |> Map.put(:last_voice_turn_id, turn_id)
        |> Map.put(:active_generation_id, gen_id)
        |> Map.put(:active_voice_turn_id, turn_id)
        |> Map.put(:next_generation_id, gen_id + 1)

      true = :ets.insert(__MODULE__, {session_id, session})
      voice_turn_reply(return_mode, gen_id)
    end
  end

  defp voice_turn_reply(:legacy, _gen_id), do: {:ok, :committed}
  defp voice_turn_reply(:with_generation, gen_id), do: {:ok, :committed, gen_id}

  defp get_criterion(criteria, key) when is_list(criteria) do
    Keyword.get(criteria, key)
  end

  defp get_criterion(criteria, key) when is_map(criteria) do
    Map.get(criteria, key) || Map.get(criteria, to_string(key))
  end

  defp get_criterion(_criteria, _key), do: nil

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

  defp valid_reply_text?(text) when is_binary(text) do
    String.trim(text) != ""
  end

  defp valid_reply_text?(_), do: false

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

  defp session_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
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
