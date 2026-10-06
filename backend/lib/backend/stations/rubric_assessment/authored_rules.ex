defmodule Backend.Stations.RubricAssessment.AuthoredRules do
  @moduledoc """
  Authored per-criterion rules over the sub-action decisions of a criterion
  Jev assessed (issue #128, ADR-012).

  `decide_level/3` applies the rules in this order:

    1. A sub-action classified `"uncertain"`, or `"performed"` without
       validated learner evidence, leaves the criterion uncertain.
    2. A performed `forbidden` action scores the zero-point level.
    3. A `mandatory` action that was not performed scores the zero-point level.
    4. With authored thresholds (`levels[].min_actions`), the level is the
       highest one whose threshold is at most the number of performed
       non-forbidden actions, capped by `count_cap`. The count decides; Jev's
       criterion-level class does not.
    5. Without thresholds, Jev's level stands.

  Rule 1 looks only at actions that can change the level: every action when
  thresholds are authored, otherwise the `mandatory` and `forbidden` ones. A
  criterion that authors none of these fields therefore keeps Jev's level
  whatever its sub-actions say.

  The module is pure. Sub-action evidence arrives already validated against
  the evidence pool, so an empty `evidence_ids` list is the only way a
  performed action can lack evidence. Points are integer eighths
  (`Backend.Stations.RubricAssessment.Points`); `first_n` and the `task_order`
  rule are not applied here.
  """

  alias Backend.Stations.RubricAssessment.Points

  @performed "performed"
  @uncertain "uncertain"
  @mandatory "mandatory"
  @forbidden "forbidden"

  @typedoc "An authored level as its label and exact points."
  @type level :: %{label: String.t(), points: Points.t()}

  @typedoc "The decision of one authored action, with validated evidence."
  @type sub_action :: %{id: String.t(), classification: String.t(), evidence_ids: [String.t()]}

  @typedoc "Why a sub-action leaves its criterion uncertain."
  @type uncertainty ::
          {:uncertain_sub_action, String.t()} | {:unsupported_sub_action, String.t()}

  @typedoc "Why the rule fields of a criterion cannot be applied."
  @type authoring_error :: :inconsistent_thresholds | :missing_zero_point_level

  @typep threshold_level :: %{label: String.t(), points: Points.t(), min_actions: term()}

  @doc """
  Checks that the rule fields of a package criterion (string keys) can be
  applied: thresholds are set on every level or on none, as non-negative
  integers; and a criterion with thresholds, a `mandatory` action or a
  `forbidden` action has a zero-point level, whose threshold is zero.

  Expects levels whose points already converted to exact points. The Station
  Package loader enforces the same rules; this check keeps `decide_level/3`
  total for a package that did not go through it.
  """
  @spec check(map()) :: :ok | {:error, authoring_error()}
  def check(criterion) when is_map(criterion) do
    levels = levels(criterion)
    zero_levels = Enum.filter(levels, &(&1.points == Points.zero()))

    cond do
      not consistent_thresholds?(levels) ->
        {:error, :inconsistent_thresholds}

      not zero_scoring_rule?(criterion, levels) ->
        :ok

      zero_levels == [] ->
        {:error, :missing_zero_point_level}

      Enum.any?(zero_levels, &(&1.min_actions not in [nil, 0])) ->
        {:error, :inconsistent_thresholds}

      true ->
        :ok
    end
  end

  @doc """
  Decides the level of a criterion from the level Jev chose and the validated
  decisions of its authored actions.

  Returns the level to assess, or `{:uncertain, reason}` naming the first
  unresolved sub-action in authored order. The criterion must have passed
  `check/1`.
  """
  @spec decide_level(map(), level(), [sub_action()]) ::
          {:ok, level()} | {:uncertain, uncertainty()}
  def decide_level(criterion, jev_level, sub_actions)
      when is_map(criterion) and is_list(sub_actions) do
    levels = levels(criterion)
    thresholds? = thresholds?(levels)
    decided = with_roles(criterion, sub_actions)

    case Enum.find_value(decided, &unresolved(&1, thresholds?)) do
      nil -> {:ok, level(criterion, levels, thresholds?, decided, jev_level)}
      reason -> {:uncertain, reason}
    end
  end

  # Rule 1. An action whose outcome cannot change the level is never unresolved.
  defp unresolved({role, _sub_action}, false) when role not in [@mandatory, @forbidden], do: nil

  defp unresolved({_role, %{classification: @uncertain, id: id}}, _thresholds?),
    do: {:uncertain_sub_action, id}

  defp unresolved({_role, %{classification: @performed, evidence_ids: [], id: id}}, _thresholds?),
    do: {:unsupported_sub_action, id}

  defp unresolved(_decided, _thresholds?), do: nil

  # Rules 2 to 5, over resolved sub-actions.
  defp level(criterion, levels, thresholds?, decided, jev_level) do
    cond do
      Enum.any?(decided, &performed?(&1, @forbidden)) -> zero_level(levels)
      Enum.any?(decided, &missing?(&1, @mandatory)) -> zero_level(levels)
      thresholds? -> threshold_level(levels, capped_count(criterion, decided))
      true -> jev_level
    end
  end

  defp performed?({role, %{classification: classification}}, role),
    do: classification == @performed

  defp performed?(_decided, _role), do: false

  defp missing?({role, %{classification: classification}}, role), do: classification != @performed
  defp missing?(_decided, _role), do: false

  defp capped_count(criterion, decided) do
    count =
      Enum.count(decided, fn {role, sub_action} ->
        role != @forbidden and sub_action.classification == @performed
      end)

    case Map.get(criterion, "count_cap") do
      cap when is_integer(cap) and cap >= 1 -> min(count, cap)
      _no_cap -> count
    end
  end

  # The zero-point level always qualifies, so the candidates are never empty.
  defp threshold_level(levels, count) do
    levels
    |> Enum.filter(&(&1.min_actions <= count))
    |> Enum.max_by(& &1.points)
    |> Map.take([:label, :points])
  end

  defp zero_level(levels) do
    levels |> Enum.find(&(&1.points == Points.zero())) |> Map.take([:label, :points])
  end

  # Pairs each sub-action decision with the authored role of its action.
  defp with_roles(criterion, sub_actions) do
    roles =
      for %{"id" => id} = action <- list(criterion, "actions"), into: %{} do
        {id, Map.get(action, "role")}
      end

    Enum.map(sub_actions, &{Map.get(roles, &1.id), &1})
  end

  defp zero_scoring_rule?(criterion, levels) do
    thresholds?(levels) or
      Enum.any?(
        list(criterion, "actions"),
        &(is_map(&1) and &1["role"] in [@mandatory, @forbidden])
      )
  end

  defp thresholds?(levels), do: levels != [] and Enum.all?(levels, &threshold?/1)

  defp consistent_thresholds?(levels) do
    thresholds?(levels) or Enum.all?(levels, &is_nil(&1.min_actions))
  end

  defp threshold?(%{min_actions: min_actions}), do: is_integer(min_actions) and min_actions >= 0

  # A level key that is present but null is kept as `:invalid`, so it never
  # reads as an absent threshold.
  @spec levels(map()) :: [threshold_level()]
  defp levels(criterion) do
    for %{"label" => label, "points" => authored} = level <- list(criterion, "levels") do
      {:ok, points} = Points.from_authored(authored)
      min_actions = if Map.has_key?(level, "min_actions"), do: level["min_actions"] || :invalid

      %{label: label, points: points, min_actions: min_actions}
    end
  end

  defp list(criterion, key) do
    case Map.get(criterion, key) do
      entries when is_list(entries) -> entries
      _missing -> []
    end
  end
end
