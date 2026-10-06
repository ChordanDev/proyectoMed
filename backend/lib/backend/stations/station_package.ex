defmodule Backend.Stations.StationPackage do
  @moduledoc """
  Validates and migrates the versioned Station Package contract supplied by the
  Content Partner.

  `Backend.Stations.StationLoader` decodes a package JSON document and passes the resulting
  map to `validate/1` before making it available to the application. Version 1
  packages can be upgraded explicitly with `migrate/1` before validation.

  `approved_templates[].applicability` must be a structured predicate object
  from the vocabulary owned by `Backend.Stations.TemplateApplicability`; prose
  strings and booleans are load errors (issue #147).
  """

  alias Backend.Stations.TemplateApplicability

  @version "2.0.0"
  @previous_version "1.0.0"
  @required_string_fields ~w(station_id version language display_title)a
  @disclosure_conditions ~w(on_request after_action timed unconditional)
  @level_labels ~w(inadequado parcialmente_adequado adequado)
  @criterion_nullable_integer_fields ~w(order count_cap first_n)
  @valid_impresso_categories ~w(physical_exam laboratory imaging report)

  @spec version() :: String.t()
  def version, do: @version

  @doc "Migrates a Station Package v1 map to the v2 contract."
  @spec migrate(map()) :: map()
  def migrate(%{"version" => @previous_version} = package) do
    package
    |> Map.put("version", @version)
    |> Map.put_new("placeholder", true)
    |> Map.update("revealable_facts", [], &Enum.map(&1, fn fact -> migrate_fact(fact) end))
    |> Map.update("rubric", [], &Enum.map(&1, fn criterion -> migrate_criterion(criterion) end))
  end

  def migrate(package) when is_map(package), do: package

  @spec validate(map()) :: {:ok, map()} | {:error, [String.t()]}
  def validate(package) when is_map(package) do
    errors =
      []
      |> validate_required_strings(package)
      |> validate_version(package)
      |> validate_language(package)
      |> validate_placeholder(package)
      |> validate_patient_profile(package)
      |> validate_revealable_facts(package)
      |> validate_list_of_entries(package, "response_rules", ["id", "instruction"])
      |> validate_list_of_entries(package, "expected_actions", ["id", "description"])
      |> validate_rubric(package)
      |> validate_approved_templates(package)
      |> validate_impressos(package)

    case errors do
      [] -> {:ok, package}
      _ -> {:error, Enum.reverse(errors)}
    end
  end

  def validate(_), do: {:error, ["package must be an object"]}

  defp migrate_fact(fact) when is_map(fact) do
    fact
    |> Map.put_new("id", slug(fact["topic"]))
    |> Map.put_new("disclosure_condition", "on_request")
  end

  defp migrate_fact(fact), do: fact

  defp migrate_criterion(criterion) when is_map(criterion) do
    {weight, criterion} = Map.pop(criterion, "weight")

    criterion
    |> Map.put_new("levels", [
      %{
        "label" => "adequado",
        "points" => weight,
        "description" => criterion["description"] || "Adequate performance."
      }
    ])
    |> Map.put_new("actions", [])
    |> Map.put_new("order", nil)
    |> Map.put_new("count_cap", nil)
    |> Map.put_new("first_n", nil)
    |> Map.put_new("veto", false)
    |> Map.put_new("exclusion", false)
    |> Map.put_new("modality_requirement", nil)
  end

  defp migrate_criterion(criterion), do: criterion

  defp slug(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  defp slug(_value), do: ""

  defp validate_required_strings(errors, package) do
    Enum.reduce(@required_string_fields, errors, fn field, errors ->
      if non_empty_string?(package[Atom.to_string(field)]) do
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

  defp validate_placeholder(errors, %{"placeholder" => value}) when is_boolean(value), do: errors
  defp validate_placeholder(errors, _package), do: ["placeholder must be a boolean" | errors]

  defp validate_patient_profile(errors, %{"patient_profile" => profile}) when is_map(profile) do
    errors
    |> validate_patient_profile_strings(profile)
    |> validate_patient_profile_age(profile)
  end

  defp validate_patient_profile(errors, _package),
    do: ["patient_profile must be an object" | errors]

  defp validate_patient_profile_strings(errors, profile) do
    Enum.reduce(["persona", "presenting_context", "tone"], errors, fn field, errors ->
      if non_empty_string?(profile[field]) do
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

  defp validate_revealable_facts(errors, %{"revealable_facts" => facts}) when is_list(facts) do
    errors =
      Enum.reduce(facts, errors, fn fact, errors ->
        errors
        |> validate_entry(fact, "revealable_facts", ["id", "topic", "content"])
        |> validate_disclosure_condition(fact)
      end)

    validate_unique_ids(errors, facts, "revealable_facts ids must be unique")
  end

  defp validate_revealable_facts(errors, _package),
    do: ["revealable_facts must be a list" | errors]

  defp validate_disclosure_condition(errors, %{"disclosure_condition" => condition})
       when condition in @disclosure_conditions,
       do: errors

  defp validate_disclosure_condition(errors, _fact),
    do: ["revealable_facts entries require a valid disclosure_condition" | errors]

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
      if non_empty_string?(entry[required_field]) do
        errors
      else
        ["#{field} entries require a non-empty #{required_field}" | errors]
      end
    end)
  end

  defp validate_entry(errors, _entry, field, _required_fields),
    do: ["#{field} entries must be objects" | errors]

  defp validate_rubric(errors, %{"rubric" => rubric}) when is_list(rubric) do
    errors = Enum.reduce(rubric, errors, &validate_rubric_criterion/2)
    validate_unique_ids(errors, rubric, "rubric criterion ids must be unique")
  end

  defp validate_rubric(errors, _package), do: ["rubric must be a list" | errors]

  defp validate_rubric_criterion(criterion, errors) when is_map(criterion) do
    errors
    |> validate_rubric_strings(criterion)
    |> validate_evidence_questions(criterion)
    |> validate_levels(criterion)
    |> validate_criterion_actions(criterion)
    |> validate_nullable_integer_fields(criterion)
    |> validate_criterion_boolean(criterion, "veto")
    |> validate_criterion_boolean(criterion, "exclusion")
    |> validate_modality_requirement(criterion)
  end

  defp validate_rubric_criterion(_criterion, errors),
    do: ["rubric criteria must be objects" | errors]

  defp validate_rubric_strings(errors, criterion) do
    Enum.reduce(["id", "description", "practice_recommendation"], errors, fn field, errors ->
      if non_empty_string?(criterion[field]) do
        errors
      else
        ["rubric criteria require a non-empty #{field}" | errors]
      end
    end)
  end

  defp validate_evidence_questions(errors, %{"evidence_questions" => questions})
       when is_list(questions) do
    if Enum.all?(questions, &non_empty_string?/1) do
      errors
    else
      ["rubric criteria evidence_questions must contain non-empty strings" | errors]
    end
  end

  defp validate_evidence_questions(errors, _criterion),
    do: ["rubric criteria evidence_questions must be a list" | errors]

  defp validate_levels(errors, %{"levels" => []}),
    do: ["rubric criteria require at least one level" | errors]

  defp validate_levels(errors, %{"levels" => levels}) when is_list(levels) do
    errors = Enum.reduce(levels, errors, &validate_level/2)
    validate_unique_values(errors, levels, "label", "rubric level labels must be unique")
  end

  defp validate_levels(errors, _criterion),
    do: ["rubric criteria levels must be a non-empty list" | errors]

  defp validate_level(level, errors) when is_map(level) do
    errors
    |> validate_level_label(level)
    |> validate_level_points(level)
    |> validate_level_description(level)
  end

  defp validate_level(_level, errors), do: ["rubric levels must be objects" | errors]

  defp validate_level_label(errors, %{"label" => label}) when label in @level_labels, do: errors
  defp validate_level_label(errors, _level), do: ["rubric levels require a valid label" | errors]

  defp validate_level_points(errors, %{"points" => points}) when is_number(points) do
    quotient = points / 0.125

    if abs(quotient - round(quotient)) < 1.0e-9 do
      errors
    else
      ["rubric level points must be a multiple of 0.125" | errors]
    end
  end

  defp validate_level_points(errors, _level),
    do: ["rubric levels require numeric points" | errors]

  defp validate_level_description(errors, %{"description" => description}) do
    if non_empty_string?(description) do
      errors
    else
      ["rubric levels require a non-empty description" | errors]
    end
  end

  defp validate_level_description(errors, _level),
    do: ["rubric levels require a non-empty description" | errors]

  defp validate_criterion_actions(errors, %{"actions" => actions}) when is_list(actions) do
    Enum.reduce(actions, errors, fn action, errors ->
      validate_entry(errors, action, "rubric actions", ["id", "description"])
    end)
  end

  defp validate_criterion_actions(errors, _criterion),
    do: ["rubric criteria actions must be a list" | errors]

  defp validate_nullable_integer_fields(errors, criterion) do
    Enum.reduce(@criterion_nullable_integer_fields, errors, fn field, errors ->
      value = criterion[field]

      if Map.has_key?(criterion, field) and (is_nil(value) or is_integer(value)) do
        errors
      else
        ["rubric criteria #{field} must be an integer or null" | errors]
      end
    end)
  end

  defp validate_criterion_boolean(errors, criterion, field) do
    if is_boolean(criterion[field]) do
      errors
    else
      ["rubric criteria #{field} must be a boolean" | errors]
    end
  end

  defp validate_modality_requirement(errors, criterion) do
    value = criterion["modality_requirement"]

    if Map.has_key?(criterion, "modality_requirement") and
         (is_nil(value) or non_empty_string?(value)) do
      errors
    else
      ["rubric criteria modality_requirement must be a non-empty string or null" | errors]
    end
  end

  defp validate_approved_templates(errors, package) do
    case package["approved_templates"] do
      nil ->
        errors

      templates when is_list(templates) ->
        errors =
          Enum.reduce(templates, errors, fn template, errors ->
            errors
            |> validate_entry(template, "approved_templates", ["template_id", "text"])
            |> validate_template_applicability(template)
          end)

        validate_unique_values(
          errors,
          templates,
          "template_id",
          "approved_templates template_ids must be unique"
        )

      _ ->
        ["approved_templates must be a list or null" | errors]
    end
  end

  # Applicability is a structured predicate object, not a string field, so it
  # gets dedicated structural validation single-sourced from TemplateApplicability.
  defp validate_template_applicability(errors, template) when is_map(template) do
    applicability =
      case Map.fetch(template, "applicability") do
        {:ok, value} -> value
        :error -> Map.get(template, :applicability)
      end

    case TemplateApplicability.structural_errors(applicability) do
      [] -> errors
      applicability_errors -> Enum.reverse(applicability_errors) ++ errors
    end
  end

  defp validate_template_applicability(errors, _template), do: errors

  defp validate_unique_ids(errors, entries, message),
    do: validate_unique_values(errors, entries, "id", message)

  defp validate_unique_values(errors, entries, field, message) do
    values =
      entries
      |> Enum.filter(&is_map/1)
      |> Enum.map(& &1[field])
      |> Enum.filter(&non_empty_string?/1)

    if length(values) == MapSet.size(MapSet.new(values)), do: errors, else: [message | errors]
  end

  defp non_empty_string?(value), do: is_binary(value) and value != ""

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
  defdelegate migrate(package), to: Backend.Stations.StationPackage
  defdelegate validate(package), to: Backend.Stations.StationPackage
end
