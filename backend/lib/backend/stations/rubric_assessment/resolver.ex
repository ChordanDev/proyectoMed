defmodule Backend.Stations.RubricAssessment.Resolver do
  @moduledoc """
  Resolves the rubric actions Jev left undecided (issue #214).

  After Jev's rubric batch, the resolver asks a second decision provider (an
  LLM behind this behaviour) about the authored actions Jev classified
  `"uncertain"`, and nothing else. Jev's clear `"performed"` and
  `"not_performed"` answers are final.

  Each criterion with at least one undecided action gets its own request
  (issue #301), carrying that criterion with every authored action, Jev's
  classification and the identifiers of the actions the provider may decide,
  plus the learner-only evidence pool (`id`, `text`). The requests run
  concurrently (at most `:rubric_resolver_max_concurrency`, default 6, at a
  time) under one overall deadline. The provider answers one decision per
  action, keyed by criterion and action identifier; a decision about another
  criterion than the one asked is ignored.

  The answer is merged in code, never trusted:

    * a decision for an action Jev decided clearly, or for an identifier the
      request did not offer, is ignored;
    * an action decided more than once is ignored;
    * `"performed"` needs at least one citation and every citation must pass
      `Backend.Stations.RubricAssessment.Evidence.validate/3` as learner
      evidence for the criterion's requirement; otherwise the action stays
      `"uncertain"`;
    * a citation must also be related to the action (issue #243): when Jev
      left the action uncertain with candidate items in its `evidence_ids`
      (the items it could neither confirm nor rule out for that action), a
      citation outside them is dropped, and an action left with no related
      citation stays `"uncertain"`. An unrelated citation alone never credits
      an action. An undecided action without candidates accepts any valid
      citation;
    * `"not_performed"` is taken without evidence, and `"uncertain"` changes
      nothing. The rubric assessment never lets such answers alone ground a
      zero-point level (`Backend.Stations.RubricAssessment`, step 4).

  A technical failure (an error, malformed output, a raise or the deadline)
  never invalidates the attempt: the undecided actions of that criterion stay
  `"uncertain"`, and every other criterion keeps the decisions it got. Each
  criterion's outcome and latency are logged (criterion id, counts and the
  failure's name only, never transcript text).

  Candidates are consumed here and never reported: every action still
  `"uncertain"` after this step carries no evidence, whatever the outcome.
  The resolver has its own deadline, `:rubric_resolver_deadline_ms` (default
  10000 ms), independent of Jev's.

  The adapter is `opts[:resolver_adapter]` or the `:rubric_resolver_adapter`
  application setting, `Backend.Stations.RubricAssessment.Resolver.DisabledAdapter`
  by default.
  It receives `opts[:resolver_opts]` (default `[]`) as its options, so the
  options of the Jev adapter never reach it.
  """

  require Logger

  alias Backend.Stations.RubricAssessment.Evidence

  @uncertain "uncertain"
  @performed "performed"
  @not_performed "not_performed"
  @classes [@performed, @not_performed, @uncertain]
  @default_deadline_ms 10_000
  @default_max_concurrency 6

  @typedoc "An authored action with Jev's classification."
  @type action :: %{id: String.t(), description: String.t(), classification: String.t()}

  @typedoc "A criterion with at least one action the provider may decide."
  @type criterion :: %{
          id: String.t(),
          description: String.t(),
          actions: [action()],
          decidable_action_ids: [String.t()]
        }

  @typedoc "A learner evidence item offered to the provider."
  @type evidence_item :: %{id: String.t(), text: String.t()}

  @typedoc "What the provider is asked to decide."
  @type request :: %{criteria: [criterion()], evidence_pool: [evidence_item()]}

  @typedoc "The provider's decision on one action."
  @type decision :: %{
          criterion_id: String.t(),
          id: String.t(),
          classification: String.t(),
          evidence_ids: [String.t()]
        }

  @typedoc "A criterion the rubric assessment asked Jev about."
  @type asked :: %{id: String.t(), criterion: map(), requirement: Evidence.requirement()}

  @doc """
  Decides the actions listed in each criterion's `decidable_action_ids`.
  Returns every decision under `:actions`, or an error.
  """
  @callback resolve(request(), keyword()) :: {:ok, %{actions: [decision()]}} | {:error, term()}

  @doc """
  Returns the batch decisions (indexed by criterion id) with the undecided
  actions the resolver decided validly merged in. The resolver is not called
  when no action is undecided.
  """
  @spec resolve(%{optional(String.t()) => map()}, [asked()], Evidence.pool(), keyword()) ::
          %{optional(String.t()) => map()}
  def resolve(decisions, asked, pool, opts) when is_map(decisions) and is_list(opts) do
    asked = Enum.filter(asked, &(decidable_ids(decisions[&1.id]) != []))

    decisions
    |> decide(asked, pool, opts)
    |> without_candidates()
  end

  defp decide(decisions, [], _pool, _opts), do: decisions

  # One request per criterion, run concurrently under one overall deadline.
  # A criterion whose request fails or misses the deadline keeps its undecided
  # actions; every other criterion keeps the decisions it got.
  defp decide(decisions, asked, pool, opts) do
    evidence_pool = learner_pool(pool)

    requests =
      for %{id: id} = entry <- asked do
        {id, %{criteria: [criterion(entry, decisions[id])], evidence_pool: evidence_pool}}
      end

    outcomes = run_all(adapter(opts), requests, opts)

    Enum.reduce(asked, decisions, fn %{id: id} = entry, acc ->
      case Map.fetch!(outcomes, id) do
        {:ok, resolved} ->
          merge(acc, [entry], pool, Enum.filter(resolved, &(&1.criterion_id == id)))

        {:error, _reason} ->
          acc
      end
    end)
  end

  @doc "Resolves the resolver adapter from options or application configuration."
  @spec adapter(keyword()) :: module()
  def adapter(opts \\ []) do
    opts[:resolver_adapter] ||
      Application.get_env(:backend, :rubric_resolver_adapter, __MODULE__.DisabledAdapter)
  end

  @doc "Returns the resolver deadline in milliseconds from options or configuration."
  @spec deadline_ms(keyword()) :: pos_integer()
  def deadline_ms(opts \\ []) do
    opts[:rubric_resolver_deadline_ms] ||
      Application.get_env(:backend, :rubric_resolver_deadline_ms, @default_deadline_ms)
  end

  # ============================================================================
  # Request
  # ============================================================================

  defp decidable_ids(%{actions: actions}) when is_list(actions) do
    for %{classification: @uncertain, id: id} <- actions, do: id
  end

  defp decidable_ids(_decision), do: []

  defp criterion(%{id: id, criterion: criterion}, decision) do
    descriptions =
      for %{"id" => action_id} = action <- list(criterion, "actions"), into: %{} do
        {action_id, to_string(action["description"])}
      end

    %{
      id: id,
      description: to_string(criterion["description"]),
      actions:
        for %{id: action_id, classification: classification} <- decision.actions do
          %{
            id: action_id,
            description: Map.get(descriptions, action_id, ""),
            classification: classification
          }
        end,
      decidable_action_ids: decidable_ids(decision)
    }
  end

  # Learner turns and verified Impressos events that released something: the
  # only items a performed action may cite under any requirement.
  defp learner_pool(pool) do
    for item <- pool, match?({:ok, _}, Evidence.validate(pool, [item.id], :any)) do
      %{id: item.id, text: item.text}
    end
  end

  # ============================================================================
  # Adapter execution
  # ============================================================================

  defp run_all(adapter, requests, opts) do
    adapter_opts = Keyword.get(opts, :resolver_opts, [])
    deadline_ms = deadline_ms(opts)
    started_at = System.monotonic_time(:millisecond)
    caller = self()
    ref = make_ref()

    # The runner owns every request task: killing it at the deadline takes the
    # requests still in flight with it.
    runner =
      Task.async(fn ->
        requests
        |> Task.async_stream(
          fn {id, request} ->
            send(caller, {ref, id, call(adapter, request, adapter_opts), now() - started_at})
          end,
          max_concurrency: max_concurrency(opts),
          ordered: false,
          timeout: :infinity
        )
        |> Stream.run()
      end)

    collected = collect(ref, length(requests), started_at + deadline_ms, %{})
    Task.shutdown(runner, :brutal_kill)
    flush(ref)

    elapsed_ms = now() - started_at

    outcomes =
      Map.new(requests, fn {id, request} ->
        {result, latency_ms} = Map.get(collected, id, {{:error, :timeout}, elapsed_ms})
        {id, log_outcome(id, request, validate_output(result), latency_ms)}
      end)

    answered = Enum.count(outcomes, &match?({_id, {:ok, _}}, &1))

    Logger.info(
      "Rubric resolver finished in #{elapsed_ms} ms: " <>
        "#{answered} of #{length(requests)} criteria answered"
    )

    outcomes
  end

  defp collect(_ref, 0, _deadline_at, acc), do: acc

  defp collect(ref, pending, deadline_at, acc) do
    receive do
      {^ref, id, result, latency_ms} ->
        collect(ref, pending - 1, deadline_at, Map.put(acc, id, {result, latency_ms}))
    after
      max(deadline_at - now(), 0) -> acc
    end
  end

  defp flush(ref) do
    receive do
      {^ref, _id, _result, _latency_ms} -> flush(ref)
    after
      0 -> :ok
    end
  end

  defp call(adapter, request, adapter_opts) do
    adapter.resolve(request, adapter_opts)
  rescue
    _error -> {:error, :adapter_crashed}
  catch
    :exit, _reason -> {:error, :task_exit}
    :throw, _value -> {:error, :adapter_threw}
  end

  defp max_concurrency(opts) do
    opts[:rubric_resolver_max_concurrency] ||
      Application.get_env(
        :backend,
        :rubric_resolver_max_concurrency,
        @default_max_concurrency
      )
  end

  defp now, do: System.monotonic_time(:millisecond)

  # Only the criterion id, counts, the reason's name and latency are logged,
  # never content.
  defp log_outcome(id, request, {:ok, actions} = ok, latency_ms) do
    Logger.info(
      "Rubric resolver criterion #{id} answered in #{latency_ms} ms: " <>
        "#{length(actions)} decisions for #{decidable_count(request)} undecided actions"
    )

    ok
  end

  defp log_outcome(id, _request, {:error, reason} = error, latency_ms) do
    Logger.warning(
      "Rubric resolver left criterion #{id} uncertain after #{latency_ms} ms: #{tag(reason)}"
    )

    error
  end

  defp decidable_count(%{criteria: criteria}) do
    Enum.reduce(criteria, 0, &(length(&1.decidable_action_ids) + &2))
  end

  defp validate_output({:ok, %{actions: actions}}) when is_list(actions) do
    if Enum.all?(actions, &valid_decision?/1),
      do: {:ok, actions},
      else: {:error, :malformed_output}
  end

  defp validate_output({:error, _reason} = error), do: error
  defp validate_output(_other), do: {:error, :malformed_output}

  defp valid_decision?(%{
         criterion_id: criterion_id,
         id: id,
         classification: classification,
         evidence_ids: evidence_ids
       }) do
    is_binary(criterion_id) and is_binary(id) and classification in @classes and
      is_list(evidence_ids) and Enum.all?(evidence_ids, &is_binary/1)
  end

  defp valid_decision?(_decision), do: false

  # Only the reason's name is logged, never content.
  defp tag(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp tag(reason) when is_tuple(reason) and is_atom(elem(reason, 0)), do: tag(elem(reason, 0))
  defp tag(_reason), do: "unknown"

  # ============================================================================
  # Merge
  # ============================================================================

  defp merge(decisions, asked, pool, resolved) do
    by_key = unique_by_key(resolved)

    Enum.reduce(asked, decisions, fn %{id: id, requirement: requirement}, acc ->
      Map.update!(acc, id, fn decision ->
        actions = Enum.map(decision.actions, &merge_action(&1, id, by_key, pool, requirement))
        %{decision | actions: actions}
      end)
    end)
  end

  # An action decided more than once is ambiguous and is dropped.
  defp unique_by_key(resolved) do
    resolved
    |> Enum.group_by(&{&1.criterion_id, &1.id})
    |> Enum.flat_map(fn
      {key, [decision]} -> [{key, decision}]
      {_key, _duplicates} -> []
    end)
    |> Map.new()
  end

  defp merge_action(
         %{classification: @uncertain} = action,
         criterion_id,
         by_key,
         pool,
         requirement
       ) do
    case Map.fetch(by_key, {criterion_id, action.id}) do
      {:ok, decision} -> apply_decision(action, decision, pool, requirement)
      :error -> action
    end
  end

  defp merge_action(action, _criterion_id, _by_key, _pool, _requirement), do: action

  defp apply_decision(action, %{classification: @not_performed}, _pool, _requirement) do
    %{action | classification: @not_performed, evidence_ids: []}
  end

  defp apply_decision(
         action,
         %{classification: @performed, evidence_ids: [_ | _] = ids},
         pool,
         requirement
       ) do
    with {:ok, evidence} <- Evidence.validate(pool, ids, requirement),
         [_ | _] = related <- related(Evidence.ids(evidence), action.evidence_ids) do
      %{action | classification: @performed, evidence_ids: related}
    else
      _invalid_or_unrelated -> action
    end
  end

  defp apply_decision(action, _uncertain_or_unsupported, _pool, _requirement), do: action

  # The cited ids among the action's candidates, in pool order; every cited id
  # when Jev offered no candidates.
  defp related(cited, []), do: cited
  defp related(cited, candidates), do: Enum.filter(cited, &(&1 in candidates))

  defp without_candidates(decisions) do
    Map.new(decisions, fn
      {id, %{actions: actions} = decision} when is_list(actions) ->
        {id, %{decision | actions: Enum.map(actions, &without_candidate/1)}}

      entry ->
        entry
    end)
  end

  defp without_candidate(%{classification: @uncertain} = action),
    do: %{action | evidence_ids: []}

  defp without_candidate(action), do: action

  defp list(map, key) do
    case Map.get(map, key) do
      entries when is_list(entries) -> entries
      _missing -> []
    end
  end
end
