defmodule Backend.Stations.StationAI.SentenceStream do
  @moduledoc """
  Generates a patient reply as a stream and hands it over one verified sentence
  at a time (issue #271, real-time voice).

  Generation runs in a linked task that sends each text piece to the caller;
  the caller splits the pieces into sentences (`Backend.Stations.StationAI.Sentences`)
  and verifies each complete sentence while the task keeps generating, so the
  next sentence is generated while this one is verified and spoken.

  ## Callbacks (`run/1` options)

    * `:generate` - `fn on_text -> {:ok, text} | {:error, reason} end`, called in
      the task; `on_text` takes each piece as it is generated.
    * `:verify` - `fn candidate, index -> :verified | {:verified, fact_ids} |
      {:regenerated, text} | {:regenerated, text, fact_ids} | {:refused, reason} |
      {:error, reason} end`. `candidate` is the whole reply so far (the verified
      sentences plus the new one, trimmed), so the verifier judges the new
      sentence with everything already said. `{:regenerated, text}` is a whole
      replacement reply that is already verified. `fact_ids` are the facts the
      verification found stated (issue #286); without them it is `[]`.
    * `:deliver` - `fn sentence, index, acc -> {:cont, acc} | {:halt, acc} end`,
      called once per verified sentence, in order, with the raw sentence.
    * `:acc` - the initial accumulator; `:idle_timeout_ms` - the longest wait for
      the next piece (default #{20_000} ms).
    * `:gate` - optional `fn -> :open | {:closed, reason} end`, a decision taken
      while the generation already runs (issue #294, the turn addressee). It is
      called exactly once: before the first sentence is verified, or when the
      stream stops before any sentence was. `{:closed, reason}` stops the reply
      with outcome `{:closed, reason}` and stops the generation: nothing of it is
      verified, delivered or logged. Without a gate the stream is open.

  ## Outcome

  `run/1` returns `%{outcome: outcome, delivered: sentences, fact_ids: ids, acc: acc}`
  where `delivered` are the raw verified sentences `deliver` accepted, in order,
  `fact_ids` the union, in order, of the fact ids of the verifications whose
  sentences were all accepted, and
  `outcome` is `:complete`, `{:refused, reason}` (the first refused sentence
  stops the reply), `{:error, reason}` (generation or verification failed) or
  `:halted` (`deliver` halted) or `{:closed, reason}` (the gate closed, nothing
  was verified or delivered). Text after the stopping point, including an
  unfinished sentence, is discarded and never handed over.

  ## Logs

  One `:info` line per verified-or-stopped sentence,
  `[Stations] voice_sentence index=<i> generation_ms=<ms> verification_ms=<ms> outcome=<o>`,
  where `generation_ms` is the time since the previous sentence was complete
  (or since generation started). Never the text.
  """

  require Logger

  alias Backend.Stations.StationAI.Sentences

  @default_idle_timeout_ms 20_000

  @type outcome ::
          :complete | :halted | {:refused, term()} | {:error, term()} | {:closed, term()}

  @spec run(keyword()) :: %{
          outcome: outcome(),
          delivered: [String.t()],
          fact_ids: [String.t()],
          acc: term()
        }
  def run(opts) do
    generate = Keyword.fetch!(opts, :generate)
    parent = self()
    ref = make_ref()

    task =
      Task.async(fn ->
        try do
          generate.(fn text when is_binary(text) -> send(parent, {ref, :text, text}) end)
        rescue
          error -> {:error, {:generator_crash, error.__struct__}}
        catch
          kind, _reason -> {:error, {:generator_crash, kind}}
        end
      end)

    state = %{
      task: task,
      ref: ref,
      verify: Keyword.fetch!(opts, :verify),
      deliver: Keyword.fetch!(opts, :deliver),
      acc: Keyword.get(opts, :acc),
      gate: Keyword.get(opts, :gate),
      idle_timeout_ms: Keyword.get(opts, :idle_timeout_ms, @default_idle_timeout_ms),
      buffer: "",
      prefix: "",
      delivered: [],
      fact_ids: [],
      index: 0,
      segment_started: now_ms()
    }

    {outcome, state} = state |> loop() |> close_gate()
    stop_generation(state)

    %{
      outcome: outcome,
      delivered: Enum.reverse(state.delivered),
      fact_ids: state.fact_ids,
      acc: state.acc
    }
  end

  defp loop(%{task: %{ref: task_ref}, ref: ref} = state) do
    receive do
      {^ref, :text, text} ->
        {sentences, rest} = Sentences.split(state.buffer <> text)

        case handle_sentences(sentences, %{state | buffer: rest}) do
          {:cont, state} -> loop(state)
          {:stop, outcome, state} -> {outcome, state}
        end

      {^task_ref, result} ->
        Process.demonitor(task_ref, [:flush])
        state = %{state | task: nil}
        finish(result, state)

      {:DOWN, ^task_ref, :process, _pid, _reason} ->
        {{:error, :generator_crash}, %{state | task: nil}}
    after
      state.idle_timeout_ms -> {{:error, :timeout}, state}
    end
  end

  # The generation ended: its unfinished tail is the last sentence. A failed
  # generation discards the tail, which was never verified.
  defp finish({:ok, _reply}, state) do
    tail = if String.trim(state.buffer) == "", do: [], else: [state.buffer]

    case handle_sentences(tail, %{state | buffer: ""}) do
      {:cont, state} -> {:complete, state}
      {:stop, outcome, state} -> {outcome, state}
    end
  end

  defp finish({:error, reason}, state), do: {{:error, reason}, state}
  defp finish(other, state), do: {{:error, {:invalid_generator_output, other}}, state}

  defp handle_sentences([], state), do: {:cont, state}

  defp handle_sentences([sentence | rest], state) do
    case handle_sentence(sentence, state) do
      {:cont, state} -> handle_sentences(rest, state)
      {:stop, _outcome, _state} = stop -> stop
    end
  end

  defp handle_sentence(sentence, state) do
    case pass_gate(state) do
      {:open, state} -> verify_sentence(sentence, state)
      {:closed, reason, state} -> {:stop, {:closed, reason}, state}
    end
  end

  # A stream that stopped before its first sentence still takes the gate's
  # decision, which wins over the stream's own outcome when it closes.
  defp close_gate({outcome, state}) do
    case pass_gate(state) do
      {:open, state} -> {outcome, state}
      {:closed, reason, state} -> {{:closed, reason}, state}
    end
  end

  defp pass_gate(%{gate: nil} = state), do: {:open, state}

  defp pass_gate(%{gate: gate} = state) do
    state = %{state | gate: nil}

    case gate.() do
      {:closed, reason} -> {:closed, reason, state}
      _open -> {:open, state}
    end
  end

  defp verify_sentence(sentence, state) do
    found_at = now_ms()
    generation_ms = found_at - state.segment_started
    candidate = String.trim(state.prefix <> sentence)
    result = state.verify.(candidate, state.index)
    log(state.index, generation_ms, now_ms() - found_at, result)
    state = %{state | segment_started: found_at}

    case result do
      :verified -> deliver(sentence, state, [])
      {:verified, fact_ids} -> deliver(sentence, state, fact_ids)
      {:regenerated, text} -> deliver_regenerated(text, state, [])
      {:regenerated, text, fact_ids} -> deliver_regenerated(text, state, fact_ids)
      {:refused, reason} -> {:stop, {:refused, reason}, state}
      {:error, reason} -> {:stop, {:error, reason}, state}
    end
  end

  defp deliver(sentence, state, fact_ids) do
    with {:cont, state} <- deliver(sentence, state) do
      {:cont, add_fact_ids(state, fact_ids)}
    end
  end

  defp add_fact_ids(state, fact_ids),
    do: %{state | fact_ids: Enum.uniq(state.fact_ids ++ List.wrap(fact_ids))}

  defp deliver(sentence, state) do
    case state.deliver.(sentence, state.index, state.acc) do
      {:cont, acc} ->
        {:cont,
         %{
           state
           | acc: acc,
             prefix: state.prefix <> sentence,
             delivered: [sentence | state.delivered],
             index: state.index + 1
         }}

      {:halt, acc} ->
        {:stop, :halted, %{state | acc: acc}}
    end
  end

  # The whole regenerated reply is already verified: the stream it replaces
  # stops and the regeneration is handed over sentence by sentence.
  defp deliver_regenerated(text, state, fact_ids) do
    stop_generation(state)
    {sentences, rest} = Sentences.split(text)
    pieces = if String.trim(rest) == "", do: sentences, else: sentences ++ [rest]

    Enum.reduce_while(pieces, {:stop, :complete, %{state | task: nil}}, fn piece,
                                                                           {:stop, _, state} ->
      case deliver(piece, state) do
        {:cont, state} -> {:cont, {:stop, :complete, state}}
        {:stop, _outcome, _state} = stop -> {:halt, stop}
      end
    end)
    |> case do
      {:stop, :complete, state} -> {:stop, :complete, add_fact_ids(state, fact_ids)}
      stop -> stop
    end
  end

  defp stop_generation(%{task: nil}), do: :ok

  defp stop_generation(%{task: task, ref: ref}) do
    Task.shutdown(task, :brutal_kill)
    flush(ref)
  end

  defp flush(ref) do
    receive do
      {^ref, :text, _text} -> flush(ref)
    after
      0 -> :ok
    end
  end

  defp log(index, generation_ms, verification_ms, result) do
    Logger.info(
      "[Stations] voice_sentence index=#{index} generation_ms=#{generation_ms}" <>
        " verification_ms=#{verification_ms} outcome=#{outcome_name(result)}"
    )
  end

  defp outcome_name(:verified), do: "verified"
  defp outcome_name({:verified, _fact_ids}), do: "verified"
  defp outcome_name({:regenerated, _text}), do: "regenerated"
  defp outcome_name({:regenerated, _text, _fact_ids}), do: "regenerated"
  defp outcome_name({:refused, _reason}), do: "refused"
  defp outcome_name({:error, _reason}), do: "error"

  defp now_ms, do: System.monotonic_time(:millisecond)
end
