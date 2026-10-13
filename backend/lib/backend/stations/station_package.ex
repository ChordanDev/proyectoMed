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

  The authored rubric rule fields are optional (issue #128): `levels[].min_actions`,
  `actions[].role` and a criterion `rule`. Their cross-field consistency, and
  the reachability of the thresholds under `count_cap` and `first_n`, are
  checked here, because the JSON schema cannot express all of it.
  """

  alias Backend.Stations.RubricAssessment.Points
  alias Backend.Stations.TemplateApplicability

  @version "2.0.0"
  @previous_version "1.0.0"
  @required_string_fields ~w(station_id version language display_title)a
  @disclosure_conditions ~w(on_request after_action timed unconditional)
  @level_labels ~w(inadequado parcialmente_adequado adequado)
  @criterion_nullable_integer_fields ~w(order count_cap first_n)
  @criterion_positive_integer_fields ~w(count_cap first_n)
  @action_roles ~w(counted mandatory forbidden)
  @zero_scoring_action_roles ~w(mandatory forbidden)
  @criterion_rules ~w(task_order)
  @task_order_null_fields ~w(order count_cap first_n modality_requirement)
  @valid_impresso_categories ~w(physical_exam laboratory imaging report)

  @spec version() :: String.t()
  def version, do: @version

  @doc "Migrates a Station Package v1 map to the v2 contract."
  @spec migrate(map()) :: map()
  def migrate(%{"version" => @previous_version} = package) do
    package
    |> Map.put("version", @version)
    |> Map.put_new("placeholder", true)
    |> Map.update("revealable_facts", [], &migrate_facts/1)
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

  # A v1 topic is a heading that several facts may share, so the ids derived
  # from it are disambiguated against every id already present or generated.
  defp migrate_facts(facts) when is_list(facts) do
    taken = for %{"id" => id} <- facts, into: MapSet.new(), do: id
    {migrated, _taken} = Enum.map_reduce(facts, taken, &migrate_fact/2)
    migrated
  end

  defp migrate_facts(facts), do: facts

  defp migrate_fact(%{"id" => _id} = fact, taken),
    do: {Map.put_new(fact, "disclosure_condition", "on_request"), taken}

  defp migrate_fact(fact, taken) when is_map(fact) do
    id = unique_id(slug(fact["topic"]), taken)

    migrated =
      fact
      |> Map.put("id", id)
      |> Map.put_new("disclosure_condition", "on_request")

    {migrated, MapSet.put(taken, id)}
  end

  defp migrate_fact(fact, taken), do: {fact, taken}

  defp unique_id(base, taken) do
    if MapSet.member?(taken, base), do: unique_id(base, taken, 2), else: base
  end

  defp unique_id(base, taken, suffix) do
    candidate = "#{base}-#{suffix}"

    if MapSet.member?(taken, candidate),
      do: unique_id(base, taken, suffix + 1),
      else: candidate
  end

  defp migrate_criterion(criterion) when is_map(criterion) do
    {weight, criterion} = Map.pop(criterion, "weight")

    # A v1 criterion was binary: its weight when met, nothing otherwise. Without
    # the zero level an omission could only ever be classified as uncertain.
    criterion
    |> Map.put_new("levels", [
      %{
        "label" => "inadequado",
        "points" => 0,
        "description" => "Inadequate performance."
      },
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

    errors
    |> validate_unique_ids(rubric, "rubric criterion ids must be unique")
    |> validate_task_order_rubric(maps(rubric))
  end

  defp validate_rubric(errors, _package), do: ["rubric must be a list" | errors]

  defp validate_rubric_criterion(criterion, errors) when is_map(criterion) do
    errors
    |> validate_rubric_strings(criterion)
    |> validate_evidence_questions(criterion)
    |> validate_levels(criterion)
    |> validate_level_thresholds(criterion)
    |> validate_first_n_thresholds(criterion)
    |> validate_criterion_actions(criterion)
    |> validate_nullable_integer_fields(criterion)
    |> validate_positive_integer_fields(criterion)
    |> validate_criterion_boolean(criterion, "veto")
    |> validate_criterion_boolean(criterion, "exclusion")
    |> validate_modality_requirement(criterion)
    |> validate_criterion_rule(criterion)
    |> validate_forbidden_requires_veto(criterion)
    |> validate_zero_point_level(criterion)
    |> validate_task_order_criterion(criterion)
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
    |> validate_level_min_actions(level)
    |> validate_level_description(level)
  end

  defp validate_level(_level, errors), do: ["rubric levels must be objects" | errors]

  defp validate_level_label(errors, %{"label" => label}) when label in @level_labels, do: errors
  defp validate_level_label(errors, _level), do: ["rubric levels require a valid label" | errors]

  # Sign and exactness are both decided by the same conversion the assessment
  # uses, so load and assessment cannot disagree.
  defp validate_level_points(errors, %{"points" => points}) when is_number(points) do
    case Points.from_authored(points) do
      {:ok, _points} -> errors
      {:error, :negative} -> ["rubric level points must not be negative" | errors]
      {:error, _reason} -> ["rubric level points must be a multiple of 0.025" | errors]
    end
  end

  defp validate_level_points(errors, _level),
    do: ["rubric levels require numeric points" | errors]

  defp validate_level_min_actions(errors, %{"min_actions" => min_actions})
       when is_integer(min_actions) and min_actions >= 0,
       do: errors

  defp validate_level_min_actions(errors, %{"min_actions" => _invalid}),
    do: ["rubric levels min_actions must be a non-negative integer" | errors]

  defp validate_level_min_actions(errors, _level), do: errors

  # Thresholds are all-or-none across the levels of a criterion. The value
  # checks run only on a complete, well-typed set, so each defect is reported
  # by exactly one message.
  defp validate_level_thresholds(errors, %{"levels" => levels} = criterion)
       when is_list(levels) do
    levels = Enum.filter(levels, &is_map/1)
    thresholds = Enum.filter(levels, &Map.has_key?(&1, "min_actions"))

    cond do
      thresholds == [] ->
        errors

      length(thresholds) < length(levels) ->
        ["rubric criteria must set min_actions on every level or on none" | errors]

      Enum.all?(levels, &well_typed_threshold?/1) ->
        errors
        |> validate_zero_point_thresholds(levels)
        |> validate_positive_point_thresholds(levels)
        |> validate_threshold_order(levels)
        |> validate_threshold_reachability(levels, criterion)

      true ->
        errors
    end
  end

  defp validate_level_thresholds(errors, _criterion), do: errors

  defp well_typed_threshold?(%{"points" => points, "min_actions" => min_actions}),
    do: is_number(points) and is_integer(min_actions) and min_actions >= 0

  defp well_typed_threshold?(_level), do: false

  defp validate_zero_point_thresholds(errors, levels) do
    if Enum.all?(levels, &(&1["points"] != 0 or &1["min_actions"] == 0)) do
      errors
    else
      ["rubric zero-point levels must set min_actions to 0" | errors]
    end
  end

  # A positive level reachable with no action would be earned by doing nothing.
  defp validate_positive_point_thresholds(errors, levels) do
    if Enum.all?(levels, &(&1["points"] <= 0 or &1["min_actions"] >= 1)) do
      errors
    else
      ["rubric levels with points above zero must set min_actions to at least 1" | errors]
    end
  end

  defp validate_threshold_order(errors, levels) do
    thresholds =
      levels
      |> Enum.sort_by(&{&1["points"], &1["min_actions"]})
      |> Enum.map(& &1["min_actions"])

    if thresholds == Enum.sort(thresholds) do
      errors
    else
      ["rubric level min_actions must not decrease as points increase" | errors]
    end
  end

  # The highest threshold has to be earnable: the assessment counts performed
  # actions that are not forbidden, only among the first first_n answers, and
  # caps that count at count_cap. A top level out of reach would still count
  # in the station maximum.
  defp validate_threshold_reachability(errors, levels, %{"actions" => actions} = criterion)
       when is_list(actions) do
    highest = levels |> Enum.map(& &1["min_actions"]) |> Enum.max()
    countable = Enum.count(actions, &(is_map(&1) and &1["role"] != "forbidden"))

    errors
    |> validate_threshold_within_actions(highest, countable)
    |> validate_threshold_within_count_cap(highest, criterion["count_cap"])
    |> validate_threshold_within_first_n(highest, criterion["first_n"])
  end

  defp validate_threshold_reachability(errors, _levels, _criterion), do: errors

  defp validate_threshold_within_actions(errors, highest, countable) when highest <= countable,
    do: errors

  defp validate_threshold_within_actions(errors, _highest, 0),
    do: [
      "rubric criteria with thresholds require at least one action that is not forbidden" | errors
    ]

  defp validate_threshold_within_actions(errors, _highest, _countable) do
    [
      "rubric level min_actions must not exceed the number of actions that are not forbidden"
      | errors
    ]
  end

  defp validate_threshold_within_count_cap(errors, highest, count_cap)
       when is_integer(count_cap) and count_cap >= 1 and highest > count_cap,
       do: ["rubric level min_actions must not exceed count_cap" | errors]

  defp validate_threshold_within_count_cap(errors, _highest, _count_cap), do: errors

  defp validate_threshold_within_first_n(errors, highest, first_n)
       when is_integer(first_n) and first_n >= 1 and highest > first_n,
       do: ["rubric level min_actions must not exceed first_n" | errors]

  defp validate_threshold_within_first_n(errors, _highest, _first_n), do: errors

  # first_n limits the count of eligible actions. Without thresholds the level
  # would be the classifier's reading of the whole transcript, which no code
  # can limit to the first N answers. Without actions first_n has no effect.
  defp validate_first_n_thresholds(errors, %{"first_n" => first_n} = criterion)
       when is_integer(first_n) and first_n >= 1 do
    levels = criterion |> Map.get("levels") |> maps()

    add_error_if(
      errors,
      maps(criterion["actions"]) != [] and not Enum.any?(levels, &Map.has_key?(&1, "min_actions")),
      "rubric criteria with first_n and actions must author thresholds"
    )
  end

  defp validate_first_n_thresholds(errors, _criterion), do: errors

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
    errors =
      Enum.reduce(actions, errors, fn action, errors ->
        errors
        |> validate_entry(action, "rubric actions", ["id", "description"])
        |> validate_action_role(action)
      end)

    validate_unique_ids(errors, actions, "rubric action ids must be unique within a criterion")
  end

  defp validate_criterion_actions(errors, _criterion),
    do: ["rubric criteria actions must be a list" | errors]

  defp validate_action_role(errors, %{"role" => role}) when role in @action_roles, do: errors

  defp validate_action_role(errors, %{"role" => _invalid}),
    do: ["rubric actions role must be one of: #{Enum.join(@action_roles, ", ")}" | errors]

  defp validate_action_role(errors, _action), do: errors

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

  defp validate_positive_integer_fields(errors, criterion) do
    Enum.reduce(@criterion_positive_integer_fields, errors, fn field, errors ->
      value = criterion[field]

      if is_integer(value) and value < 1 do
        ["rubric criteria #{field} must be at least 1 when set" | errors]
      else
        errors
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

  defp validate_criterion_rule(errors, %{"rule" => rule})
       when is_nil(rule) or rule in @criterion_rules,
       do: errors

  defp validate_criterion_rule(errors, %{"rule" => _invalid}),
    do: ["rubric criteria rule must be #{Enum.join(@criterion_rules, ", ")} or null" | errors]

  defp validate_criterion_rule(errors, _criterion), do: errors

  defp validate_forbidden_requires_veto(errors, criterion) do
    if "forbidden" in action_roles(criterion) and criterion["veto"] != true do
      ["rubric criteria with a forbidden action must set veto to true" | errors]
    else
      errors
    end
  end

  # Thresholds and mandatory or forbidden actions score a criterion at its
  # zero-point level, so that level has to exist.
  defp validate_zero_point_level(errors, criterion) do
    levels = criterion |> Map.get("levels") |> maps()

    zero_scoring_rule? =
      Enum.any?(levels, &Map.has_key?(&1, "min_actions")) or
        Enum.any?(action_roles(criterion), &(&1 in @zero_scoring_action_roles))

    if zero_scoring_rule? and not Enum.any?(levels, &(&1["points"] == 0)) do
      [
        "rubric criteria with thresholds, mandatory or forbidden actions require a zero-point level"
        | errors
      ]
    else
      errors
    end
  end

  # The task-order criterion is assessed in code from the ranks of the other
  # criteria, so it authors no rule field of its own. Its evidence is the
  # evidence of those criteria, so a modality requirement would never apply.
  defp validate_task_order_criterion(errors, %{"rule" => "task_order"} = criterion) do
    levels = criterion |> Map.get("levels") |> maps()

    errors
    |> add_error_if(
      criterion["actions"] not in [nil, []],
      "rubric task_order criteria must not author actions"
    )
    |> add_error_if(
      Enum.any?(levels, &Map.has_key?(&1, "min_actions")),
      "rubric task_order criteria must not set min_actions"
    )
    |> validate_task_order_null_fields(criterion)
    |> add_error_if(
      criterion["veto"] == true,
      "rubric task_order criteria must set veto to false"
    )
    |> add_error_if(
      not Enum.any?(levels, &(&1["points"] == 0)),
      "rubric task_order criteria require a zero-point level"
    )
  end

  defp validate_task_order_criterion(errors, _criterion), do: errors

  defp validate_task_order_null_fields(errors, criterion) do
    Enum.reduce(@task_order_null_fields, errors, fn field, errors ->
      add_error_if(
        errors,
        not is_nil(criterion[field]),
        "rubric task_order criteria must set #{field} to null"
      )
    end)
  end

  # An order needs steps to compare: at least two other criteria with a rank.
  # An excluded criterion is never assessed, so it is not a step.
  defp validate_task_order_rubric(errors, criteria) do
    {order_criteria, others} = Enum.split_with(criteria, &(&1["rule"] == "task_order"))
    ranked = Enum.count(others, &(is_integer(&1["order"]) and &1["exclusion"] != true))

    errors
    |> add_error_if(
      length(order_criteria) > 1,
      "rubric must have at most one task_order criterion"
    )
    |> add_error_if(
      order_criteria != [] and ranked < 2,
      "rubric with a task_order criterion requires at least two other criteria with an order"
    )
  end

  defp add_error_if(errors, true, message), do: [message | errors]
  defp add_error_if(errors, false, _message), do: errors

  defp action_roles(criterion) do
    criterion |> Map.get("actions") |> maps() |> Enum.map(& &1["role"])
  end

  defp maps(entries) when is_list(entries), do: Enum.filter(entries, &is_map/1)
  defp maps(_entries), do: []

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
