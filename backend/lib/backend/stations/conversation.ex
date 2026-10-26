defmodule Backend.Stations.Conversation do
  @moduledoc """
  Holds active station conversations in an ephemeral, in-memory session store.

  Sessions are never persisted. A completed session is immutable: calling
  `complete/2` again returns the original completed session. The only data
  added to a completed session are its rubric assessment
  (`put_rubric_assessment/2`, issue #301), its learner feedback cache
  (`put_learner_feedback/2`) and the after-delivery audits of its patient
  replies (`record_patient_audit/3`, issue #307), which live and die with the
  session.

  Learner feedback generation is single-flight per session
  (`claim_learner_feedback/2`, `settle_learner_feedback/2`): one caller
  generates while later callers for the same session wait for it to settle.
  A settled, crashed or exited owner, or a discarded session, releases every
  waiter.
  """

  use GenServer

  alias Backend.Stations.Usage

  @default_timeout_ms :timer.minutes(30)
  @default_purge_interval_ms :timer.minutes(1)
  @default_station_duration_ms :timer.minutes(10)
  @default_turn_grace_ms :timer.seconds(30)
  # `user_id` is the learner that started the session (#337).
  @pinned_station_keys [
    :user_id,
    :package,
    :station_version_id,
    :station_slug,
    :station_area,
    :station_theme
  ]

  @type session :: %{
          optional(:completed_at) => DateTime.t(),
          optional(:completion_reason) => term(),
          optional(:learner_feedback) => learner_feedback(),
          optional(:rubric_assessment) => map(),
          optional(:patient_audits) => [map()],
          optional(:elapsed_generation_id) => pos_integer(),
          optional(:last_voice_turn_id) => pos_integer(),
          optional(:cancelled_voice_turn_id) => non_neg_integer(),
          optional(:active_generation_id) => pos_integer() | nil,
          optional(:active_voice_turn_id) => pos_integer() | nil,
          optional(:active_generation_message_index) => non_neg_integer() | nil,
          optional(:next_generation_id) => pos_integer(),
          optional(:failed_voice_turn) =>
            %{
              turn_id: pos_integer(),
              generation_id: pos_integer(),
              reason: :station_ai_unavailable
            }
            | nil,
          optional(:package) => map(),
          optional(:user_id) => pos_integer(),
          optional(:station_version_id) => pos_integer(),
          optional(:station_slug) => String.t(),
          optional(:station_area) => String.t(),
          optional(:station_theme) => String.t(),
          session_id: String.t(),
          station_id: String.t() | pos_integer(),
          station_version: String.t() | pos_integer(),
          audio_consent: boolean(),
          started_at: DateTime.t(),
          expires_at: DateTime.t(),
          deadline_at: DateTime.t(),
          messages: [message()],
          released_impressos: [String.t()],
          impresso_requests: [impresso_request_event()],
          status: :active | :completed
        }

  @typedoc """
  A transcript message. A patient message may carry `verified_fact_ids`: the
  authored ids of the facts the Jev verdict that verified it found stated
  (issue #286). The session's disclosed facts are derived from them, see
  `disclosed_fact_ids/1`. In a station with a companion (issue #341) a patient
  message carries the `speaker` of the actor who said it.
  """
  @type message :: %{
          required(:role) => term(),
          required(:modality) => term(),
          required(:text) => String.t(),
          required(:at) => DateTime.t(),
          optional(:verified_fact_ids) => [String.t()],
          optional(:speaker) => :patient | :companion
        }

  @type impresso_request_event :: %{
          optional(:classification) => :plausible | :not_plausible | :undecided | :unclassified,
          request_id: String.t(),
          station_id: String.t() | pos_integer(),
          station_version: String.t() | pos_integer(),
          order: pos_integer(),
          text: String.t(),
          matched_ids: [String.t()],
          decision: :released | :already_released | :unavailable,
          released_ids: [String.t()],
          at: DateTime.t()
        }

  @typedoc """
  Learner feedback by criterion id, each entry bound to the fingerprint of the
  graded outcome it was generated for: either the generated `text`, or a
  failed generation not to retry before the monotonic `retry_after` (ms).
  """
  @type learner_feedback :: %{
          String.t() =>
            %{fingerprint: term(), text: String.t()}
            | %{fingerprint: term(), retry_after: integer()}
        }

  @type turn_token :: reference()

  @typep turn :: %{
           token: turn_token(),
           learner_message: message(),
           waiters: [GenServer.from()],
           first_reason: term() | nil,
           grace_ref: reference() | nil
         }

  @typep voice_grace :: %{
           token: reference(),
           grace_ref: reference() | nil,
           waiters: [GenServer.from()]
         }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @doc """
  Starts a session. `:audio_consent` defaults to `false`: audio transcription is
  refused until the learner explicitly grants it.

  A session started on a published Station version (issue #334) also carries
  its pinned `:package` and the version's `:station_version_id`,
  `:station_slug`, `:station_area` and `:station_theme`.
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

  @doc """
  Completes a session. While a text turn is pending the caller waits until it
  settles or the bounded grace period elapses. A `:timer` completion takes the
  deadline's decision: it also waits, under the same single grace window, for a
  voice generation in flight. Any other reason completes at once in that case.
  """
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

  The deadline grants one grace window per session: it also covers a voice
  generation in flight, see `begin_voice_turn/3` and `resolve_patient_reply/4`.
  """
  @spec begin_turn(String.t(), map()) ::
          {:ok, session(), turn_token()}
          | {:error, :not_found | :expired | :completed | :station_time_elapsed}
  def begin_turn(session_id, message) do
    GenServer.call(__MODULE__, {:begin_turn, session_id, message})
  end

  @doc """
  Resolves a pending turn identified by `token`: appends the patient reply
  (`{:ok, message}`), keeps the learner message without a patient reply
  (`:keep_learner_turn`), or rolls back the learner message (`:rollback`).

  Returns `{:error, :station_time_elapsed}` if the token is no longer pending
  (already rolled back by the grace timer, or unknown/stale).
  """
  @spec resolve_turn(
          String.t(),
          turn_token(),
          {:ok, map()} | :keep_learner_turn | :rollback
        ) ::
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

  `opts` accepts `:classification`, the Jev classification of an unavailable
  request (#357), stored on the new event; without it the event has no
  `:classification` key. The classification is never graded.

  A repeated `request_id` is idempotent: it returns the originally stored
  event untouched (its classification included) and does not append a new one
  or change `released_impressos`.
  """
  @spec record_impresso_request(String.t(), String.t(), [String.t()], String.t(), keyword()) ::
          {:ok, %{event: impresso_request_event(), session: session()}}
          | {:error, :not_found | :expired | :completed}
  def record_impresso_request(session_id, request_id, matched_ids, text, opts \\ []) do
    GenServer.call(
      __MODULE__,
      {:record_impresso_request, session_id, request_id, matched_ids, text,
       Keyword.take(opts, [:classification])}
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
  Atomically appends a learner voice turn unless `turn_id` is not greater than
  the last committed voice turn, which makes reconnects, retries and
  reordered provider finals idempotent.

  Preserves the base #118 return shape `{:ok, :committed | :duplicate}` for existing
  callers such as Backend.Stations.commit_voice_transcript and VoiceWorkerController.

  Follows the station deadline exactly as `begin_voice_turn/3` does.
  """
  @spec commit_voice_turn(String.t(), pos_integer(), String.t()) ::
          {:ok, :committed | :duplicate}
          | {:error,
             :not_found | :expired | :completed | :stale_generation | :station_time_elapsed}
  def commit_voice_turn(session_id, turn_id, text) do
    GenServer.call(__MODULE__, {:commit_voice_turn, session_id, turn_id, text})
  end

  @doc """
  Atomically commits an accepted learner voice turn and assigns a session-scoped
  monotonic generation identity for bounded real-time turns (#119).

  Invalidates any previously pending generation on an accepted final turn.
  Returns `{:ok, :committed, generation_id}` on accepted turns, or `{:ok, :duplicate}`
  if turn_id is not greater than the last committed voice turn. The latest failed
  generation returns its canonical technical failure on retry instead of duplicate.

  A new turn at or after the authoritative deadline, or any turn on a session
  completed by the timer, returns `{:error, :station_time_elapsed}` and appends
  nothing. A generation still in flight when the deadline fires defers the timer
  completion for the same bounded grace period a pending text turn gets.
  """
  @spec begin_voice_turn(String.t(), pos_integer(), String.t()) ::
          {:ok, :committed, pos_integer()}
          | {:ok, :duplicate}
          | {:error,
             :not_found
             | :expired
             | :completed
             | :stale_generation
             | :station_ai_unavailable
             | :station_time_elapsed}
  def begin_voice_turn(session_id, turn_id, text) do
    GenServer.call(__MODULE__, {:begin_voice_turn, session_id, turn_id, text})
  end

  @doc """
  Records a canonical technical failure only for the still-active generation.
  Keeps one turn-scoped outcome until a newer turn or session completion, never
  provider payloads or reply text. Cancellation and supersession remain stale.
  """
  @spec fail_generation(String.t(), pos_integer(), :station_ai_unavailable) ::
          {:ok, :failed}
          | {:error, :not_found | :expired | :completed | :stale_generation}
  def fail_generation(session_id, generation_id, :station_ai_unavailable)
      when is_integer(generation_id) and generation_id > 0 do
    GenServer.call(__MODULE__, {:fail_generation, session_id, generation_id})
  end

  @doc """
  Atomically resolves a verified patient reply against the active generation identity.
  Refuses invalid replies (non-binary or empty text), stale generations,
  completed sessions, expired sessions, and missing/discarded sessions.

  `:keep_learner_turn` settles the generation the same way without appending a
  patient message: the learner voice turn stays, as `resolve_turn/3` keeps a
  text turn whose patient reply was refused (#235, #269).

  A reply resolved inside the deadline grace window is appended and the returned
  session is then completed with reason `:timer`, unless a text turn is still
  pending under the same window. Once the window elapsed, the generation it cut
  off returns `{:error, :station_time_elapsed}` and nothing is appended.

  `verified_fact_ids` are stored on the appended patient message (issue #286);
  they are recorded only when the reply is, never for a stale, cancelled or
  kept generation.

  `speaker` (issue #341) is `:companion` for a reply of a station's companion,
  stored on the message as `speaker`; `nil` (the default) stores none, as for
  every single-actor station.
  """
  @spec resolve_patient_reply(
          String.t(),
          pos_integer(),
          String.t() | :keep_learner_turn,
          [String.t()],
          :patient | :companion | nil
        ) ::
          {:ok, session()}
          | {:error,
             :not_found
             | :expired
             | :completed
             | :stale_generation
             | :invalid_reply
             | :station_time_elapsed}
  def resolve_patient_reply(
        session_id,
        generation_id,
        reply_text,
        verified_fact_ids \\ [],
        speaker \\ nil
      ) do
    GenServer.call(
      __MODULE__,
      {:resolve_patient_reply, session_id, generation_id, reply_text, verified_fact_ids, speaker}
    )
  end

  @doc """
  The facts the session's verified patient turns disclosed (issue #286): the
  `verified_fact_ids` of its patient messages, in first-disclosure order,
  without duplicates. Derived from the transcript, so it lives and dies with the
  session and is unaffected by kept, rolled back or cancelled learner turns.
  """
  @spec disclosed_fact_ids(session()) :: [String.t()]
  def disclosed_fact_ids(%{messages: messages}) when is_list(messages) do
    messages
    |> Enum.flat_map(fn
      %{role: :patient, verified_fact_ids: ids} when is_list(ids) -> ids
      _message -> []
    end)
    |> Enum.uniq()
  end

  def disclosed_fact_ids(_session), do: []

  @doc """
  Records the after-delivery Jev audit of a patient message (issue #307).

  The message is the patient message stored at `message_at`. `audit` is
  appended to the session's `patient_audits` with that message's
  `message_index`; when `verified_fact_ids` is a list it replaces the message's
  `verified_fact_ids`, so `disclosed_fact_ids/1` follows the audit verdict.
  A completed session still records it: audits are measurement data that live
  and die with the session. Returns the recorded audit.
  """
  @spec record_patient_audit(String.t(), DateTime.t(), %{
          audit: map(),
          verified_fact_ids: [String.t()] | nil
        }) :: {:ok, map()} | {:error, :not_found | :expired | :message_not_found}
  def record_patient_audit(session_id, message_at, entry) do
    GenServer.call(__MODULE__, {:record_patient_audit, session_id, message_at, entry})
  end

  @doc """
  Explicitly cancels a pending generation. When `generation_id` is provided,
  cancels only if that generation is still active, protecting against races with newer turns.

  Cancelling or failing the generation a deadline grace window was waiting for
  completes the session with reason `:timer` at once, unless a text turn is
  still pending; the return value is unchanged.
  """
  @spec cancel_generation(String.t(), pos_integer() | nil) ::
          {:ok, :cancelled}
          | {:error, :not_found | :expired | :completed | :stale_generation}
  def cancel_generation(session_id, generation_id \\ nil) do
    GenServer.call(__MODULE__, {:cancel_generation, session_id, generation_id})
  end

  @doc """
  Explicitly cancels a pending voice turn by expected turn_id (#119).
  Cancels active work only if `turn_id` matches. Turn-only criteria also fence
  future admission through that monotonic turn ID, even when no active work
  matches (the existing `:stale_generation` response is preserved). A supplied
  generation must match before a fence is installed. Already admitted duplicates
  retain their idempotent return shape; a fence never removes transcript messages.
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

  @doc "Returns the learner feedback cache of a session, or `%{}` when it has none."
  @spec learner_feedback(String.t()) ::
          {:ok, learner_feedback()} | {:error, :not_found | :expired}
  def learner_feedback(session_id) do
    with {:ok, session} <- fetch(session_id) do
      {:ok, Map.get(session, :learner_feedback, %{})}
    end
  end

  @doc """
  Returns the rubric assessment kept with a session, or `nil` before it has
  been graded (issue #301).
  """
  @spec rubric_assessment(String.t()) :: {:ok, map() | nil} | {:error, :not_found | :expired}
  def rubric_assessment(session_id) do
    with {:ok, session} <- fetch(session_id) do
      {:ok, Map.get(session, :rubric_assessment)}
    end
  end

  @doc """
  Keeps the rubric assessment of a completed session, so it is graded once
  (issue #301). An assessment already kept is never replaced, and a missing,
  expired or still active session is left untouched.
  """
  @spec put_rubric_assessment(String.t(), map()) ::
          :ok | {:error, :not_found | :expired | :session_not_finished}
  def put_rubric_assessment(session_id, assessment) when is_map(assessment) do
    GenServer.call(__MODULE__, {:put_rubric_assessment, session_id, assessment})
  end

  @doc """
  Merges `entries` into the learner feedback cache of a session, replacing
  entries with the same criterion id. A missing or expired session is left
  untouched, so the cache never outlives a discarded session.
  """
  @spec put_learner_feedback(String.t(), learner_feedback()) ::
          :ok | {:error, :not_found | :expired}
  def put_learner_feedback(session_id, entries) when is_map(entries) do
    GenServer.call(__MODULE__, {:put_learner_feedback, session_id, entries})
  end

  @doc """
  Claims learner feedback generation for a session.

  Returns `:generate` when the caller now owns the generation and must call
  `settle_learner_feedback/2` (or exit) when done. When another process is
  already generating for the session, the call blocks until that owner
  settles, exits or the session is discarded, and returns `:settled`; the
  caller then reads the cache instead of generating. `timeout` bounds the
  wait; an exit is the caller's to handle.
  """
  @spec claim_learner_feedback(String.t(), timeout()) ::
          :generate | :settled | {:error, :not_found | :expired}
  def claim_learner_feedback(session_id, timeout) do
    GenServer.call(__MODULE__, {:claim_learner_feedback, session_id}, timeout)
  end

  @doc """
  Merges `entries` into the learner feedback cache of a session, like
  `put_learner_feedback/2`, and releases the generation the caller claimed,
  waking every waiter. A missing or expired session is left untouched.
  """
  @spec settle_learner_feedback(String.t(), learner_feedback()) ::
          :ok | {:error, :not_found | :expired}
  def settle_learner_feedback(session_id, entries) when is_map(entries) do
    GenServer.call(__MODULE__, {:settle_learner_feedback, session_id, entries})
  end

  @impl true
  def init(_options) do
    :ets.new(__MODULE__, [:named_table, :set, :public, read_concurrency: true])
    # Per-session provider usage counters (issue #342) live as long as sessions.
    :ok = Usage.create_table()
    schedule_purge()
    {:ok, %{turns: %{}, voice_graces: %{}, feedback_flights: %{}}}
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
      status: :active,
      last_voice_turn_id: 0,
      cancelled_voice_turn_id: 0,
      active_generation_id: nil,
      active_voice_turn_id: nil,
      active_generation_message_index: nil,
      next_generation_id: 1,
      failed_voice_turn: nil
    }

    session = Map.merge(session, Map.take(attrs, @pinned_station_keys))

    true = :ets.insert(__MODULE__, {session.session_id, session})
    Process.send_after(self(), {:deadline, session.session_id}, station_duration_ms())
    {:reply, session, state}
  end

  def handle_call({:begin_turn, session_id, message}, _from, state) do
    case active_session(session_id) do
      {:ok, %{status: :completed} = session} ->
        {:reply, {:error, completed_turn_error(session)}, state}

      {:ok, %{status: :active} = session} ->
        now = DateTime.utc_now()

        if deadline_passed?(session, now) do
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
        case apply_resolution(session_id, turn, resolution) do
          {:ok, session} ->
            state = %{state | turns: Map.delete(state.turns, session_id)}

            {final_session, state} =
              finalize_deferred_completion(session_id, turn, session, state)

            {:reply, {:ok, final_session}, state}

          {:error, reason} ->
            if turn.grace_ref, do: Process.cancel_timer(turn.grace_ref)
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
        complete_without_turn(session_id, reason, from, state)
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

  def handle_call(
        {:resolve_patient_reply, session_id, generation_id, reply_text, verified_fact_ids,
         speaker},
        _from,
        state
      ) do
    case active_session(session_id) do
      {:ok, %{status: :completed} = session} ->
        {:reply, {:error, completed_generation_error(session, generation_id)}, state}

      {:ok, session} ->
        active_gen = Map.get(session, :active_generation_id)

        cond do
          not valid_reply_text?(reply_text) ->
            {:reply, {:error, :invalid_reply}, state}

          is_nil(active_gen) or active_gen != generation_id ->
            {:reply, {:error, :stale_generation}, state}

          true ->
            session =
              session
              |> Map.put(
                :messages,
                session.messages ++ patient_messages(reply_text, verified_fact_ids, speaker)
              )
              |> Map.put(:active_generation_id, nil)
              |> Map.put(:active_voice_turn_id, nil)
              |> Map.put(:active_generation_message_index, nil)

            true = :ets.insert(__MODULE__, {session_id, session})
            {final_session, state} = finalize_voice_grace(session_id, session, state)
            {:reply, {:ok, final_session}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:fail_generation, session_id, generation_id}, _from, state) do
    case active_session(session_id) do
      {:ok, %{status: :completed}} ->
        {:reply, {:error, :completed}, state}

      {:ok, session} ->
        if session.active_generation_id == generation_id do
          failure = %{
            turn_id: session.active_voice_turn_id,
            generation_id: generation_id,
            reason: :station_ai_unavailable
          }

          session =
            session
            |> Map.put(:failed_voice_turn, failure)
            |> Map.put(:active_generation_id, nil)
            |> Map.put(:active_voice_turn_id, nil)
            |> Map.put(:active_generation_message_index, nil)

          true = :ets.insert(__MODULE__, {session_id, session})
          {:reply, {:ok, :failed}, settle_abandoned_voice_grace(session_id, state)}
        else
          {:reply, {:error, :stale_generation}, state}
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
            |> Map.put(:active_generation_message_index, nil)

          true = :ets.insert(__MODULE__, {session_id, session})
          {:reply, {:ok, :cancelled}, settle_abandoned_voice_grace(session_id, state)}
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

        # Turn IDs order a session's stream. One high-water mark fences delayed
        # POSTs/retries without an unbounded identity set or touching newer active
        # work. A mismatched generation-qualified request has no side effects.
        session =
          if is_integer(expected_turn) and expected_turn > 0 and
               (is_nil(expected_gen) or not stale?) do
            fenced =
              Map.put(
                session,
                :cancelled_voice_turn_id,
                max(Map.get(session, :cancelled_voice_turn_id, 0), expected_turn)
              )

            true = :ets.insert(__MODULE__, {session_id, fenced})
            fenced
          else
            session
          end

        if stale? do
          {:reply, {:error, :stale_generation}, state}
        else
          session =
            session
            |> Map.put(:active_generation_id, nil)
            |> Map.put(:active_voice_turn_id, nil)
            |> Map.put(:active_generation_message_index, nil)

          true = :ets.insert(__MODULE__, {session_id, session})
          {:reply, {:ok, :cancelled}, settle_abandoned_voice_grace(session_id, state)}
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

  def handle_call(
        {:record_impresso_request, session_id, request_id, matched_ids, text, opts},
        _from,
        state
      ) do
    case active_session(session_id) do
      {:ok, %{status: :active} = session} ->
        {:reply, do_record_impresso_request(session, request_id, matched_ids, text, opts), state}

      {:ok, %{status: :completed}} ->
        {:reply, {:error, :completed}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:put_learner_feedback, session_id, entries}, _from, state) do
    {:reply, merge_learner_feedback(session_id, entries), state}
  end

  def handle_call({:claim_learner_feedback, session_id}, {pid, _tag} = from, state) do
    flights = Map.get(state, :feedback_flights, %{})

    case Map.fetch(flights, session_id) do
      {:ok, flight} ->
        flight = %{flight | waiters: [from | flight.waiters]}
        {:noreply, Map.put(state, :feedback_flights, Map.put(flights, session_id, flight))}

      :error ->
        case fetch_session(session_id) do
          {:ok, _session} ->
            flight = %{owner: pid, monitor: Process.monitor(pid), waiters: []}
            flights = Map.put(flights, session_id, flight)
            {:reply, :generate, Map.put(state, :feedback_flights, flights)}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call({:record_patient_audit, session_id, message_at, entry}, _from, state) do
    with {:ok, session} <- fetch_session(session_id),
         index when is_integer(index) <-
           Enum.find_index(session.messages, &match?(%{role: :patient, at: ^message_at}, &1)) do
      audit = Map.put(entry.audit, :message_index, index)

      messages =
        case entry.verified_fact_ids do
          ids when is_list(ids) ->
            List.update_at(session.messages, index, &Map.put(&1, :verified_fact_ids, ids))

          nil ->
            session.messages
        end

      session =
        session
        |> Map.put(:messages, messages)
        |> Map.put(:patient_audits, Map.get(session, :patient_audits, []) ++ [audit])

      true = :ets.insert(__MODULE__, {session_id, session})
      {:reply, {:ok, audit}, state}
    else
      nil -> {:reply, {:error, :message_not_found}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:put_rubric_assessment, session_id, assessment}, _from, state) do
    case fetch_session(session_id) do
      {:ok, %{status: :completed, rubric_assessment: %{}}} ->
        {:reply, :ok, state}

      {:ok, %{status: :completed} = session} ->
        true =
          :ets.insert(__MODULE__, {session_id, Map.put(session, :rubric_assessment, assessment)})

        {:reply, :ok, state}

      {:ok, _active} ->
        {:reply, {:error, :session_not_finished}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:settle_learner_feedback, session_id, entries}, {pid, _tag}, state) do
    reply = merge_learner_feedback(session_id, entries)

    state =
      case state |> Map.get(:feedback_flights, %{}) |> Map.get(session_id) do
        %{owner: ^pid} -> release_flight(state, session_id)
        _other -> state
      end

    {:reply, reply, state}
  end

  def handle_call({:discard, session_id}, _from, state) do
    :ets.delete(__MODULE__, session_id)
    Usage.forget(session_id)

    state =
      case Map.pop(state.turns, session_id) do
        {nil, state_turns} ->
          %{state | turns: state_turns}

        {%{waiters: waiters, grace_ref: grace_ref}, state_turns} ->
          if grace_ref, do: Process.cancel_timer(grace_ref)
          reply_waiters({:error, :not_found}, waiters)
          %{state | turns: state_turns}
      end

    {voice_grace, state} = pop_voice_grace(state, session_id)
    reply_waiters({:error, :not_found}, voice_grace.waiters)
    {:reply, :ok, release_flight(state, session_id)}
  end

  @impl true
  def handle_info(:purge_expired, state) do
    now = DateTime.utc_now()

    for {session_id, session} <- :ets.tab2list(__MODULE__), expired?(session, now) do
      :ets.delete(__MODULE__, session_id)
      Usage.forget(session_id)
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
        {:noreply, defer_or_complete_timer(session_id, [], state)}
    end
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    flights = Map.get(state, :feedback_flights, %{})

    case Enum.find(flights, fn {_session_id, flight} -> flight.monitor == monitor end) do
      {session_id, _flight} -> {:noreply, release_flight(state, session_id)}
      nil -> {:noreply, state}
    end
  end

  def handle_info({:grace_expired, session_id, token}, state) do
    case {get_in(state, [:turns, session_id]), Map.get(state.voice_graces, session_id)} do
      {%{token: ^token} = turn, _voice_grace} ->
        rollback_pending_message(session_id, turn)
        reason = turn.first_reason || :timer
        reply_waiters(complete_deferred(session_id, reason), turn.waiters)
        state = %{state | turns: Map.delete(state.turns, session_id)}
        {:noreply, state}

      {_turn, %{token: ^token} = voice_grace} ->
        reply_waiters(complete_deferred(session_id, :timer), voice_grace.waiters)
        state = %{state | voice_graces: Map.delete(state.voice_graces, session_id)}
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  defp do_voice_turn(session_id, turn_id, text, return_mode, state) do
    case active_session(session_id) do
      {:ok, session} ->
        reply = commit_voice_turn(session_id, session, turn_id, text, return_mode)
        {:reply, reply, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp commit_voice_turn(_session_id, %{status: :completed} = session, _turn_id, _text, _mode) do
    {:error, completed_turn_error(session)}
  end

  defp commit_voice_turn(session_id, session, turn_id, text, return_mode) do
    now = DateTime.utc_now()

    cond do
      turn_id <= Map.get(session, :last_voice_turn_id, 0) ->
        case {return_mode, Map.get(session, :failed_voice_turn)} do
          {:with_generation, %{turn_id: ^turn_id, reason: :station_ai_unavailable}} ->
            {:error, :station_ai_unavailable}

          _ ->
            {:ok, :duplicate}
        end

      # Only a new turn starts work: retries of an admitted turn stay idempotent.
      deadline_passed?(session, now) ->
        {:error, :station_time_elapsed}

      turn_id <= Map.get(session, :cancelled_voice_turn_id, 0) ->
        {:error, :stale_generation}

      true ->
        gen_id = Map.get(session, :next_generation_id, 1)
        message = %{role: :learner, modality: :voice, text: text, at: now}

        session =
          session
          |> Map.put(:messages, session.messages ++ [message])
          |> Map.put(:last_voice_turn_id, turn_id)
          |> Map.put(:active_generation_id, gen_id)
          |> Map.put(:active_voice_turn_id, turn_id)
          |> Map.put(:active_generation_message_index, length(session.messages))
          |> Map.put(:next_generation_id, gen_id + 1)
          |> Map.put(:failed_voice_turn, nil)

        true = :ets.insert(__MODULE__, {session_id, session})
        voice_turn_reply(return_mode, gen_id)
    end
  end

  defp voice_turn_reply(:legacy, _gen_id), do: {:ok, :committed}
  defp voice_turn_reply(:with_generation, gen_id), do: {:ok, :committed, gen_id}

  defp deadline_passed?(session, now) do
    DateTime.compare(now, session.deadline_at) != :lt
  end

  defp completed_turn_error(%{completion_reason: :timer}), do: :station_time_elapsed
  defp completed_turn_error(_session), do: :completed

  defp completed_generation_error(
         %{completion_reason: :timer, elapsed_generation_id: generation_id},
         generation_id
       ),
       do: :station_time_elapsed

  defp completed_generation_error(_session, _generation_id), do: :completed

  defp voice_generation_in_flight?(session_id) do
    case fetch_session(session_id) do
      {:ok, %{status: :active} = session} -> is_integer(Map.get(session, :active_generation_id))
      _ -> false
    end
  end

  defp get_criterion(criteria, key) when is_list(criteria) do
    Keyword.get(criteria, key)
  end

  defp get_criterion(criteria, key) when is_map(criteria) do
    Map.get(criteria, key) || Map.get(criteria, to_string(key))
  end

  defp get_criterion(_criteria, _key), do: nil

  defp merge_learner_feedback(session_id, entries) do
    case fetch_session(session_id) do
      {:ok, session} ->
        cache = session |> Map.get(:learner_feedback, %{}) |> Map.merge(entries)
        true = :ets.insert(__MODULE__, {session_id, Map.put(session, :learner_feedback, cache)})
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Ends the learner feedback generation of a session, if any, and wakes its
  # waiters so they read the cache.
  defp release_flight(state, session_id) do
    case Map.pop(Map.get(state, :feedback_flights, %{}), session_id) do
      {nil, _flights} ->
        state

      {flight, flights} ->
        Process.demonitor(flight.monitor, [:flush])
        reply_waiters(:settled, flight.waiters)
        Map.put(state, :feedback_flights, flights)
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
          Usage.forget(session_id)
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

  defp patient_messages(:keep_learner_turn, _verified_fact_ids, _speaker), do: []

  defp patient_messages(reply_text, verified_fact_ids, speaker) do
    message = %{
      role: :patient,
      modality: :voice,
      text: reply_text,
      at: DateTime.utc_now(),
      verified_fact_ids: Enum.filter(List.wrap(verified_fact_ids), &is_binary/1)
    }

    [if(speaker, do: Map.put(message, :speaker, speaker), else: message)]
  end

  defp valid_reply_text?(:keep_learner_turn), do: true

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
            completion_reason: reason,
            active_generation_id: nil,
            active_voice_turn_id: nil,
            active_generation_message_index: nil,
            failed_voice_turn: nil
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

  defp complete_without_turn(session_id, :timer, from, state) do
    {:noreply, defer_or_complete_timer(session_id, [from], state)}
  end

  defp complete_without_turn(session_id, reason, _from, state) do
    result = complete_now(session_id, reason)
    {voice_grace, state} = pop_voice_grace(state, session_id)
    reply_waiters(result, voice_grace.waiters)
    {:reply, result, state}
  end

  # The one timer decision when no text turn is pending, shared by the deadline
  # and a manual `:timer` completion: a voice generation in flight gets the
  # session's single grace window, otherwise the session completes now.
  defp defer_or_complete_timer(session_id, waiters, state) do
    case Map.get(state.voice_graces, session_id) do
      %{} = voice_grace ->
        put_voice_grace(state, session_id, %{
          voice_grace
          | waiters: waiters ++ voice_grace.waiters
        })

      nil ->
        if voice_generation_in_flight?(session_id) do
          arm_voice_grace(state, session_id, waiters)
        else
          reply_waiters(complete_now(session_id, :timer), waiters)
          state
        end
    end
  end

  defp arm_voice_grace(state, session_id, waiters) do
    token = make_ref()
    ref = Process.send_after(self(), {:grace_expired, session_id, token}, turn_grace_ms())
    put_voice_grace(state, session_id, %{token: token, grace_ref: ref, waiters: waiters})
  end

  @spec put_voice_grace(map(), String.t(), voice_grace()) :: map()
  defp put_voice_grace(state, session_id, voice_grace) do
    %{state | voice_graces: Map.put(state.voice_graces, session_id, voice_grace)}
  end

  # Cancels and removes the session's voice grace; its waiters are the caller's to answer.
  defp pop_voice_grace(state, session_id) do
    case Map.pop(state.voice_graces, session_id) do
      {nil, _voice_graces} ->
        {%{waiters: []}, state}

      {%{grace_ref: grace_ref} = voice_grace, voice_graces} ->
        if grace_ref, do: Process.cancel_timer(grace_ref)
        {voice_grace, %{state | voice_graces: voice_graces}}
    end
  end

  defp finalize_deferred_completion(session_id, turn, session, state) do
    cond do
      is_nil(turn.first_reason) ->
        {session, state}

      # The timer's grace window keeps running for a voice generation still in
      # flight, and callers waiting on the timer completion keep waiting with it.
      turn.first_reason == :timer and is_integer(Map.get(session, :active_generation_id)) ->
        voice_grace = %{token: turn.token, grace_ref: turn.grace_ref, waiters: turn.waiters}
        {session, put_voice_grace(state, session_id, voice_grace)}

      true ->
        if turn.grace_ref, do: Process.cancel_timer(turn.grace_ref)
        result = complete_deferred(session_id, turn.first_reason)
        reply_waiters(result, turn.waiters)

        case result do
          {:ok, completed} -> {completed, state}
          {:error, _reason} -> {session, state}
        end
    end
  end

  # A voice reply settled the generation the deadline was waiting for. A text
  # turn still pending under grace owns the completion instead.
  defp finalize_voice_grace(session_id, session, state) do
    case complete_voice_grace(session_id, state) do
      {{:ok, completed}, state} -> {completed, state}
      {_no_completion, state} -> {session, state}
    end
  end

  # The generation the deadline was waiting for was cancelled or failed, so no
  # reply can arrive inside the window: the session completes now instead of at
  # grace expiry. The learner message stays, as it does for a generation
  # abandoned before the deadline. A pending text turn keeps the window.
  defp settle_abandoned_voice_grace(session_id, state) do
    if Map.has_key?(state.turns, session_id) do
      state
    else
      {_result, state} = complete_voice_grace(session_id, state)
      state
    end
  end

  # Ends an armed voice grace: the session completes with the timer's reason and
  # the callers parked on it are answered. `:none` when no window is armed.
  defp complete_voice_grace(session_id, state) do
    if Map.has_key?(state.voice_graces, session_id) do
      {voice_grace, state} = pop_voice_grace(state, session_id)
      result = complete_now(session_id, :timer)
      reply_waiters(result, voice_grace.waiters)
      {result, state}
    else
      {:none, state}
    end
  end

  # Completion that was deferred behind in-flight work. When the timer is the
  # reason, a voice generation still unanswered has run out of time too.
  defp complete_deferred(session_id, :timer) do
    expire_voice_generation(session_id)
    complete_now(session_id, :timer)
  end

  defp complete_deferred(session_id, reason), do: complete_now(session_id, reason)

  defp expire_voice_generation(session_id) do
    case fetch_session(session_id) do
      {:ok, %{status: :active, active_generation_id: generation_id} = session}
      when is_integer(generation_id) ->
        updated =
          session
          |> remove_message_at(Map.get(session, :active_generation_message_index))
          |> Map.put(:elapsed_generation_id, generation_id)

        true = :ets.insert(__MODULE__, {session_id, updated})
        :ok

      _ ->
        :ok
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

  defp apply_resolution(session_id, _turn, :keep_learner_turn) do
    active_session(session_id)
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
    # A voice turn may have been appended after the pending learner message, so
    # it is found by identity rather than assumed to be the tail.
    index =
      session.messages
      |> Enum.with_index()
      |> Enum.reverse()
      |> Enum.find_value(fn {message, index} -> message == turn.learner_message && index end)

    updated = remove_message_at(session, index)
    true = :ets.insert(__MODULE__, {session_id, updated})
    updated
  end

  defp remove_message_at(session, nil), do: session

  defp remove_message_at(session, index) do
    session = %{session | messages: List.delete_at(session.messages, index)}

    # The generation origin is an absolute index: keep it on the same message.
    case Map.get(session, :active_generation_message_index) do
      origin when is_integer(origin) and origin > index ->
        Map.put(session, :active_generation_message_index, origin - 1)

      _ ->
        session
    end
  end

  defp session_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  defp do_record_impresso_request(session, request_id, matched_ids, text, opts) do
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

        event =
          case Keyword.fetch(opts, :classification) do
            {:ok, classification} when not is_nil(classification) ->
              Map.put(event, :classification, classification)

            _none ->
              event
          end

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

      # Append/tail-pop keeps the origin's position stable even for identical messages.
      session =
        if Map.get(session, :active_generation_message_index) == length(updated_messages) do
          session
          |> Map.put(:active_generation_id, nil)
          |> Map.put(:active_voice_turn_id, nil)
          |> Map.put(:active_generation_message_index, nil)
        else
          session
        end

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
