defmodule Backend.Stations.Usage do
  @moduledoc """
  Per-session provider usage (issue #342): Claude tokens per model, Jev
  (TypeSafe) calls and the audio usage the voice worker reports.

  ## Attribution

  The provider clients (`Backend.Stations.StationAI.AnthropicClient`,
  `Backend.Stations.JevDecision.TypesafeAdapter`) do not know which session
  they serve. A `Backend.Stations` entry point runs its work inside
  `track/2`, which marks the calling process with the session id; a recorded
  call is attributed to the session of the calling process or, for a
  `Task.async` child, of the first process in its `$callers` that has one. A
  detached task that may outlive its caller (the patient audit) carries the
  id itself with `track/2`. A call made outside any tracked session is not
  recorded.

  ## Storage

  Counters are integers in a public ETS table owned by
  `Backend.Stations.Conversation` (created in its `init/1`), so they live as
  long as the in-memory sessions and are dropped with them (`forget/1`). Only
  counts are kept: no prompt, transcript, reply, user id or key. The finished
  session's totals are persisted by `Backend.Stations.Usage.Store`.
  """

  @table __MODULE__
  @session_key :"$backend_usage_session"
  @claude_fields [
    :input_tokens,
    :output_tokens,
    :cache_read_input_tokens,
    :cache_creation_input_tokens
  ]

  @typedoc "Claude token counts of one model."
  @type claude_tokens :: %{
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          cache_read_input_tokens: non_neg_integer(),
          cache_creation_input_tokens: non_neg_integer()
        }

  @typedoc "Audio usage the voice worker reports (ADR-013 #209)."
  @type voice :: %{
          deepgram_audio_seconds: float(),
          cartesia_characters: non_neg_integer(),
          livekit_participant_minutes: float()
        }

  @type snapshot :: %{
          claude: %{optional(String.t()) => claude_tokens()},
          jev_calls: non_neg_integer(),
          voice: voice()
        }

  @doc false
  @spec create_table() :: :ok
  def create_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :set, :public, write_concurrency: true])
    end

    :ok
  end

  @doc "The Claude token fields recorded per model."
  @spec claude_fields() :: [atom()]
  def claude_fields, do: @claude_fields

  @doc """
  Runs `fun` with the calling process attributed to `session_id`, then
  restores the previous attribution, and returns `fun`'s result.
  """
  @spec track(String.t() | nil, (-> result)) :: result when result: term()
  def track(session_id, fun) when is_function(fun, 0) do
    previous = Process.get(@session_key)
    Process.put(@session_key, session_id)

    try do
      fun.()
    after
      if previous, do: Process.put(@session_key, previous), else: Process.delete(@session_key)
    end
  end

  @doc "The session the calling process (or its nearest caller) is attributed to."
  @spec current_session() :: String.t() | nil
  def current_session do
    Process.get(@session_key) ||
      Enum.find_value(Process.get(:"$callers", []), &caller_session/1)
  end

  defp caller_session(pid) when is_pid(pid) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dictionary} -> Keyword.get(dictionary, @session_key)
      nil -> nil
    end
  end

  defp caller_session(_other), do: nil

  @doc """
  Adds one Claude response's `usage` (the Messages API field names, string
  keys) to the current session's counters for `model`. Missing or
  non-integer fields count as 0.
  """
  @spec record_claude(String.t(), map()) :: :ok
  def record_claude(model, usage) when is_binary(model) and is_map(usage) do
    with_session(fn session_id ->
      for field <- @claude_fields do
        increment({session_id, :claude, model, field}, token_count(usage, field))
      end
    end)
  end

  def record_claude(_model, _usage), do: :ok

  defp token_count(usage, field) do
    case Map.get(usage, Atom.to_string(field)) do
      count when is_integer(count) and count > 0 -> count
      _missing -> 0
    end
  end

  @doc "Counts one Jev (TypeSafe System One) request of the current session."
  @spec record_jev_call() :: :ok
  def record_jev_call do
    with_session(&increment({&1, :jev}, 1))
  end

  @report_id ~r/\A[A-Za-z0-9_.:-]{1,128}\z/
  @max_audio_seconds 86_400
  @max_characters 10_000_000
  @max_participant_minutes 14_400

  @doc """
  Validates one voice worker report (string keys): `report_id` (1 to 128 of
  `A-Z a-z 0-9 _ . : -`, the worker job), `deepgram_audio_seconds` and
  `livekit_participant_minutes` (non-negative numbers) and
  `cartesia_characters` (a non-negative integer), each bounded. Other keys
  are ignored.
  """
  @spec voice_report(map()) :: {:ok, String.t(), voice()} | {:error, :invalid_usage}
  def voice_report(%{
        "report_id" => report_id,
        "deepgram_audio_seconds" => seconds,
        "cartesia_characters" => characters,
        "livekit_participant_minutes" => minutes
      })
      when is_binary(report_id) and is_number(seconds) and seconds >= 0 and
             seconds <= @max_audio_seconds and is_integer(characters) and characters >= 0 and
             characters <= @max_characters and is_number(minutes) and minutes >= 0 and
             minutes <= @max_participant_minutes do
    if Regex.match?(@report_id, report_id) do
      {:ok, report_id,
       %{
         deepgram_audio_seconds: seconds * 1.0,
         cartesia_characters: characters,
         livekit_participant_minutes: minutes * 1.0
       }}
    else
      {:error, :invalid_usage}
    end
  end

  def voice_report(_params), do: {:error, :invalid_usage}

  @doc """
  Keeps a voice worker report for `session_id`. Reports are cumulative per
  `report_id` (one worker job): a retried report replaces the earlier one with
  the same id, and the session's voice usage is the sum over its jobs.
  """
  @spec record_voice(String.t(), String.t(), voice()) :: :ok
  def record_voice(session_id, report_id, voice) when is_binary(session_id) do
    if :ets.whereis(@table) != :undefined do
      :ets.insert(@table, {{session_id, :voice, report_id}, voice})
    end

    :ok
  end

  @doc "The usage recorded for `session_id` so far (zeros when nothing was)."
  @spec snapshot(String.t()) :: snapshot()
  def snapshot(session_id) do
    if :ets.whereis(@table) == :undefined do
      empty()
    else
      %{
        empty()
        | claude: claude_totals(session_id),
          jev_calls: lookup({session_id, :jev}, 0),
          voice: voice_totals(session_id)
      }
    end
  end

  defp claude_totals(session_id) do
    @table
    |> :ets.match_object({{session_id, :claude, :_, :_}, :_})
    |> Enum.reduce(%{}, fn {{_id, :claude, model, field}, count}, acc ->
      acc
      |> Map.put_new(model, Map.new(@claude_fields, &{&1, 0}))
      |> put_in([model, field], count)
    end)
  end

  defp voice_totals(session_id) do
    @table
    |> :ets.match_object({{session_id, :voice, :_}, :_})
    |> Enum.reduce(empty().voice, &add_report/2)
  end

  defp add_report({_key, report}, totals),
    do: Map.merge(totals, report, fn _field, total, count -> total + count end)

  @doc "Drops every counter of `session_id`."
  @spec forget(String.t()) :: :ok
  def forget(session_id) do
    if :ets.whereis(@table) != :undefined do
      :ets.match_delete(@table, {{session_id, :_}, :_})
      :ets.match_delete(@table, {{session_id, :_, :_}, :_})
      :ets.match_delete(@table, {{session_id, :_, :_, :_}, :_})
    end

    :ok
  end

  defp empty do
    %{
      claude: %{},
      jev_calls: 0,
      voice: %{
        deepgram_audio_seconds: 0.0,
        cartesia_characters: 0,
        livekit_participant_minutes: 0.0
      }
    }
  end

  defp with_session(fun) do
    case current_session() do
      session_id when is_binary(session_id) ->
        if :ets.whereis(@table) != :undefined, do: fun.(session_id)
        :ok

      _untracked ->
        :ok
    end
  end

  defp increment(key, count) do
    :ets.update_counter(@table, key, count, {key, 0})
  end

  defp lookup(key, default) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> value
      [] -> default
    end
  end
end
