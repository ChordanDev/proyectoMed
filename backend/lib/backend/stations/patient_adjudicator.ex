defmodule Backend.Stations.PatientAdjudicator do
  @moduledoc """
  Adjudicates a candidate patient reply that Jev left undecided (issue #290,
  amending ADR-011 #123).

  A `:low_confidence` Jev verdict (any answer between the thresholds) is not an
  automatic refusal any more: `Backend.Stations.CandidateGate` asks this module
  once per such candidate. A small language model, a separate call from the
  patient generator, reads Jev's undecided labels and scores as evidence and
  answers one of:

    * `:deliver` - the candidate is delivered unchanged;
    * `{:regenerate, fact_ids}` - the gate's single regeneration runs, withholding
      those authored facts;
    * `{:refuse, reason}` - the gate keeps today's behaviour for a low-confidence
      verdict (one regeneration withholding Jev's `undecided_fact_ids`, then a
      refusal).

  Clear Jev verdicts never reach it: `:verified` delivers and
  `:semantic_refusal` refuses or regenerates exactly as before.

  ## Request

  The adapter receives a map with the `candidate_reply`, the
  `latest_learner_message` and the bounded `conversation` (`speaker`, `text`;
  learner text is untrusted data), the `facts` involved (the facts named by an
  undecided label, by `used_fact_ids` or by `not_asked_fact_ids`, each `id`,
  `content`, `disclosure_condition`), the `disclosed_facts` earlier verified
  turns disclosed (issue #286), every `undecided_labels` entry with its score,
  the `not_asked_fact_ids`, the authored `response_rules` and its
  `deadline_ms`.

  ## Hard limits, enforced in code

    * The answer must be exactly `%{"decision" => d, "withheld_fact_ids" => ids}`
      with `d` one of `deliver`, `regenerate`, `refuse` and every id an authored
      fact id of the package; a `deliver` that names facts contradicts itself.
      Anything else is `{:refuse, :malformed_output}`.
    * A `deliver` while Jev reported `not_asked_fact_ids` (an `on_request` fact
      whose `fact_asked` answer is a clear no and whose `fact_stated` answer is
      not) becomes `{:regenerate, not_asked_fact_ids}`, and a `regenerate`
      always withholds them too: the adjudicator never delivers a fact Jev
      clearly found unrequested.
    * A `deliver` is re-checked with
      `Backend.Stations.StationAI.BoundedReply.check_violations/2` (the gate
      already ran it before Jev): a deterministic violation is
      `{:refuse, :denied}`.
    * Without undecided labels there is nothing to adjudicate:
      `{:refuse, :no_evidence}`, and no call is made.

  ## Deadline

  The call has its own deadline, `opts[:adjudicator_deadline_ms]` or the
  `:patient_adjudicator_deadline_ms` setting (default 1500 ms), capped by the
  turn's remaining verification budget (`opts[:deadline_at_monotonic_ms]`)
  minus a margin, so the whole turn stays inside the existing bounded deadline.
  With less than 200 ms left no call is made (`{:refuse, :no_budget}`). The
  deadline is enforced on the adapter task: a late answer is `{:refuse,
  :timeout}`. Errors and crashes are `{:refuse, :error}`, the disabled adapter
  `{:refuse, :disabled}`.

  ## Logging

  Each call logs one `:info` line, `[PatientAdjudicator] adjudication
  outcome=<deliver|regenerate|refuse> latency_ms=<n>`, followed by
  `reason=<reason>` on a refusal or `limit=not_asked` when the hard limit
  changed a `deliver`. It carries no text and no fact id.

  ## Configuration

  The adapter is `opts[:adjudicator_adapter]` or the
  `:patient_adjudicator_adapter` setting
  (`Backend.Stations.PatientAdjudicator.DisabledAdapter` by default;
  `config/runtime.exs` selects the Anthropic adapter with
  `LLM_PROVIDER=anthropic` unless `PATIENT_ADJUDICATOR=off`). It receives
  `opts[:adjudicator_opts]` (default `[]`) as its options.
  """

  require Logger

  alias Backend.Stations.JevDecision
  alias Backend.Stations.StationAI.BoundedReply

  @default_deadline_ms 1_500
  @budget_margin_ms 100
  @min_budget_ms 200
  @decisions ~w(deliver regenerate refuse)

  @type outcome :: :deliver | {:regenerate, [String.t()]} | {:refuse, atom()}

  @typedoc "What the adapter is asked to decide (see the moduledoc)."
  @type request :: %{
          candidate_reply: String.t(),
          latest_learner_message: String.t(),
          conversation: [%{speaker: String.t(), text: String.t()}],
          facts: [%{id: String.t(), content: String.t(), disclosure_condition: String.t()}],
          disclosed_facts: [%{id: String.t(), content: String.t()}],
          undecided_labels: [JevDecision.undecided_label()],
          not_asked_fact_ids: [String.t()],
          response_rules: [String.t()],
          deadline_ms: pos_integer()
        }

  @doc "Decides one undecided candidate; returns the provider's raw answer."
  @callback adjudicate(request(), keyword()) :: {:ok, term()} | {:error, term()}

  @doc """
  Adjudicates `candidate` given Jev's low-confidence `decision`, the `package`
  and the `conversation` the gate verified it against.
  """
  @spec adjudicate(map(), String.t(), map(), list(), keyword()) :: outcome()
  def adjudicate(decision, candidate, package, conversation, opts \\ []) do
    started_at = JevDecision.monotonic_now_ms()

    outcome =
      with {:ok, labels} <- labels(decision),
           {:ok, budget_ms} <- budget(opts) do
        not_asked = fact_ids(decision, :not_asked_fact_ids)

        decision
        |> build_request(labels, not_asked, candidate, package, conversation, opts)
        |> Map.put(:deadline_ms, budget_ms)
        |> run(adapter(opts), Keyword.get(opts, :adjudicator_opts, []), budget_ms)
        |> validate(package)
        |> enforce_limits(not_asked, candidate, package)
      end

    log_outcome(outcome, JevDecision.monotonic_now_ms() - started_at)
    strip_limit(outcome)
  end

  @doc "The adjudicator adapter from options or application configuration."
  @spec adapter(keyword()) :: module()
  def adapter(opts \\ []) do
    opts[:adjudicator_adapter] ||
      Application.get_env(:backend, :patient_adjudicator_adapter, __MODULE__.DisabledAdapter)
  end

  @doc "The adjudicator's own deadline in milliseconds, before the turn cap."
  @spec deadline_ms(keyword()) :: pos_integer()
  def deadline_ms(opts \\ []) do
    opts[:adjudicator_deadline_ms] ||
      Application.get_env(:backend, :patient_adjudicator_deadline_ms, @default_deadline_ms)
  end

  # ============================================================================
  # Request
  # ============================================================================

  defp labels(decision) do
    case Map.get(decision, :undecided_labels) do
      [_ | _] = labels -> {:ok, labels}
      _ -> {:refuse, :no_evidence}
    end
  end

  defp budget(opts) do
    remaining =
      case opts[:deadline_at_monotonic_ms] do
        deadline_at when is_integer(deadline_at) ->
          JevDecision.remaining_budget_ms(deadline_at) - @budget_margin_ms

        _none ->
          deadline_ms(opts)
      end

    budget_ms = min(deadline_ms(opts), remaining)

    if budget_ms >= @min_budget_ms, do: {:ok, budget_ms}, else: {:refuse, :no_budget}
  end

  defp fact_ids(decision, key) do
    case Map.get(decision, key) do
      ids when is_list(ids) -> Enum.filter(ids, &is_binary/1)
      _ -> []
    end
  end

  defp build_request(decision, labels, not_asked, candidate, package, conversation, opts) do
    facts = package_facts(package)

    involved =
      Enum.uniq(label_fact_ids(labels) ++ fact_ids(decision, :used_fact_ids) ++ not_asked)

    disclosed = opts |> Keyword.get(:disclosed_fact_ids, []) |> List.wrap()
    turns = conversation |> List.wrap() |> Enum.map(&turn/1)

    %{
      candidate_reply: to_string(candidate),
      latest_learner_message:
        turns
        |> Enum.filter(&(&1.speaker == "learner"))
        |> List.last(%{text: ""})
        |> Map.get(:text),
      conversation: Enum.take(turns, -JevDecision.max_context_turns()),
      facts:
        for fact <- facts, fact.id in involved do
          Map.take(fact, [:id, :content, :disclosure_condition])
        end,
      disclosed_facts:
        for(fact <- facts, fact.id in disclosed, do: Map.take(fact, [:id, :content])),
      undecided_labels: labels,
      not_asked_fact_ids: not_asked,
      response_rules: response_rules(package)
    }
  end

  defp label_fact_ids(labels) do
    for %{fact_id: id} when is_binary(id) <- labels, do: id
  end

  defp package_facts(package) do
    for fact when is_map(fact) <- field(package, "revealable_facts"),
        id = field_value(fact, "id"),
        is_binary(id) do
      %{
        id: id,
        content: to_string(field_value(fact, "content") || ""),
        disclosure_condition: to_string(field_value(fact, "disclosure_condition") || "")
      }
    end
  end

  defp response_rules(package) do
    for rule when is_map(rule) <- field(package, "response_rules"),
        instruction = field_value(rule, "instruction"),
        is_binary(instruction) and String.trim(instruction) != "",
        do: instruction
  end

  defp field(map, key), do: List.wrap(field_value(map, key))

  defp field_value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, String.to_existing_atom(key))

  defp field_value(_map, _key), do: nil

  @patient_roles [:patient, "patient", :assistant, "assistant"]

  defp turn(item) when is_map(item) do
    role = Map.get(item, :role) || Map.get(item, "role")
    speaker = if role in @patient_roles, do: "patient", else: "learner"
    %{speaker: speaker, text: to_string(Map.get(item, :text) || Map.get(item, "text") || "")}
  end

  defp turn(_item), do: %{speaker: "learner", text: ""}

  # ============================================================================
  # Execution
  # ============================================================================

  defp run(request, adapter, adapter_opts, budget_ms) do
    task =
      Task.async(fn ->
        try do
          adapter.adjudicate(request, adapter_opts)
        rescue
          _error -> {:error, :adapter_crashed}
        catch
          :exit, _reason -> {:error, :task_exit}
          :throw, _value -> {:error, :adapter_threw}
        end
      end)

    case Task.yield(task, budget_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
      {:exit, _reason} -> {:error, :task_exit}
    end
  end

  # ============================================================================
  # Validation & hard limits
  # ============================================================================

  defp validate({:ok, %{} = answer}, package) when map_size(answer) == 2 do
    decision = Map.get(answer, "decision")
    ids = Map.get(answer, "withheld_fact_ids")
    known = MapSet.new(package_facts(package), & &1.id)

    cond do
      decision not in @decisions or not is_list(ids) ->
        {:refuse, :malformed_output}

      not Enum.all?(ids, &(is_binary(&1) and MapSet.member?(known, &1))) ->
        {:refuse, :malformed_output}

      decision == "deliver" and ids != [] ->
        {:refuse, :malformed_output}

      decision == "deliver" ->
        :deliver

      decision == "regenerate" ->
        {:regenerate, Enum.uniq(ids)}

      true ->
        {:refuse, :adjudicator}
    end
  end

  defp validate({:ok, _other}, _package), do: {:refuse, :malformed_output}
  defp validate({:error, :disabled}, _package), do: {:refuse, :disabled}
  defp validate({:error, :timeout}, _package), do: {:refuse, :timeout}
  defp validate({:error, :malformed_output}, _package), do: {:refuse, :malformed_output}
  defp validate({:error, _reason}, _package), do: {:refuse, :error}
  defp validate(_other, _package), do: {:refuse, :malformed_output}

  defp enforce_limits(:deliver, [_ | _] = not_asked, _candidate, _package),
    do: {:regenerate, not_asked, :not_asked}

  defp enforce_limits(:deliver, [], candidate, package) do
    case BoundedReply.check_violations(candidate, package) do
      :ok -> :deliver
      _violation -> {:refuse, :denied}
    end
  end

  defp enforce_limits({:regenerate, ids}, not_asked, _candidate, _package),
    do: {:regenerate, Enum.uniq(ids ++ not_asked)}

  defp enforce_limits(outcome, _not_asked, _candidate, _package), do: outcome

  defp strip_limit({:regenerate, ids, _limit}), do: {:regenerate, ids}
  defp strip_limit(outcome), do: outcome

  # ============================================================================
  # Logging
  # ============================================================================

  defp log_outcome(outcome, latency_ms) do
    {name, detail} =
      case outcome do
        :deliver -> {"deliver", ""}
        {:regenerate, _ids} -> {"regenerate", ""}
        {:regenerate, _ids, limit} -> {"regenerate", " limit=#{limit}"}
        {:refuse, reason} -> {"refuse", " reason=#{reason}"}
      end

    Logger.info(
      "[PatientAdjudicator] adjudication outcome=#{name} latency_ms=#{latency_ms}#{detail}"
    )
  end
end
