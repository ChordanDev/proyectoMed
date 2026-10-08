defmodule Backend.Stations.Qualification.Cases do
  @moduledoc """
  The format of the qualification case files and of the thresholds file
  (issue #130).

  A case file holds the fictional cases of one category:

      {"station_id": "...", "category": "...", "fictional": true, "cases": [...]}

  A case names the surface it drives, the fictional input, the structural
  outcome it was written to probe (`proposed_expected`) and its human
  `adjudication`. A proposal is not an adjudication: a case is compared with
  an expected outcome only once a named adjudicator recorded one.

  Outcomes use the vocabulary of the surface:

    * `dialogue_gate`: `delivered`, `denied`, `semantic_refusal`,
      `low_confidence` or `technical_failure`;
    * `rubric_assessment`: `assessed:<level label>`, `uncertain`,
      `not_observable`, `not_applicable`, `technical_failure` or, for a case
      that targets one authored action, `action:<classification>`.

  The module is pure: it validates decoded JSON and knows no Station Package.
  Whether a criterion, action or level exists is checked by
  `Backend.Stations.Qualification.load/1`.
  """

  alias Backend.Stations.JevDecision.RubricBatch

  @categories ~w(ambiguity unsupported_or_early_disclosure contradiction injection uncertainty) ++
                ~w(modality_gap chronology technical_failure)
  @surfaces ~w(dialogue_gate rubric_assessment)
  @case_fields ~w(id category surface probes input proposed_expected adjudication)
  @dialogue_outcomes ~w(delivered denied semantic_refusal low_confidence technical_failure)
  @rubric_statuses ~w(uncertain not_observable not_applicable technical_failure)
  @pending %{"status" => "pending", "adjudicator" => nil, "date" => nil, "expected" => nil}

  @type case_error ::
          :unknown_category
          | :category_mismatch
          | :duplicate_id
          | :unknown_surface
          | :invalid_probes
          | :invalid_input
          | :invalid_proposed_expected
          | :invalid_adjudication
          | {:missing_field, String.t()}

  @type file_error ::
          {:invalid_file, :expected_map | :not_fictional | :unknown_category | :invalid_cases}
          | {:invalid_case, String.t() | pos_integer(), case_error()}

  @type thresholds_error ::
          {:invalid_thresholds,
           :expected_map | :categories | :invalid_required_agreement | :missing_definition_record}

  @doc "The eight qualification categories, in reporting order."
  @spec categories() :: [String.t(), ...]
  def categories, do: @categories

  @doc """
  Validates one decoded case file and returns its cases unchanged.

  A case without a usable `id` is reported by its 1-based position.
  """
  @spec validate_file(term()) :: {:ok, [map(), ...]} | {:error, file_error()}
  def validate_file(%{"cases" => [_ | _] = cases} = file) do
    cond do
      file["fictional"] != true -> {:error, {:invalid_file, :not_fictional}}
      file["category"] not in @categories -> {:error, {:invalid_file, :unknown_category}}
      true -> validate_cases(cases, file["category"])
    end
  end

  def validate_file(file) when is_map(file), do: {:error, {:invalid_file, :invalid_cases}}
  def validate_file(_file), do: {:error, {:invalid_file, :expected_map}}

  @doc """
  Validates the decoded thresholds file.

  Returns `:undefined` while any required agreement is `null`. Thresholds are
  `:defined` only when every value is a fraction between 0 and 1 and the file
  records who defined them and when.
  """
  @spec validate_thresholds(term()) :: {:ok, :undefined | :defined} | {:error, thresholds_error()}
  def validate_thresholds(%{"categories" => categories} = thresholds) when is_map(categories) do
    entries = [thresholds["overall"] | Map.values(categories)]

    cond do
      Enum.sort(Map.keys(categories)) != Enum.sort(@categories) ->
        {:error, {:invalid_thresholds, :categories}}

      not Enum.all?(entries, &required_agreement?/1) ->
        {:error, {:invalid_thresholds, :invalid_required_agreement}}

      Enum.any?(entries, &is_nil(&1["required_agreement"])) ->
        {:ok, :undefined}

      non_blank?(thresholds["defined_by"]) and iso_date?(thresholds["date"]) ->
        {:ok, :defined}

      true ->
        {:error, {:invalid_thresholds, :missing_definition_record}}
    end
  end

  def validate_thresholds(thresholds) when is_map(thresholds) do
    {:error, {:invalid_thresholds, :categories}}
  end

  def validate_thresholds(_thresholds), do: {:error, {:invalid_thresholds, :expected_map}}

  # ============================================================================
  # Cases
  # ============================================================================

  defp validate_cases(cases, category) do
    cases
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, MapSet.new()}, fn {case_map, position}, {:ok, seen} ->
      case validate_case(case_map, category, seen) do
        :ok ->
          {:cont, {:ok, MapSet.put(seen, case_map["id"])}}

        {:error, reason} ->
          {:halt, {:error, {:invalid_case, reference(case_map, position), reason}}}
      end
    end)
    |> case do
      {:ok, _seen} -> {:ok, cases}
      error -> error
    end
  end

  defp reference(%{"id" => id}, _position) when is_binary(id), do: id
  defp reference(_case_map, position), do: position

  defp validate_case(case_map, category, seen) when is_map(case_map) do
    with :ok <- required_fields(case_map),
         :ok <- check(not MapSet.member?(seen, case_map["id"]), :duplicate_id),
         :ok <- check(case_map["category"] in @categories, :unknown_category),
         :ok <- check(case_map["category"] == category, :category_mismatch),
         :ok <- check(case_map["surface"] in @surfaces, :unknown_surface),
         :ok <- check(strings?(case_map["probes"]), :invalid_probes),
         :ok <- check(input?(case_map["surface"], case_map["input"]), :invalid_input),
         :ok <-
           check(
             proposed?(case_map["surface"], case_map["proposed_expected"]),
             :invalid_proposed_expected
           ) do
      check(
        adjudication?(case_map["surface"], case_map["adjudication"]),
        :invalid_adjudication
      )
    end
  end

  defp validate_case(_case_map, _category, _seen), do: {:error, {:missing_field, "id"}}

  defp required_fields(case_map) do
    case Enum.find(@case_fields, &(not present?(case_map, &1))) do
      nil -> :ok
      field -> {:error, {:missing_field, field}}
    end
  end

  defp present?(case_map, "id"), do: non_blank?(case_map["id"])
  defp present?(case_map, field), do: is_map_key(case_map, field)

  # ============================================================================
  # Input
  # ============================================================================

  defp input?("dialogue_gate", %{"turns" => turns, "candidate_reply" => reply} = input) do
    turns?(turns, ~w(text voice)) and is_binary(reply) and deadline?(input)
  end

  defp input?("rubric_assessment", %{"turns" => turns, "criterion_id" => criterion_id} = input) do
    turns?(turns, ~w(text voice impressos)) and non_blank?(criterion_id) and
      (is_nil(input["action_id"]) or non_blank?(input["action_id"])) and deadline?(input)
  end

  defp input?(_surface, _input), do: false

  defp turns?([_ | _] = turns, modalities), do: Enum.all?(turns, &turn?(&1, modalities))
  defp turns?(_turns, _modalities), do: false

  # An Impressos request is a learner event, so the patient never has one.
  defp turn?(%{"role" => role, "modality" => modality, "text" => text}, modalities) do
    role in ~w(learner patient) and modality in modalities and non_blank?(text) and
      (modality != "impressos" or role == "learner")
  end

  defp turn?(_turn, _modalities), do: false

  defp deadline?(input), do: input["deadline"] in [nil, "expired"]

  # ============================================================================
  # Expected outcomes and adjudication
  # ============================================================================

  defp proposed?(surface, %{"outcomes" => outcomes, "note" => note}) do
    outcomes?(surface, outcomes) and non_blank?(note)
  end

  defp proposed?(_surface, _proposed), do: false

  defp adjudication?(_surface, @pending), do: true

  defp adjudication?(
         surface,
         %{"status" => "adjudicated", "expected" => %{"outcomes" => outcomes}} = adjudication
       ) do
    non_blank?(adjudication["adjudicator"]) and iso_date?(adjudication["date"]) and
      outcomes?(surface, outcomes)
  end

  defp adjudication?(_surface, _adjudication), do: false

  defp outcomes?(surface, [_ | _] = outcomes), do: Enum.all?(outcomes, &outcome?(surface, &1))
  defp outcomes?(_surface, _outcomes), do: false

  defp outcome?("dialogue_gate", outcome), do: outcome in @dialogue_outcomes
  defp outcome?("rubric_assessment", "assessed:" <> level), do: non_blank?(level)

  defp outcome?("rubric_assessment", "action:" <> class),
    do: class in RubricBatch.action_classes()

  defp outcome?("rubric_assessment", outcome), do: outcome in @rubric_statuses

  # ============================================================================
  # Thresholds
  # ============================================================================

  defp required_agreement?(%{"required_agreement" => nil}), do: true

  defp required_agreement?(%{"required_agreement" => value}) when is_number(value) do
    value >= 0 and value <= 1
  end

  defp required_agreement?(_entry), do: false

  # ============================================================================
  # Shared checks
  # ============================================================================

  defp check(true, _reason), do: :ok
  defp check(false, reason), do: {:error, reason}

  defp strings?(values), do: is_list(values) and Enum.all?(values, &non_blank?/1)

  defp non_blank?(value), do: is_binary(value) and String.trim(value) != ""

  defp iso_date?(value), do: is_binary(value) and match?({:ok, _date}, Date.from_iso8601(value))
end
