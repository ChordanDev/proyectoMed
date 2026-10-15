defmodule Backend.Stations.RubricAssessment.Resolver do
  @moduledoc """
  Resolves the rubric actions Jev left undecided (issue #214).

  After Jev's rubric batch, the resolver asks a second decision provider (an
  LLM behind this behaviour) about the authored actions Jev classified
  `"uncertain"`, and nothing else. Jev's clear `"performed"` and
  `"not_performed"` answers are final.

  The request carries, per criterion with at least one undecided action, every
  authored action with Jev's classification and the identifiers of the actions
  the provider may decide, plus one learner-only evidence pool (`id`, `text`).
  The provider answers one decision per action, keyed by criterion and action
  identifier.

  The answer is merged in code, never trusted:

    * a decision for an action Jev decided clearly, or for an identifier the
      request did not offer, is ignored;
    * an action decided more than once is ignored;
    * `"performed"` needs at least one citation and every citation must pass
      `Backend.Stations.RubricAssessment.Evidence.validate/3` as learner
      evidence for the criterion's requirement; otherwise the action stays
      `"uncertain"`;
    * `"not_performed"` is taken without evidence, and `"uncertain"` changes
      nothing. The rubric assessment never lets such answers alone ground a
      zero-point level (`Backend.Stations.RubricAssessment`, step 4).

  A technical failure (an error, malformed output, a raise or the deadline)
  never invalidates the attempt: every undecided action stays `"uncertain"`.
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

    if asked == [] do
      decisions
    else
      request = %{
        criteria: Enum.map(asked, &criterion(&1, decisions[&1.id])),
        evidence_pool: learner_pool(pool)
      }

      case run(adapter(opts), request, opts) do
        {:ok, resolved} -> merge(decisions, asked, pool, resolved)
        {:error, _reason} -> decisions
      end
    end
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

  defp run(adapter, request, opts) do
    adapter_opts = Keyword.get(opts, :resolver_opts, [])
    deadline_ms = deadline_ms(opts)
    started_at = System.monotonic_time(:millisecond)

    task =
      Task.async(fn ->
        try do
          adapter.resolve(request, adapter_opts)
        rescue
          _error -> {:error, :adapter_crashed}
        catch
          :exit, _reason -> {:error, :task_exit}
          :throw, _value -> {:error, :adapter_threw}
        end
      end)

    result =
      case Task.yield(task, deadline_ms) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} -> result
        nil -> {:error, :timeout}
        {:exit, _reason} -> {:error, :task_exit}
      end

    elapsed_ms = System.monotonic_time(:millisecond) - started_at

    case validate_output(result) do
      {:ok, actions} = ok ->
        Logger.info(
          "Rubric resolver answered in #{elapsed_ms} ms: " <>
            "#{length(actions)} decisions for #{decidable_count(request)} undecided actions"
        )

        ok

      {:error, reason} = error ->
        Logger.warning(
          "Rubric resolver left undecided actions uncertain after #{elapsed_ms} ms: #{tag(reason)}"
        )

        error
    end
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
    case Evidence.validate(pool, ids, requirement) do
      {:ok, evidence} ->
        %{action | classification: @performed, evidence_ids: Evidence.ids(evidence)}

      {:error, _rejection} ->
        action
    end
  end

  defp apply_decision(action, _uncertain_or_unsupported, _pool, _requirement), do: action

  defp list(map, key) do
    case Map.get(map, key) do
      entries when is_list(entries) -> entries
      _missing -> []
    end
  end
end
