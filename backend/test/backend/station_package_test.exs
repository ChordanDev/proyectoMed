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
    assert {:ok, ^package} = StationPackage.validate(package)
  end

  test "keeps valid-package.json as a valid v2 default fixture" do
    package = fixture("valid-package.json")

    assert {:ok, ^package} = StationPackage.validate(package)
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
  end

  test "rejects every invalid v2 fixture with its contract error" do
    cases = [
      {"invalid-package-v2-duplicate-fact-ids.json", "revealable_facts ids must be unique"},
      {"invalid-package-v2-bad-points.json", "rubric level points must be a multiple of 0.125"},
      {"invalid-package-v2-duplicate-levels.json", "rubric level labels must be unique"},
      {"invalid-package-v2-missing-placeholder.json", "placeholder must be a boolean"},
      {"invalid-package-v2-bad-disclosure.json",
       "revealable_facts entries require a valid disclosure_condition"}
    ]

    Enum.each(cases, fn {fixture_name, expected_error} ->
      assert {:error, errors} = fixture_name |> fixture() |> StationPackage.validate()
      assert expected_error in errors
    end)
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
