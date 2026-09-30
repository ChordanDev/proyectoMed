defmodule Backend.Stations.TemplateApplicability do
  @moduledoc """
  Structured applicability predicates for approved templates (issue #147).

  Predicate vocabulary v1, grounded only in trusted case state:

      %{"type" => "unconditional"}
      %{"type" => "first_learner_turn"}
      %{"type" => "min_learner_turns", "count" => pos_integer}
      %{"type" => "max_learner_turns", "count" => pos_integer}

  Case state contract: `%{learner_turns: non_neg_integer()}` (atom key; the
  JSON-canonical `"learner_turns"` key is tolerated too). A missing or invalid
  `learner_turns` makes every state-dependent predicate evaluate `false`
  (fail closed per ADR-011, issue #123).

  `evaluate/2` and `structural_errors/1` share a single classifier so the
  load-time validator (`Backend.Stations.StationPackage`) and the runtime
  evaluator (`Backend.Stations.CandidateGate`) can never diverge. String keys
  are the JSON-canonical form; atom keys are tolerated. The module is pure and
  deterministic: it never raises and never interprets natural language.
  """

  @known_types ~w(unconditional first_learner_turn min_learner_turns max_learner_turns)
  @bare_keys ["type", :type]
  @counted_keys ["type", :type, "count", :count]

  @typedoc "A recognized applicability predicate in evaluated form."
  @type predicate ::
          :unconditional
          | :first_learner_turn
          | {:min_learner_turns, pos_integer()}
          | {:max_learner_turns, pos_integer()}

  # ============================================================================
  # Runtime evaluation (fail closed)
  # ============================================================================

  @doc """
  Evaluates `applicability` against `case_state`, returning `true` only when a
  recognized structured predicate's condition holds.

  Anything unrecognized (unknown type, wrong shape, `nil`, non-map, malformed
  counts) evaluates `false`. Never raises.
  """
  @spec evaluate(term(), term()) :: boolean()
  def evaluate(applicability, case_state) do
    case classify(applicability) do
      {:ok, :unconditional} ->
        true

      {:ok, :first_learner_turn} ->
        learner_turns(case_state) == 1

      {:ok, {:min_learner_turns, count}} ->
        known_turns?(case_state, &(&1 >= count))

      {:ok, {:max_learner_turns, count}} ->
        known_turns?(case_state, &(&1 <= count))

      {:error, _reason} ->
        false
    end
  end

  # ============================================================================
  # Load-time structural validation
  # ============================================================================

  @doc """
  Returns structural errors for `applicability` ([] when it matches the
  structured vocabulary), each message following the `"approved_templates ..."`
  style used by `Backend.Stations.StationPackage.validate/1`.
  """
  @spec structural_errors(term()) :: [String.t()]
  def structural_errors(applicability) do
    case classify(applicability) do
      {:ok, _predicate} -> []
      {:error, reason} -> [error_message(reason)]
    end
  end

  # ============================================================================
  # Shared classifier
  # ============================================================================

  defp classify(applicability) when is_map(applicability) do
    with {:ok, type} <- fetch_type(applicability),
         :ok <- ensure_known_type(type),
         {:ok, predicate} <- build_predicate(type, applicability) do
      {:ok, predicate}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp classify(nil), do: {:error, :missing}
  defp classify(applicability) when is_boolean(applicability), do: {:error, :boolean}
  defp classify(applicability) when is_binary(applicability), do: {:error, :prose_string}
  defp classify(_applicability), do: {:error, :not_object}

  defp fetch_type(applicability) do
    case fetch_field(applicability, "type", :type) do
      {:ok, type} -> {:ok, type}
      :error -> {:error, :missing_type}
    end
  end

  defp ensure_known_type(type) when type in @known_types, do: :ok
  defp ensure_known_type(_type), do: {:error, :unknown_type}

  defp build_predicate("unconditional", applicability),
    do: bare_predicate(:unconditional, "unconditional", applicability)

  defp build_predicate("first_learner_turn", applicability),
    do: bare_predicate(:first_learner_turn, "first_learner_turn", applicability)

  defp build_predicate("min_learner_turns", applicability),
    do: counted_predicate(:min_learner_turns, "min_learner_turns", applicability)

  defp build_predicate("max_learner_turns", applicability),
    do: counted_predicate(:max_learner_turns, "max_learner_turns", applicability)

  defp bare_predicate(atom, type, applicability) do
    if allowed_keys_only?(applicability, @bare_keys) do
      {:ok, atom}
    else
      {:error, {:extra_fields, type}}
    end
  end

  defp counted_predicate(atom, type, applicability) do
    with true <- allowed_keys_only?(applicability, @counted_keys),
         {:ok, count} <- fetch_count(type, applicability) do
      {:ok, {atom, count}}
    else
      false -> {:error, {:extra_fields, type}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_count(type, applicability) do
    case fetch_field(applicability, "count", :count) do
      {:ok, count} when is_integer(count) and count >= 1 -> {:ok, count}
      {:ok, _count} -> {:error, {:invalid_count, type}}
      :error -> {:error, {:missing_count, type}}
    end
  end

  defp fetch_field(map, string_key, atom_key) do
    case Map.fetch(map, string_key) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(map, atom_key)
    end
  end

  defp allowed_keys_only?(map, allowed_keys) do
    Enum.all?(Map.keys(map), &(&1 in allowed_keys))
  end

  # ============================================================================
  # Trusted case state access
  # ============================================================================

  defp learner_turns(case_state) when is_map(case_state) do
    case fetch_field(case_state, "learner_turns", :learner_turns) do
      {:ok, turns} when is_integer(turns) and turns >= 0 -> turns
      _other -> nil
    end
  end

  defp learner_turns(_case_state), do: nil

  defp known_turns?(case_state, condition) do
    case learner_turns(case_state) do
      nil -> false
      turns -> condition.(turns)
    end
  end

  # ============================================================================
  # Load-time error messages
  # ============================================================================

  defp error_message(:missing),
    do: "approved_templates entries require an applicability predicate object"

  defp error_message(:prose_string),
    do:
      "approved_templates applicability must be a structured predicate object, not a prose string"

  defp error_message(:boolean),
    do: "approved_templates applicability must be a structured predicate object, not a boolean"

  defp error_message(:not_object),
    do: "approved_templates applicability must be a structured predicate object"

  defp error_message(:missing_type),
    do: "approved_templates applicability requires a type"

  defp error_message(:unknown_type),
    do:
      "approved_templates applicability type must be one of: unconditional, first_learner_turn, min_learner_turns, max_learner_turns"

  defp error_message({:missing_count, type}),
    do: "approved_templates #{type} predicate requires a count"

  defp error_message({:invalid_count, type}),
    do: "approved_templates #{type} predicate requires an integer count >= 1"

  defp error_message({:extra_fields, type}),
    do: "approved_templates #{type} predicates must not include additional fields"
end
