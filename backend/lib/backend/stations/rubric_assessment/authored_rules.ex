defmodule Backend.Stations.RubricAssessment.AuthoredRules do
  @moduledoc """
  Authored per-criterion rules over the sub-action decisions of a criterion
  Jev assessed (issue #128, ADR-012).

  `decide_level/3` follows one principle: an unresolved action leaves the
  criterion uncertain only when resolving it could change the result. The
  rules apply in this order:

    1. A sub-action is unresolved when it is classified `"uncertain"`, or
       `"performed"` without validated learner evidence.
    2. A `forbidden` action performed with evidence scores the zero-point level.
    3. A `mandatory` action that was not performed scores the zero-point level.
    4. Otherwise the reachable outcomes are the levels the criterion can end at
       across every resolution of the unresolved actions: the zero-point level
       when a `mandatory` or `forbidden` action is unresolved, and the level of
       rule 5 or 6. One reachable outcome is the level; several leave the
       criterion uncertain.
    5. With authored thresholds (`levels[].min_actions`), the level is the
       highest one whose threshold is at most the number of performed
       non-forbidden actions, capped by `count_cap`. The unresolved ones range
       that number from none to all of them. The count decides; Jev's
       criterion-level class does not.
    6. Without thresholds, Jev's level stands.

  A criterion that authors no threshold and no `mandatory` or `forbidden`
  action therefore keeps Jev's level whatever its sub-actions say.

  Jev may be uncertain about the criterion as a whole and still classify its
  actions. Rules 2, 3 and 5 need no criterion-level class, so they still
  decide; only an outcome that depends on rule 6 stays uncertain.

  The module is pure. Sub-action evidence arrives already validated against
  the evidence pool, so an empty `evidence_ids` list is the only way a
  performed action can lack evidence. Points are integer eighths
  (`Backend.Stations.RubricAssessment.Points`). `first_n` runs before this
  module (`Backend.Stations.RubricAssessment.FirstN`), which hands over the
  decisions with every action beyond the first N answers already not
  performed, and asks `certain_zero?/2` and `unresolved/2` whether an action
  without a known position could still displace an eligible answer; the
  `task_order` rule is not applied here.
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

  @typedoc "The level Jev chose for the criterion, or `:uncertain` when it chose none."
  @type jev_level :: level() | :uncertain

  @typedoc "Why the rule fields of a criterion cannot be applied."
  @type authoring_error ::
          :inconsistent_thresholds | :missing_zero_point_level | :first_n_without_thresholds

  @typep threshold_level :: %{label: String.t(), points: Points.t(), min_actions: term()}

  @doc """
  Checks that the rule fields of a package criterion (string keys) can be
  applied: thresholds are set on every level or on none, as non-negative
  integers; a criterion with thresholds, a `mandatory` action or a
  `forbidden` action has a zero-point level, whose threshold is zero; and a
  criterion that authors `first_n` and at least one action authors thresholds,
  because a level Jev chose as a whole cannot be limited to the first N
  answers.

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

      first_n_without_thresholds?(criterion, levels) ->
        {:error, :first_n_without_thresholds}

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
  Says whether the rule fields of a package criterion (string keys) can decide
  its level without Jev's criterion-level class: it authors thresholds, or a
  `mandatory` or `forbidden` action.
  """
  @spec decides?(map()) :: boolean()
  def decides?(criterion) when is_map(criterion) do
    zero_scoring_rule?(criterion, levels(criterion))
  end

  @doc """
  Decides the level of a criterion from the level Jev chose, or `:uncertain`
  when it chose none, and the validated decisions of its authored actions.

  Returns the level to assess with the actions that ground it: the performed
  countable actions when their count decided it, the performed `forbidden`
  actions when they scored the zero-point level, and no actions otherwise.
  Returns `{:uncertain, reason}`
  when several outcomes are reachable: the reason names the first unresolved
  `mandatory` or `forbidden` action in authored order, or else the first
  unresolved countable one. It is `:classifier_uncertain` when the outcome
  depends on a level Jev did not choose. The criterion must have passed
  `check/1`.
  """
  @spec decide_level(map(), jev_level(), [sub_action()]) ::
          {:ok, level(), [sub_action()]} | {:uncertain, uncertainty() | :classifier_uncertain}
  def decide_level(criterion, jev_level, sub_actions)
      when is_map(criterion) and is_list(sub_actions) do
    levels = levels(criterion)
    decided = decided(criterion, sub_actions)

    cond do
      vetoing(decided) != [] ->
        {:ok, zero_level(levels), vetoing(decided)}

      missing_mandatory?(decided) ->
        {:ok, zero_level(levels), []}

      thresholds?(levels) ->
        counted =
          for {role, :performed, sub_action} <- decided, role != @forbidden, do: sub_action

        single(
          vetoable(levels, decided) ++ countable(criterion, levels, decided),
          decided,
          counted
        )

      jev_level == :uncertain ->
        {:uncertain, :classifier_uncertain}

      true ->
        single(vetoable(levels, decided) ++ [jev_level], decided, [])
    end
  end

  @doc """
  Says whether the classified facts already score the zero-point level,
  whatever else is unresolved: a `forbidden` action performed with evidence
  (rule 2) or a `mandatory` action that was not performed (rule 3).
  """
  @spec certain_zero?(map(), [sub_action()]) :: boolean()
  def certain_zero?(criterion, sub_actions) when is_map(criterion) and is_list(sub_actions) do
    decided = decided(criterion, sub_actions)

    vetoing(decided) != [] or missing_mandatory?(decided)
  end

  @doc """
  Returns the reason that names the unresolved action of a criterion, chosen
  as `decide_level/3` chooses it, or `nil` when every action is resolved.
  """
  @spec unresolved(map(), [sub_action()]) :: uncertainty() | nil
  def unresolved(criterion, sub_actions) when is_map(criterion) and is_list(sub_actions) do
    case criterion |> decided(sub_actions) |> first_unresolved() do
      nil -> nil
      sub_action -> reason(sub_action)
    end
  end

  # Rule 4: one reachable outcome is the level, several are uncertainty.
  defp single(outcomes, decided, counted) do
    case Enum.uniq(outcomes) do
      [level] -> {:ok, level, counted}
      _several -> {:uncertain, decided |> first_unresolved() |> reason()}
    end
  end

  defp vetoing(decided) do
    for {@forbidden, :performed, sub_action} <- decided, do: sub_action
  end

  defp missing_mandatory?(decided) do
    Enum.any?(decided, &match?({@mandatory, :not_performed, _sub_action}, &1))
  end

  # An unresolved mandatory action may turn out not performed, and an
  # unresolved forbidden one performed: either way the zero-point level.
  defp vetoable(levels, decided) do
    if Enum.any?(decided, &zero_scoring?/1), do: [zero_level(levels)], else: []
  end

  # The levels of every count the unresolved countable actions leave open,
  # from none of them performed to all of them, each after `count_cap`.
  defp countable(criterion, levels, decided) do
    performed = count(decided, :performed)

    for count <- performed..(performed + count(decided, :unresolved)) do
      threshold_level(levels, capped(criterion, count))
    end
  end

  # The first unresolved mandatory or forbidden action in authored order, or
  # else the first unresolved countable one. Several reachable outcomes need
  # an unresolved action, so `single/3` always finds one.
  defp first_unresolved(decided) do
    case Enum.find(decided, &zero_scoring?/1) || Enum.find(decided, &unresolved?/1) do
      {_role, :unresolved, sub_action} -> sub_action
      nil -> nil
    end
  end

  defp unresolved?({_role, state, _sub_action}), do: state == :unresolved

  defp zero_scoring?({role, :unresolved, _sub_action}), do: role in [@mandatory, @forbidden]
  defp zero_scoring?(_resolved), do: false

  defp reason(%{classification: @uncertain, id: id}), do: {:uncertain_sub_action, id}
  defp reason(%{id: id}), do: {:unsupported_sub_action, id}

  # Forbidden actions never count toward a threshold.
  defp count(decided, state) do
    Enum.count(decided, fn {role, action_state, _sub_action} ->
      role != @forbidden and action_state == state
    end)
  end

  defp capped(criterion, count) do
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

  # Each sub-action decision with the authored role of its action and its
  # state. The batch contract returns the decisions in authored order.
  defp decided(criterion, sub_actions) do
    roles =
      for %{"id" => id} = action <- list(criterion, "actions"), into: %{} do
        {id, Map.get(action, "role")}
      end

    Enum.map(sub_actions, &{Map.get(roles, &1.id), state(&1), &1})
  end

  defp state(%{classification: @uncertain}), do: :unresolved
  defp state(%{classification: @performed, evidence_ids: []}), do: :unresolved
  defp state(%{classification: @performed}), do: :performed
  defp state(_sub_action), do: :not_performed

  defp zero_scoring_rule?(criterion, levels) do
    thresholds?(levels) or
      Enum.any?(
        list(criterion, "actions"),
        &(is_map(&1) and &1["role"] in [@mandatory, @forbidden])
      )
  end

  defp first_n_without_thresholds?(criterion, levels) do
    is_integer(Map.get(criterion, "first_n")) and
      Enum.any?(list(criterion, "actions"), &is_map/1) and not thresholds?(levels)
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
