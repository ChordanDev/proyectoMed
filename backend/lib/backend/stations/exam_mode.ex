defmodule Backend.Stations.ExamMode do
  @moduledoc """
  The exam mode for the learner's next utterance (#364): the learner presses
  the exam button, and the next voice turn is an impresso request instead of a
  dialogue turn.

  One row per session in a public ETS table owned by the supervised
  `Backend.Stations.MediaSession` process:

    * `{:armed, expires_at}` — the next fresh voice turn before `expires_at`
      consumes the mode;
    * `{:consumed, turn_id}` — the turn that consumed it, so a retry of that
      same turn replays its impresso request instead of reaching the patient.

  Consuming is a compare-and-swap (`:ets.select_replace/2`), so two turns
  racing for one armed mode never both win. State is node-local and lost on
  restart, like the session state in `Backend.Stations.Conversation`; the
  learner then presses the button again.
  """

  @table __MODULE__

  @doc "Creates the table; called once by the owning `MediaSession` process."
  @spec create_table() :: :ok
  def create_table do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    :ok
  end

  @doc "Arms the mode for `session_id` until `expires_at`, replacing any earlier state."
  @spec arm(String.t(), DateTime.t()) :: :ok
  def arm(session_id, %DateTime{} = expires_at) do
    true = :ets.insert(@table, {session_id, {:armed, DateTime.to_unix(expires_at, :microsecond)}})
    :ok
  end

  @doc "Disarms the mode (cancel, discard, completion). Idempotent."
  @spec disarm(String.t()) :: :ok
  def disarm(session_id) do
    true = :ets.delete(@table, session_id)
    :ok
  end

  @doc "Whether `turn_id` already consumed the mode, so its retry replays."
  @spec consumed_by?(String.t(), pos_integer()) :: boolean()
  def consumed_by?(session_id, turn_id) do
    :ets.lookup(@table, session_id) == [{session_id, {:consumed, turn_id}}]
  end

  @doc "Whether the mode is armed and not expired at `now`."
  @spec armed?(String.t(), DateTime.t()) :: boolean()
  def armed?(session_id, now \\ DateTime.utc_now()) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, {:armed, expires_at}}] -> DateTime.to_unix(now, :microsecond) < expires_at
      _other -> false
    end
  end

  @doc """
  Consumes an armed, unexpired mode for `turn_id`: `:ok` when this turn won it,
  `:disarmed` otherwise (never armed, expired, cancelled or already consumed).
  """
  @spec consume(String.t(), pos_integer(), DateTime.t()) :: :ok | :disarmed
  def consume(session_id, turn_id, now \\ DateTime.utc_now()) do
    with [{^session_id, {:armed, expires_at} = armed}] <- :ets.lookup(@table, session_id),
         true <- DateTime.to_unix(now, :microsecond) < expires_at,
         1 <-
           :ets.select_replace(@table, [
             {{session_id, armed}, [], [{{session_id, {:const, {:consumed, turn_id}}}}]}
           ]) do
      :ok
    else
      _other -> :disarmed
    end
  end
end
