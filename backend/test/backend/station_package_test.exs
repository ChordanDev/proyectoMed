defmodule Backend.StationPackageTest do
  use ExUnit.Case, async: true

  alias Backend.StationPackage

  @fixtures_path Path.expand("../../priv/stations/fixtures", __DIR__)
  @schema_path Path.expand("../../priv/stations/package.schema.json", __DIR__)

  test "validates the complete versioned package fixture" do
    package = fixture("valid-package.json")

    assert package["version"] == StationPackage.version()
    assert {:ok, ^package} = StationPackage.validate(package)
  end

  test "declares the package version and numeric rubric weight in the JSON schema" do
    schema = json_file(@schema_path)
    rubric_criterion = schema["$defs"]["rubricCriterion"]

    assert schema["properties"]["version"]["const"] == StationPackage.version()
    assert "weight" in rubric_criterion["required"]
    assert rubric_criterion["properties"]["weight"]["type"] == "number"
  end

  test "rejects a rubric criterion without a weight" do
    assert {:error, errors} =
             "invalid-package-missing-rubric-weight.json"
             |> fixture()
             |> StationPackage.validate()

    assert "rubric criteria require a numeric weight" in errors
  end

  test "rejects a rubric criterion with a non-numeric weight" do
    assert {:error, errors} =
             "invalid-package-non-numeric-rubric-weight.json"
             |> fixture()
             |> StationPackage.validate()

    assert "rubric criteria require a numeric weight" in errors
  end

  defp fixture(name) do
    @fixtures_path
    |> Path.join(name)
    |> json_file()
  end

  defp json_file(path), do: path |> File.read!() |> Jason.decode!()
end
