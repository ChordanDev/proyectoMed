defmodule Backend.StationPackageTest do
  use ExUnit.Case, async: true

  alias Backend.StationPackage

  @fixtures_path Path.expand("../../priv/stations/fixtures", __DIR__)
  @schema_path Path.expand("../../priv/stations/package.schema.json", __DIR__)

  test "validates the complete v2 package fixture" do
    package = fixture("valid-package-v2.json")

    assert package["version"] == StationPackage.version()
    assert package["placeholder"] == true
    assert Enum.count(package["rubric"]) >= 3
    assert Enum.any?(package["rubric"], & &1["veto"])
    assert Enum.any?(package["rubric"], & &1["exclusion"])
    assert Enum.any?(package["rubric"], &is_binary(&1["modality_requirement"]))

    [opening, safety] = package["approved_templates"]
    assert opening["applicability"] == %{"type" => "min_learner_turns", "count" => 1}
    assert safety["applicability"] == %{"type" => "unconditional"}

    assert {:ok, ^package} = StationPackage.validate(package)
  end

  test "keeps valid-package.json as a valid v2 default fixture" do
    package = fixture("valid-package.json")

    assert {:ok, ^package} = StationPackage.validate(package)
  end

  test "canonical Backend.Stations.StationPackage and legacy Backend.StationPackage expose identical API" do
    assert Backend.Stations.StationPackage.version() == "2.0.0"
    assert StationPackage.version() == Backend.Stations.StationPackage.version()

    v1 = fixture("valid-package-v1.json")
    assert Backend.Stations.StationPackage.migrate(v1) == StationPackage.migrate(v1)

    v2 = fixture("valid-package-v2.json")
    assert Backend.Stations.StationPackage.validate(v2) == StationPackage.validate(v2)
  end

  test "migrates a v1 package to v2 and validates it" do
    v1 = fixture("valid-package-v1.json")
    migrated = StationPackage.migrate(v1)

    assert migrated["version"] == "2.0.0"
    assert migrated["placeholder"] == true

    assert [fact] = migrated["revealable_facts"]
    assert fact["id"] == "onset"
    assert fact["disclosure_condition"] == "on_request"

    assert [criterion] = migrated["rubric"]
    refute Map.has_key?(criterion, "weight")

    assert criterion["levels"] == [
             %{
               "label" => "adequado",
               "points" => 2,
               "description" => "Assesses the onset of chest pain."
             }
           ]

    assert criterion["actions"] == []
    assert criterion["order"] == nil
    assert criterion["count_cap"] == nil
    assert criterion["first_n"] == nil
    assert criterion["veto"] == false
    assert criterion["exclusion"] == false
    assert criterion["modality_requirement"] == nil
    assert {:ok, ^migrated} = StationPackage.validate(migrated)
  end

  test "JSON schema declares the optional impressos field" do
    schema = json_file(@schema_path)

    assert schema["properties"]["impressos"]["oneOf"] == [
             %{"$ref" => "#/$defs/impressos"},
             %{"type" => "null"}
           ]

    assert schema["$defs"]["impressos"]["type"] == "array"
    impresso_def = schema["$defs"]["impresso"]
    assert impresso_def["required"] == ["id", "title", "category", "keywords", "content"]
    assert impresso_def["properties"]["id"]["type"] == "string"
    assert impresso_def["properties"]["title"]["type"] == "string"

    assert impresso_def["properties"]["category"]["enum"] == [
             "physical_exam",
             "laboratory",
             "imaging",
             "report"
           ]

    assert impresso_def["properties"]["keywords"]["type"] == "array"

    assert impresso_def["properties"]["content"]["oneOf"] == [
             %{"type" => "string", "minLength" => 1},
             %{"type" => "object", "minProperties" => 1}
           ]
  end

  test "validates impressos in the valid package fixture covering all clinical categories" do
    package = fixture("valid-package.json")

    assert is_list(package["impressos"])
    assert length(package["impressos"]) == 4

    categories = Enum.map(package["impressos"], & &1["category"])
    assert "physical_exam" in categories
    assert "laboratory" in categories
    assert "imaging" in categories
    assert "report" in categories

    for impresso <- package["impressos"] do
      assert is_binary(impresso["id"]) and impresso["id"] != ""
      assert is_binary(impresso["title"]) and impresso["title"] != ""
      assert is_list(impresso["keywords"]) and impresso["keywords"] != []
      assert Enum.all?(impresso["keywords"], &(is_binary(&1) and &1 != ""))
      assert is_binary(impresso["content"]) and impresso["content"] != ""
    end

    assert {:ok, ^package} = StationPackage.validate(package)
  end

  test "accepts packages when impressos is omitted, nil, or empty list" do
    base = fixture("valid-package.json")

    omitted = Map.delete(base, "impressos")
    assert {:ok, ^omitted} = StationPackage.validate(omitted)

    with_nil = Map.put(base, "impressos", nil)
    assert {:ok, ^with_nil} = StationPackage.validate(with_nil)

    with_empty = Map.put(base, "impressos", [])
    assert {:ok, ^with_empty} = StationPackage.validate(with_empty)
  end

  test "accepts impressos with structured findings map content" do
    package =
      fixture("valid-package.json")
      |> put_in(["impressos"], [
        %{
          "id" => "laboratorio-estruturado",
          "title" => "Resultados Laboratoriais Estruturados",
          "category" => "laboratory",
          "keywords" => ["laboratório", "glicemia"],
          "content" => %{"glicemia" => 118, "troponina" => "positiva"}
        }
      ])

    assert {:ok, ^package} = StationPackage.validate(package)
  end

  test "rejects package when impressos is not a list" do
    base = fixture("valid-package.json")

    for invalid_impressos <- ["invalid", 123, %{"id" => "test"}, true] do
      package = Map.put(base, "impressos", invalid_impressos)
      assert {:error, errors} = StationPackage.validate(package)
      assert "impressos must be a list" in errors
    end
  end

  test "rejects package when an impressos entry is not an object" do
    package =
      fixture("valid-package.json")
      |> Map.put("impressos", ["not_an_object"])

    assert {:error, errors} = StationPackage.validate(package)
    assert "impressos entries must be objects" in errors
  end

  test "rejects impressos entries with missing or empty required fields" do
    base = fixture("valid-package.json")

    missing_id =
      Map.put(base, "impressos", [
        %{
          "id" => "",
          "title" => "Título",
          "category" => "physical_exam",
          "keywords" => ["exame"],
          "content" => "conteúdo"
        }
      ])

    assert {:error, errors} = StationPackage.validate(missing_id)
    assert "impressos entries require a non-empty id" in errors

    missing_title =
      Map.put(base, "impressos", [
        %{
          "id" => "teste-id",
          "title" => "",
          "category" => "physical_exam",
          "keywords" => ["exame"],
          "content" => "conteúdo"
        }
      ])

    assert {:error, errors} = StationPackage.validate(missing_title)
    assert "impressos entries require a non-empty title" in errors

    missing_category =
      Map.put(base, "impressos", [
        %{
          "id" => "teste-id",
          "title" => "Título",
          "keywords" => ["exame"],
          "content" => "conteúdo"
        }
      ])

    assert {:error, errors} = StationPackage.validate(missing_category)
    assert "impressos entries require a non-empty category" in errors
  end

  test "rejects impressos entries with invalid category" do
    package =
      fixture("valid-package.json")
      |> Map.put("impressos", [
        %{
          "id" => "teste-id",
          "title" => "Título",
          "category" => "exame_invalido",
          "keywords" => ["exame"],
          "content" => "conteúdo"
        }
      ])

    assert {:error, errors} = StationPackage.validate(package)

    assert "impressos entries category must be one of: physical_exam, laboratory, imaging, report" in errors
  end

  test "rejects impressos entries with invalid keywords" do
    base = fixture("valid-package.json")

    non_list_keywords =
      Map.put(base, "impressos", [
        %{
          "id" => "teste-id",
          "title" => "Título",
          "category" => "physical_exam",
          "keywords" => "palavra-chave-string",
          "content" => "conteúdo"
        }
      ])

    assert {:error, errors} = StationPackage.validate(non_list_keywords)
    assert "impressos entries keywords must be a list" in errors

    empty_string_keywords =
      Map.put(base, "impressos", [
        %{
          "id" => "teste-id",
          "title" => "Título",
          "category" => "physical_exam",
          "keywords" => ["valido", ""],
          "content" => "conteúdo"
        }
      ])

    assert {:error, errors} = StationPackage.validate(empty_string_keywords)
    assert "impressos entries keywords must contain non-empty strings" in errors
  end

  test "rejects impressos entries with empty content" do
    base = fixture("valid-package.json")

    empty_string_content =
      Map.put(base, "impressos", [
        %{
          "id" => "teste-id",
          "title" => "Título",
          "category" => "physical_exam",
          "keywords" => ["exame"],
          "content" => ""
        }
      ])

    assert {:error, errors} = StationPackage.validate(empty_string_content)
    assert "impressos entries require non-empty string or structured content" in errors

    empty_map_content =
      Map.put(base, "impressos", [
        %{
          "id" => "teste-id",
          "title" => "Título",
          "category" => "physical_exam",
          "keywords" => ["exame"],
          "content" => %{}
        }
      ])

    assert {:error, errors} = StationPackage.validate(empty_map_content)
    assert "impressos entries require non-empty string or structured content" in errors
  end

  test "rejects impressos with duplicate IDs" do
    package =
      fixture("valid-package.json")
      |> Map.put("impressos", [
        %{
          "id" => "exame-duplicado",
          "title" => "Exame 1",
          "category" => "physical_exam",
          "keywords" => ["exame 1"],
          "content" => "conteudo 1"
        },
        %{
          "id" => "exame-duplicado",
          "title" => "Exame 2",
          "category" => "laboratory",
          "keywords" => ["exame 2"],
          "content" => "conteudo 2"
        }
      ])

    assert {:error, errors} = StationPackage.validate(package)
    assert "impressos entries must have unique ids" in errors
  end

  test "rejects malformed impressos fixture" do
    assert {:error, errors} =
             "invalid-package-malformed-impressos.json"
             |> fixture()
             |> StationPackage.validate()

    assert "impressos entries category must be one of: physical_exam, laboratory, imaging, report" in errors
    assert "impressos entries keywords must be a list" in errors
    assert "impressos entries require non-empty string or structured content" in errors
  end

  test "migration preserves existing v2 defaults on v1-shaped content" do
    package =
      fixture("valid-package-v1.json")
      |> Map.put("placeholder", false)
      |> update_in(["revealable_facts", Access.at(0)], fn fact ->
        fact
        |> Map.put("id", "custom-id")
        |> Map.put("disclosure_condition", "unconditional")
      end)

    migrated = StationPackage.migrate(package)

    assert migrated["placeholder"] == false
    assert hd(migrated["revealable_facts"])["id"] == "custom-id"
    assert hd(migrated["revealable_facts"])["disclosure_condition"] == "unconditional"
  end

  test "JSON schema declares the v2 contract" do
    schema = json_file(@schema_path)
    criterion = schema["$defs"]["rubricCriterion"]
    level = schema["$defs"]["rubricLevel"]

    assert schema["properties"]["version"]["const"] == StationPackage.version()
    assert "placeholder" in schema["required"]
    assert schema["properties"]["placeholder"]["type"] == "boolean"

    assert schema["$defs"]["revealableFact"]["required"] == [
             "id",
             "topic",
             "content",
             "disclosure_condition"
           ]

    assert "levels" in criterion["required"]
    refute "weight" in criterion["required"]
    assert level["properties"]["points"]["multipleOf"] == 0.125

    applicability = schema["$defs"]["approvedTemplate"]["properties"]["applicability"]
    predicate = schema["$defs"]["applicabilityPredicate"]

    assert applicability == %{"$ref" => "#/$defs/applicabilityPredicate"}

    assert Enum.map(predicate["oneOf"], & &1["$ref"]) == [
             "#/$defs/unconditionalPredicate",
             "#/$defs/firstLearnerTurnPredicate",
             "#/$defs/minLearnerTurnsPredicate",
             "#/$defs/maxLearnerTurnsPredicate"
           ]

    assert schema["$defs"]["unconditionalPredicate"]["additionalProperties"] == false

    assert schema["$defs"]["minLearnerTurnsPredicate"]["required"] == ["type", "count"]

    assert schema["$defs"]["minLearnerTurnsPredicate"]["properties"]["count"] == %{
             "type" => "integer",
             "minimum" => 1
           }
  end

  test "rejects every invalid v2 fixture with its contract error" do
    cases = [
      {"invalid-package-v2-duplicate-fact-ids.json", "revealable_facts ids must be unique"},
      {"invalid-package-v2-bad-points.json", "rubric level points must be a multiple of 0.125"},
      {"invalid-package-v2-duplicate-levels.json", "rubric level labels must be unique"},
      {"invalid-package-v2-missing-placeholder.json", "placeholder must be a boolean"},
      {"invalid-package-v2-bad-disclosure.json",
       "revealable_facts entries require a valid disclosure_condition"},
      {"invalid-package-v2-prose-applicability.json",
       "approved_templates applicability must be a structured predicate object, not a prose string"},
      {"invalid-package-v2-bad-predicate.json",
       "approved_templates applicability type must be one of: unconditional, first_learner_turn, min_learner_turns, max_learner_turns"},
      {"invalid-package-v2-bad-predicate.json",
       "approved_templates min_learner_turns predicate requires an integer count >= 1"}
    ]

    Enum.each(cases, fn {fixture_name, expected_error} ->
      assert {:error, errors} = fixture_name |> fixture() |> StationPackage.validate()
      assert expected_error in errors
    end)
  end

  test "accepts every structured applicability predicate" do
    base = fixture("valid-package-v2.json")

    predicates = [
      %{"type" => "unconditional"},
      %{"type" => "first_learner_turn"},
      %{"type" => "min_learner_turns", "count" => 1},
      %{"type" => "max_learner_turns", "count" => 5}
    ]

    Enum.each(predicates, fn applicability ->
      package = put_in(base, ["approved_templates", Access.at(0), "applicability"], applicability)
      assert {:ok, ^package} = StationPackage.validate(package)
    end)
  end

  test "rejects invalid applicability with its exact error" do
    base = fixture("valid-package-v2.json")

    unknown_type_error =
      "approved_templates applicability type must be one of: unconditional, first_learner_turn, min_learner_turns, max_learner_turns"

    cases = [
      {"Use after the opening assessment.",
       "approved_templates applicability must be a structured predicate object, not a prose string"},
      {"unconditional",
       "approved_templates applicability must be a structured predicate object, not a prose string"},
      {true,
       "approved_templates applicability must be a structured predicate object, not a boolean"},
      {false,
       "approved_templates applicability must be a structured predicate object, not a boolean"},
      {nil, "approved_templates entries require an applicability predicate object"},
      {42, "approved_templates applicability must be a structured predicate object"},
      {%{}, "approved_templates applicability requires a type"},
      {%{"count" => 2}, "approved_templates applicability requires a type"},
      {%{"type" => "whenever"}, unknown_type_error},
      {%{"type" => 1}, unknown_type_error},
      {%{"type" => "min_learner_turns"},
       "approved_templates min_learner_turns predicate requires a count"},
      {%{"type" => "max_learner_turns"},
       "approved_templates max_learner_turns predicate requires a count"},
      {%{"type" => "min_learner_turns", "count" => "2"},
       "approved_templates min_learner_turns predicate requires an integer count >= 1"},
      {%{"type" => "min_learner_turns", "count" => 0},
       "approved_templates min_learner_turns predicate requires an integer count >= 1"},
      {%{"type" => "max_learner_turns", "count" => 0},
       "approved_templates max_learner_turns predicate requires an integer count >= 1"},
      {%{"type" => "unconditional", "count" => 1},
       "approved_templates unconditional predicates must not include additional fields"},
      {%{"type" => "first_learner_turn", "extra" => true},
       "approved_templates first_learner_turn predicates must not include additional fields"}
    ]

    Enum.each(cases, fn {applicability, expected_error} ->
      package = put_in(base, ["approved_templates", Access.at(0), "applicability"], applicability)
      assert {:error, errors} = StationPackage.validate(package)

      assert expected_error in errors,
             "expected #{inspect(expected_error)} for #{inspect(applicability)}"
    end)
  end

  test "rejects approved templates missing the applicability key" do
    package = fixture("valid-package-v2.json")

    package =
      Map.update!(package, "approved_templates", fn [first | rest] ->
        [Map.delete(first, "applicability") | rest]
      end)

    assert {:error, errors} = StationPackage.validate(package)

    assert "approved_templates entries require an applicability predicate object" in errors
  end

  test "rejects approved templates with atom-keyed false applicability as boolean" do
    base = fixture("valid-package-v2.json")

    package =
      Map.update!(base, "approved_templates", fn [first | rest] ->
        first =
          first
          |> Map.delete("applicability")
          |> Map.put(:applicability, false)

        [first | rest]
      end)

    assert {:error, errors} = StationPackage.validate(package)

    assert "approved_templates applicability must be a structured predicate object, not a boolean" in errors
  end

  test "requires at least one rubric level" do
    package = put_in(fixture("valid-package.json"), ["rubric", Access.at(0), "levels"], [])

    assert {:error, errors} = StationPackage.validate(package)
    assert "rubric criteria require at least one level" in errors
  end

  test "accepts points at 0.125 granularity" do
    package =
      put_in(
        fixture("valid-package.json"),
        ["rubric", Access.at(0), "levels", Access.at(0), "points"],
        0.125
      )

    assert {:ok, ^package} = StationPackage.validate(package)
  end

  test "rejects duplicate revealable fact ids" do
    package = fixture("valid-package-v2.json")
    [first, second | rest] = package["revealable_facts"]

    package =
      Map.put(package, "revealable_facts", [first, %{second | "id" => first["id"]} | rest])

    assert {:error, errors} = StationPackage.validate(package)
    assert "revealable_facts ids must be unique" in errors
  end

  test "rejects duplicate approved template ids" do
    package = fixture("valid-package-v2.json")
    [first, second] = package["approved_templates"]

    package =
      Map.put(package, "approved_templates", [
        first,
        %{second | "template_id" => first["template_id"]}
      ])

    assert {:error, errors} = StationPackage.validate(package)
    assert "approved_templates template_ids must be unique" in errors
  end

  test "rejects duplicate rubric criterion ids" do
    package = fixture("valid-package-v2.json")
    [first, second | rest] = package["rubric"]
    package = Map.put(package, "rubric", [first, %{second | "id" => first["id"]} | rest])

    assert {:error, errors} = StationPackage.validate(package)
    assert "rubric criterion ids must be unique" in errors
  end

  test "approved template text remains byte-exact in the validated package" do
    package = fixture("valid-package-v2.json")
    expected_text = "Resuma o motivo da consulta."

    assert {:ok, validated} = StationPackage.validate(package)
    assert hd(validated["approved_templates"])["text"] === expected_text
  end

  test "partial reconciliation fixture yields the expected score boundaries" do
    package = fixture("valid-package-v2-partial-reconciliation.json")
    assert {:ok, ^package} = StationPackage.validate(package)

    [criterion_a, criterion_b] = package["rubric"]
    selected_a = Enum.find(criterion_a["levels"], &(&1["label"] == "parcialmente_adequado"))

    subtotal = selected_a["points"]
    scored_max = Enum.max_by(criterion_a["levels"], & &1["points"])["points"]

    eligible_max =
      package["rubric"]
      |> Enum.reject(& &1["exclusion"])
      |> Enum.map(fn criterion -> Enum.max_by(criterion["levels"], & &1["points"])["points"] end)
      |> Enum.sum()

    unresolved_ids = Enum.filter([criterion_b["id"]], &is_binary/1)
    total = if Enum.empty?(unresolved_ids), do: subtotal, else: nil

    assert subtotal == 0.25
    assert scored_max == 0.25
    assert eligible_max == 1.25
    assert total == nil
  end

  describe "authored rule fields" do
    @history 0
    @treatment 1
    @exams 2
    @order 3

    defp authored_rules, do: fixture("valid-package-v2-authored-rules.json")

    defp put_criterion(package, index, path, value) do
      put_in(package, ["rubric", Access.at(index) | path], value)
    end

    defp delete_min_actions(package, index, level_index) do
      update_in(
        package,
        ["rubric", Access.at(index), "levels", Access.at(level_index)],
        fn level ->
          Map.delete(level, "min_actions")
        end
      )
    end

    test "validates a fixture that exercises every authored rule field" do
      package = authored_rules()
      rubric = package["rubric"]
      levels = Enum.flat_map(rubric, & &1["levels"])
      actions = Enum.flat_map(rubric, & &1["actions"])

      assert Enum.any?(levels, &is_integer(&1["min_actions"]))
      assert Enum.any?(levels, &(not Map.has_key?(&1, "min_actions")))

      for role <- ["counted", "mandatory", "forbidden"] do
        assert Enum.any?(actions, &(&1["role"] == role))
      end

      assert Enum.any?(actions, &(not Map.has_key?(&1, "role")))
      assert Enum.any?(rubric, &(&1["rule"] == "task_order"))
      assert Enum.any?(rubric, &(Map.has_key?(&1, "rule") and is_nil(&1["rule"])))
      assert Enum.any?(rubric, &(not Map.has_key?(&1, "rule")))
      assert Enum.any?(rubric, &is_integer(&1["count_cap"]))
      assert Enum.any?(rubric, &is_integer(&1["first_n"]))
      assert Enum.any?(rubric, & &1["veto"])

      assert {:ok, ^package} = StationPackage.validate(package)
    end

    test "JSON schema declares the optional authored rule fields" do
      schema = json_file(@schema_path)
      criterion = schema["$defs"]["rubricCriterion"]
      level = schema["$defs"]["rubricLevel"]
      action = schema["$defs"]["rubricAction"]

      assert level["properties"]["min_actions"] == %{"type" => "integer", "minimum" => 0}
      refute "min_actions" in level["required"]

      assert action["properties"]["role"] == %{
               "enum" => ["counted", "mandatory", "forbidden"],
               "default" => "counted"
             }

      refute "role" in action["required"]

      assert criterion["properties"]["rule"] == %{"enum" => [nil, "task_order"], "default" => nil}
      refute "rule" in criterion["required"]

      assert criterion["properties"]["count_cap"] == %{
               "type" => ["integer", "null"],
               "minimum" => 1
             }

      assert criterion["properties"]["first_n"] == %{
               "type" => ["integer", "null"],
               "minimum" => 1
             }
    end

    test "accepts thresholds of equal value on increasing points" do
      package =
        put_criterion(authored_rules(), @history, ["levels", Access.at(2), "min_actions"], 2)

      assert {:ok, ^package} = StationPackage.validate(package)
    end

    test "rejects every authored rule violation with its own error" do
      base = authored_rules()

      cases = [
        {put_criterion(base, @history, ["levels", Access.at(1), "min_actions"], -1),
         "rubric levels min_actions must be a non-negative integer"},
        {put_criterion(base, @history, ["levels", Access.at(1), "min_actions"], "2"),
         "rubric levels min_actions must be a non-negative integer"},
        {put_criterion(base, @history, ["levels", Access.at(1), "min_actions"], nil),
         "rubric levels min_actions must be a non-negative integer"},
        {put_criterion(base, @history, ["actions", Access.at(1), "role"], "optional"),
         "rubric actions role must be one of: counted, mandatory, forbidden"},
        {put_criterion(base, @history, ["actions", Access.at(1), "role"], nil),
         "rubric actions role must be one of: counted, mandatory, forbidden"},
        {put_criterion(base, @history, ["rule"], "pairwise_gate"),
         "rubric criteria rule must be task_order or null"},
        {put_criterion(base, @history, ["rule"], true),
         "rubric criteria rule must be task_order or null"},
        {put_criterion(base, @history, ["count_cap"], 0),
         "rubric criteria count_cap must be at least 1 when set"},
        {put_criterion(base, @exams, ["first_n"], 0),
         "rubric criteria first_n must be at least 1 when set"},
        {put_criterion(base, @exams, ["first_n"], -3),
         "rubric criteria first_n must be at least 1 when set"},
        {put_criterion(base, @history, ["actions", Access.at(1), "id"], "ask-onset"),
         "rubric action ids must be unique within a criterion"},
        {delete_min_actions(base, @history, 1),
         "rubric criteria must set min_actions on every level or on none"},
        {put_criterion(base, @history, ["levels", Access.at(0), "min_actions"], 1),
         "rubric zero-point levels must set min_actions to 0"},
        {put_criterion(base, @history, ["levels", Access.at(2), "min_actions"], 1),
         "rubric level min_actions must not decrease as points increase"},
        {put_criterion(base, @treatment, ["veto"], false),
         "rubric criteria with a forbidden action must set veto to true"},
        {put_criterion(base, @exams, ["levels", Access.at(0), "points"], 0.125),
         "rubric criteria with thresholds, mandatory or forbidden actions require a zero-point level"},
        {put_criterion(base, @treatment, ["levels", Access.at(0), "points"], 0.5),
         "rubric criteria with thresholds, mandatory or forbidden actions require a zero-point level"}
      ]

      Enum.each(cases, fn {package, expected_error} ->
        assert {:error, errors} = StationPackage.validate(package)

        assert expected_error in errors,
               "expected #{inspect(expected_error)} in #{inspect(errors)}"
      end)
    end

    test "each threshold violation reports only its own threshold error" do
      threshold_errors = [
        "rubric criteria must set min_actions on every level or on none",
        "rubric zero-point levels must set min_actions to 0",
        "rubric level min_actions must not decrease as points increase"
      ]

      cases = [
        {delete_min_actions(authored_rules(), @history, 1), Enum.at(threshold_errors, 0)},
        {put_criterion(authored_rules(), @history, ["levels", Access.at(2), "min_actions"], 1),
         Enum.at(threshold_errors, 2)}
      ]

      Enum.each(cases, fn {package, expected_error} ->
        assert {:error, errors} = StationPackage.validate(package)
        assert Enum.filter(errors, &(&1 in threshold_errors)) == [expected_error]
      end)
    end

    test "rejects thresholds that grade wrongly, each with only its own error" do
      base = authored_rules()

      threshold_errors = [
        "rubric criteria must set min_actions on every level or on none",
        "rubric zero-point levels must set min_actions to 0",
        "rubric level min_actions must not decrease as points increase",
        "rubric levels with points above zero must set min_actions to at least 1",
        "rubric level min_actions must not exceed the number of actions that are not forbidden",
        "rubric level min_actions must not exceed count_cap",
        "rubric criteria with thresholds require at least one action that is not forbidden"
      ]

      uncapped = put_criterion(base, @history, ["count_cap"], nil)

      two_countable_actions =
        uncapped
        |> put_criterion(@history, ["veto"], true)
        |> put_criterion(@history, ["actions", Access.at(2), "role"], "forbidden")
        |> put_criterion(@history, ["actions", Access.at(3), "role"], "forbidden")

      cases = [
        {put_criterion(base, @history, ["levels", Access.at(1), "min_actions"], 0),
         Enum.at(threshold_errors, 3)},
        {base
         |> put_criterion(@history, ["levels", Access.at(1), "min_actions"], 0)
         |> put_criterion(@history, ["levels", Access.at(2), "min_actions"], 0),
         Enum.at(threshold_errors, 3)},
        {put_criterion(uncapped, @history, ["levels", Access.at(2), "min_actions"], 9),
         Enum.at(threshold_errors, 4)},
        {two_countable_actions, Enum.at(threshold_errors, 4)},
        {put_criterion(base, @history, ["count_cap"], 2), Enum.at(threshold_errors, 5)},
        {put_criterion(base, @exams, ["actions"], []), Enum.at(threshold_errors, 6)}
      ]

      Enum.each(cases, fn {package, expected_error} ->
        assert {:error, errors} = StationPackage.validate(package)

        assert Enum.filter(errors, &(&1 in threshold_errors)) == [expected_error],
               "expected only #{inspect(expected_error)} in #{inspect(errors)}"
      end)
    end

    test "accepts a top threshold equal to the number of countable actions" do
      package =
        authored_rules()
        |> put_criterion(@history, ["count_cap"], nil)
        |> put_criterion(@history, ["levels", Access.at(2), "min_actions"], 4)

      assert {:ok, ^package} = StationPackage.validate(package)
    end

    test "rejects a top threshold that the first N answers cannot reach" do
      first_n_error = "rubric level min_actions must not exceed first_n"
      uncapped = put_criterion(authored_rules(), @history, ["count_cap"], nil)

      # history-taking authors thresholds 0/2/3 over four countable actions.
      assert {:error, errors} =
               StationPackage.validate(put_criterion(uncapped, @history, ["first_n"], 2))

      assert errors == [first_n_error]

      # Both caps out of reach are two defects, each with its own message.
      assert {:error, errors} =
               authored_rules()
               |> put_criterion(@history, ["count_cap"], 2)
               |> put_criterion(@history, ["first_n"], 2)
               |> StationPackage.validate()

      assert Enum.sort(errors) ==
               ["rubric level min_actions must not exceed count_cap", first_n_error]
    end

    test "accepts first_n at or above the top threshold" do
      for first_n <- [3, 4] do
        package = put_criterion(authored_rules(), @history, ["first_n"], first_n)

        assert {:ok, ^package} = StationPackage.validate(package)
      end
    end

    test "rejects first_n on a criterion with actions and no thresholds" do
      # treatment-plan authors actions and no thresholds.
      package = put_criterion(authored_rules(), @treatment, ["first_n"], 1)

      assert StationPackage.validate(package) ==
               {:error, ["rubric criteria with first_n and actions must author thresholds"]}
    end

    test "accepts first_n on a criterion without actions, where it has no effect" do
      package =
        authored_rules()
        |> put_criterion(@treatment, ["first_n"], 1)
        |> put_criterion(@treatment, ["actions"], [])

      assert {:ok, ^package} = StationPackage.validate(package)

      # The base v2 fixture relies on it.
      assert {:ok, %{"rubric" => rubric}} =
               StationPackage.validate(fixture("valid-package-v2.json"))

      assert Enum.any?(rubric, &(is_integer(&1["first_n"]) and &1["actions"] == []))
    end

    test "JSON schema requires thresholds where first_n and actions are both authored" do
      criterion = json_file(@schema_path)["$defs"]["rubricCriterion"]

      assert %{
               "if" => %{
                 "required" => ["first_n", "actions"],
                 "properties" => %{
                   "first_n" => %{"type" => "integer"},
                   "actions" => %{"minItems" => 1}
                 }
               },
               "then" => %{
                 "properties" => %{"levels" => %{"items" => %{"required" => ["min_actions"]}}}
               }
             } in criterion["allOf"]

      assert criterion["description"] =~ "first_n and at least one action must author thresholds"
    end

    test "JSON schema documents the first_n reachability rule" do
      description = json_file(@schema_path)["$defs"]["rubricCriterion"]["description"]

      assert description =~ "at most first_n when first_n is set"
    end

    test "JSON schema requires a positive threshold on levels with points above zero" do
      level = json_file(@schema_path)["$defs"]["rubricLevel"]

      assert %{
               "if" => %{
                 "required" => ["points", "min_actions"],
                 "properties" => %{"points" => %{"exclusiveMinimum" => 0}}
               },
               "then" => %{"properties" => %{"min_actions" => %{"minimum" => 1}}}
             } in level["allOf"]
    end

    test "rejects every task_order violation with only its own error" do
      base = authored_rules()
      [_history, _treatment, _exams, order] = base["rubric"]

      task_order_errors = [
        "rubric must have at most one task_order criterion",
        "rubric task_order criteria must not author actions",
        "rubric task_order criteria must not set min_actions",
        "rubric task_order criteria must set order to null",
        "rubric task_order criteria must set count_cap to null",
        "rubric task_order criteria must set first_n to null",
        "rubric task_order criteria must set veto to false",
        "rubric task_order criteria require a zero-point level",
        "rubric with a task_order criterion requires at least two other criteria with an order",
        "rubric task_order criteria must set modality_requirement to null"
      ]

      second = Map.put(order, "id", "task-order-b")
      action = %{"id" => "follow-order", "description" => "Follow the order."}

      with_thresholds =
        base
        |> put_criterion(@order, ["levels", Access.at(0), "min_actions"], 0)
        |> put_criterion(@order, ["levels", Access.at(1), "min_actions"], 1)

      cases = [
        {Map.update!(base, "rubric", &(&1 ++ [second])), Enum.at(task_order_errors, 0)},
        {put_criterion(base, @order, ["actions"], [action]), Enum.at(task_order_errors, 1)},
        {with_thresholds, Enum.at(task_order_errors, 2)},
        {put_criterion(base, @order, ["order"], 4), Enum.at(task_order_errors, 3)},
        {put_criterion(base, @order, ["count_cap"], 1), Enum.at(task_order_errors, 4)},
        {put_criterion(base, @order, ["first_n"], 2), Enum.at(task_order_errors, 5)},
        {put_criterion(base, @order, ["veto"], true), Enum.at(task_order_errors, 6)},
        {put_criterion(base, @order, ["levels", Access.at(0), "points"], 0.125),
         Enum.at(task_order_errors, 7)},
        {base
         |> put_criterion(@treatment, ["order"], nil)
         |> put_criterion(@exams, ["order"], nil), Enum.at(task_order_errors, 8)},
        {put_criterion(base, @order, ["modality_requirement"], "verbal"),
         Enum.at(task_order_errors, 9)}
      ]

      Enum.each(cases, fn {package, expected_error} ->
        assert {:error, errors} = StationPackage.validate(package)

        assert Enum.filter(errors, &(&1 in task_order_errors)) == [expected_error],
               "expected only #{inspect(expected_error)} in #{inspect(errors)}"
      end)
    end

    test "an excluded criterion is not a ranked step of the task order" do
      # Only history-taking is left as a ranked criterion the order pass reads.
      package =
        authored_rules()
        |> put_criterion(@treatment, ["order"], nil)
        |> put_criterion(@exams, ["exclusion"], true)

      assert StationPackage.validate(package) ==
               {:error,
                [
                  "rubric with a task_order criterion requires at least two other criteria with an order"
                ]}

      # Two ranked criteria that are not excluded are enough.
      package = put_criterion(authored_rules(), @exams, ["exclusion"], true)

      assert {:ok, ^package} = StationPackage.validate(package)
    end

    test "a task_order criterion needs only two ranked criteria, and equal ranks are valid" do
      package =
        authored_rules()
        |> put_criterion(@history, ["order"], nil)
        |> put_criterion(@exams, ["order"], 2)

      assert {:ok, ^package} = StationPackage.validate(package)
    end

    test "the task_order constraints do not apply to other criteria" do
      package = put_criterion(authored_rules(), @order, ["rule"], nil)

      assert {:ok, ^package} = StationPackage.validate(package)
    end

    test "JSON schema constrains a task_order criterion and the rubric that has one" do
      schema = json_file(@schema_path)
      criterion = schema["$defs"]["rubricCriterion"]
      rubric = schema["$defs"]["rubric"]

      task_order = %{
        "required" => ["rule"],
        "properties" => %{"rule" => %{"const" => "task_order"}}
      }

      assert [%{"if" => ^task_order, "then" => %{"properties" => constrained}}, _first_n] =
               criterion["allOf"]

      assert constrained["actions"] == %{"maxItems" => 0}
      assert constrained["order"] == %{"type" => "null"}
      assert constrained["count_cap"] == %{"type" => "null"}
      assert constrained["first_n"] == %{"type" => "null"}
      assert constrained["veto"] == %{"const" => false}
      assert constrained["modality_requirement"] == %{"type" => "null"}

      assert constrained["levels"] == %{
               "contains" => %{"properties" => %{"points" => %{"const" => 0}}},
               "items" => %{"not" => %{"required" => ["min_actions"]}}
             }

      assert rubric["if"] == %{"contains" => task_order}

      assert rubric["then"] == %{
               "contains" => task_order,
               "maxContains" => 1,
               "allOf" => [
                 %{
                   "contains" => %{
                     "required" => ["order"],
                     "properties" => %{
                       "order" => %{"type" => "integer"},
                       "exclusion" => %{"const" => false}
                     }
                   },
                   "minContains" => 2
                 }
               ]
             }
    end

    test "the same action id may be reused by different criteria" do
      package =
        put_criterion(authored_rules(), @exams, ["actions", Access.at(0), "id"], "ask-onset")

      assert {:ok, ^package} = StationPackage.validate(package)
    end

    test "veto without a forbidden action stays valid" do
      package = put_criterion(authored_rules(), @history, ["veto"], true)

      assert {:ok, ^package} = StationPackage.validate(package)
    end
  end

  defp fixture(name) do
    @fixtures_path
    |> Path.join(name)
    |> json_file()
  end

  defp json_file(path), do: path |> File.read!() |> Jason.decode!()
end
