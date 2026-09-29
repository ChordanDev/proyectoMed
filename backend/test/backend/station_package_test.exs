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

  defp fixture(name) do
    @fixtures_path
    |> Path.join(name)
    |> json_file()
  end

  defp json_file(path), do: path |> File.read!() |> Jason.decode!()
end
