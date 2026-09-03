defmodule Backend.StationLoaderTest do
  use ExUnit.Case, async: true

  alias Backend.StationLoader

  @fixtures_path Path.expand("../../priv/stations/fixtures", __DIR__)

  test "application boot loads the configured valid package" do
    package = StationLoader.active_package()

    assert package["station_id"] == "chest-pain-initial-assessment"
    assert StationLoader.active_version() == package["version"]
  end

  test "fails to start when the package does not meet the validation contract" do
    name = :invalid_station_loader
    path = fixture_path("invalid-package-missing-rubric-weight.json")

    assert {:error,
            {{:invalid_station_package, ^path, errors},
             {:child, :undefined, StationLoader, _start, :permanent, false, 5_000, :worker,
              [StationLoader]}}} =
             start_supervised({StationLoader, name: name, package_path: path})

    assert "rubric criteria require a numeric weight" in errors
  end

  test "runtime consumers can look up the active package and version" do
    name = :valid_station_loader
    path = fixture_path("valid-package.json")

    start_supervised!({StationLoader, name: name, package_path: path})

    assert %{"station_id" => "chest-pain-initial-assessment", "version" => "1.0.0"} =
             StationLoader.active_package(name)

    assert StationLoader.active_version(name) == "1.0.0"
  end

  defp fixture_path(name), do: Path.join(@fixtures_path, name)
end
