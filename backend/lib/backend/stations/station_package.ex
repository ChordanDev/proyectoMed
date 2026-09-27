defmodule Backend.Stations.StationPackage do
  @moduledoc """
  Validates the versioned Station Package contract supplied by the Content Partner.

  `Backend.Stations.StationLoader` will decode a package JSON document and pass the resulting
  map to `validate/1` before making it available to the application.
  """

  @version "1.0.0"
  @required_string_fields ~w(station_id version language display_title)a
  @valid_impresso_categories ~w(physical_exam laboratory imaging report)

  @spec version() :: String.t()
  def version, do: @version

  @spec validate(map()) :: {:ok, map()} | {:error, [String.t()]}
  def validate(package) when is_map(package) do
    errors =
      []
      |> validate_required_strings(package)
      |> validate_version(package)
      |> validate_language(package)
      |> validate_patient_profile(package)
      |> validate_list_of_entries(package, "revealable_facts", ["topic", "content"])
      |> validate_list_of_entries(package, "response_rules", ["id", "instruction"])
      |> validate_list_of_entries(package, "expected_actions", ["id", "description"])
      |> validate_rubric(package)
      |> validate_impressos(package)

    case errors do
      [] -> {:ok, package}
      _ -> {:error, Enum.reverse(errors)}
    end
  end

  def validate(_), do: {:error, ["package must be an object"]}

  defp validate_required_strings(errors, package) do
    Enum.reduce(@required_string_fields, errors, fn field, errors ->
      if is_binary(package[Atom.to_string(field)]) and package[Atom.to_string(field)] != "" do
        errors
      else
        ["#{field} must be a non-empty string" | errors]
      end
    end)
  end

  defp validate_version(errors, %{"version" => @version}), do: errors
  defp validate_version(errors, _package), do: ["version must be #{@version}" | errors]

  defp validate_language(errors, %{"language" => "pt-BR"}), do: errors
  defp validate_language(errors, _package), do: ["language must be pt-BR" | errors]

  defp validate_patient_profile(errors, %{"patient_profile" => profile}) when is_map(profile) do
    errors
    |> validate_patient_profile_strings(profile)
    |> validate_patient_profile_age(profile)
  end

  defp validate_patient_profile(errors, _package),
    do: ["patient_profile must be an object" | errors]

  defp validate_patient_profile_strings(errors, profile) do
    Enum.reduce(["persona", "presenting_context", "tone"], errors, fn field, errors ->
      if is_binary(profile[field]) and profile[field] != "" do
        errors
      else
        ["patient_profile.#{field} must be a non-empty string" | errors]
      end
    end)
  end

  defp validate_patient_profile_age(errors, %{"age" => age})
       when is_integer(age) and age >= 0,
       do: errors

  defp validate_patient_profile_age(errors, _profile),
    do: ["patient_profile.age must be a non-negative integer" | errors]

  defp validate_list_of_entries(errors, package, field, required_fields) do
    case package[field] do
      entries when is_list(entries) ->
        Enum.reduce(entries, errors, fn entry, errors ->
          validate_entry(errors, entry, field, required_fields)
        end)

      _ ->
        ["#{field} must be a list" | errors]
    end
  end

  defp validate_entry(errors, entry, field, required_fields) when is_map(entry) do
    Enum.reduce(required_fields, errors, fn required_field, errors ->
      if is_binary(entry[required_field]) and entry[required_field] != "" do
        errors
      else
        ["#{field} entries require a non-empty #{required_field}" | errors]
      end
    end)
  end

  defp validate_entry(errors, _entry, field, _required_fields),
    do: ["#{field} entries must be objects" | errors]

  defp validate_rubric(errors, %{"rubric" => rubric}) when is_list(rubric) do
    Enum.reduce(rubric, errors, &validate_rubric_criterion/2)
  end

  defp validate_rubric(errors, _package), do: ["rubric must be a list" | errors]

  defp validate_rubric_criterion(criterion, errors) when is_map(criterion) do
    errors
    |> validate_rubric_strings(criterion)
    |> validate_evidence_questions(criterion)
    |> validate_weight(criterion)
  end

  defp validate_rubric_criterion(_criterion, errors),
    do: ["rubric criteria must be objects" | errors]

  defp validate_rubric_strings(errors, criterion) do
    Enum.reduce(["id", "description", "practice_recommendation"], errors, fn field, errors ->
      if is_binary(criterion[field]) and criterion[field] != "" do
        errors
      else
        ["rubric criteria require a non-empty #{field}" | errors]
      end
    end)
  end

  defp validate_evidence_questions(errors, %{"evidence_questions" => questions})
       when is_list(questions) do
    if Enum.all?(questions, &(is_binary(&1) and &1 != "")) do
      errors
    else
      ["rubric criteria evidence_questions must contain non-empty strings" | errors]
    end
  end

  defp validate_evidence_questions(errors, _criterion),
    do: ["rubric criteria evidence_questions must be a list" | errors]

  defp validate_weight(errors, %{"weight" => weight}) when is_number(weight), do: errors

  defp validate_weight(errors, _criterion),
    do: ["rubric criteria require a numeric weight" | errors]

  defp validate_impressos(errors, %{"impressos" => impressos}) when is_list(impressos) do
    errors
    |> validate_impresso_entries(impressos)
    |> validate_impresso_unique_ids(impressos)
  end

  defp validate_impressos(errors, %{"impressos" => nil}), do: errors
  defp validate_impressos(errors, %{"impressos" => _}), do: ["impressos must be a list" | errors]
  defp validate_impressos(errors, _package), do: errors

  defp validate_impresso_entries(errors, impressos) do
    Enum.reduce(impressos, errors, &validate_impresso_entry/2)
  end

  defp validate_impresso_entry(entry, errors) when is_map(entry) do
    errors
    |> validate_impresso_strings(entry)
    |> validate_impresso_category(entry)
    |> validate_impresso_keywords(entry)
    |> validate_impresso_content(entry)
  end

  defp validate_impresso_entry(_entry, errors) do
    ["impressos entries must be objects" | errors]
  end

  defp validate_impresso_strings(errors, entry) do
    Enum.reduce(["id", "title"], errors, fn field, errors ->
      if is_binary(entry[field]) and entry[field] != "" do
        errors
      else
        ["impressos entries require a non-empty #{field}" | errors]
      end
    end)
  end

  defp validate_impresso_category(errors, %{"category" => category})
       when category in @valid_impresso_categories,
       do: errors

  defp validate_impresso_category(errors, %{"category" => category})
       when is_binary(category) and category != "" do
    [
      "impressos entries category must be one of: #{Enum.join(@valid_impresso_categories, ", ")}"
      | errors
    ]
  end

  defp validate_impresso_category(errors, _entry) do
    ["impressos entries require a non-empty category" | errors]
  end

  defp validate_impresso_keywords(errors, %{"keywords" => keywords}) when is_list(keywords) do
    if Enum.all?(keywords, &(is_binary(&1) and &1 != "")) do
      errors
    else
      ["impressos entries keywords must contain non-empty strings" | errors]
    end
  end

  defp validate_impresso_keywords(errors, _entry) do
    ["impressos entries keywords must be a list" | errors]
  end

  defp validate_impresso_content(errors, %{"content" => content})
       when is_binary(content) and content != "",
       do: errors

  defp validate_impresso_content(errors, %{"content" => content})
       when is_map(content) and map_size(content) > 0,
       do: errors

  defp validate_impresso_content(errors, _entry) do
    ["impressos entries require non-empty string or structured content" | errors]
  end

  defp validate_impresso_unique_ids(errors, impressos) do
    ids =
      Enum.flat_map(impressos, fn
        %{"id" => id} when is_binary(id) and id != "" -> [id]
        _ -> []
      end)

    if length(ids) == length(Enum.uniq(ids)) do
      errors
    else
      ["impressos entries must have unique ids" | errors]
    end
  end
end

defmodule Backend.StationPackage do
  @moduledoc false
  defdelegate version(), to: Backend.Stations.StationPackage
  defdelegate validate(package), to: Backend.Stations.StationPackage
end
