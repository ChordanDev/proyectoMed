defmodule Backend.StationLoaderTest do
  use ExUnit.Case, async: true

  alias Backend.StationLoader

  @fixtures_path Path.expand("../../priv/stations/fixtures", __DIR__)
  @canonical_package_path Path.expand(
                            "../../priv/stations/chest-pain-initial-assessment/package.json",
                            __DIR__
                          )

  test "loads a valid package from the canonical active station path" do
    start_supervised!(
      {StationLoader, name: :canonical_station_loader, package_path: @canonical_package_path}
    )

    package = StationLoader.active_package(:canonical_station_loader)

    assert package["station_id"] == "chest-pain-initial-assessment"
    assert StationLoader.active_version(:canonical_station_loader) == package["version"]
    assert File.exists?(@canonical_package_path)
  end

  test "fails boot with a localized error when the package file is missing" do
    path =
      Path.join(
        System.tmp_dir!(),
        "missing-station-package-#{System.unique_integer([:positive])}.json"
      )

    assert {:error,
            {{:station_package_load_failed, message},
             {:child, :undefined, StationLoader, _start, :permanent, false, 5_000, :worker,
              [StationLoader]}}} =
             start_supervised({StationLoader, name: :missing_station_loader, package_path: path})

    assert message == "Falha ao carregar o pacote da estação em #{path}: arquivo não encontrado."
  end

  test "fails boot with a localized error when the package JSON is malformed" do
    path = write_temporary_package("{invalid")

    assert {:error,
            {{:station_package_load_failed, message},
             {:child, :undefined, StationLoader, _start, :permanent, false, 5_000, :worker,
              [StationLoader]}}} =
             start_supervised(
               {StationLoader, name: :malformed_station_loader, package_path: path}
             )

    assert message == "Falha ao carregar o pacote da estação em #{path}: JSON inválido."
  end

  test "fails boot with a localized error when a required field is invalid" do
    path = write_temporary_package("{\"version\": \"1.0.0\"}")

    assert {:error,
            {{:station_package_load_failed, message},
             {:child, :undefined, StationLoader, _start, :permanent, false, 5_000, :worker,
              [StationLoader]}}} =
             start_supervised({StationLoader, name: :invalid_station_loader, package_path: path})

    assert message ==
             "Falha ao validar o pacote da estação em #{path}: o conteúdo não atende ao contrato obrigatório."
  end

  test "runtime consumers can look up an explicitly configured test package" do
    name = :valid_station_loader
    path = fixture_path("valid-package.json")

    start_supervised!({StationLoader, name: name, package_path: path})

    assert %{"station_id" => "chest-pain-initial-assessment", "version" => "1.0.0"} =
             StationLoader.active_package(name)

    assert StationLoader.active_version(name) == "1.0.0"
  end

  defp fixture_path(name), do: Path.join(@fixtures_path, name)

  defp write_temporary_package(contents) do
    path =
      Path.join(System.tmp_dir!(), "station-package-#{System.unique_integer([:positive])}.json")

    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
