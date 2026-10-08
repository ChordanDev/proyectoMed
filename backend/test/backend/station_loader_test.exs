defmodule Backend.StationLoaderTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Backend.StationLoader

  @fixtures_path Path.expand("../../priv/stations/fixtures", __DIR__)
  @canonical_package_path Application.app_dir(
                            :backend,
                            "priv/stations/chest-pain-initial-assessment/package.json"
                          )

  test "load_active loads the valid package from the canonical active station path" do
    package = StationLoader.load_active()

    assert package["station_id"] == "chest-pain-initial-assessment"
    assert is_list(package["impressos"])
    assert length(package["impressos"]) == 4
    assert File.exists?(@canonical_package_path)
  end

  test "load_active logs and raises a localized error when the package file is missing" do
    with_canonical_package(nil, fn ->
      assert capture_log(fn ->
               assert_raise RuntimeError,
                            "Falha ao carregar o pacote ativo da estação: arquivo não encontrado.",
                            fn ->
                              StationLoader.load_active()
                            end
             end) =~ "Falha ao carregar o pacote ativo da estação: arquivo não encontrado."
    end)
  end

  test "load_active logs and raises a localized error when the package JSON is malformed" do
    with_canonical_package("{invalid", fn ->
      assert capture_log(fn ->
               assert_raise RuntimeError,
                            "Falha ao carregar o pacote ativo da estação: JSON inválido.",
                            fn ->
                              StationLoader.load_active()
                            end
             end) =~ "Falha ao carregar o pacote ativo da estação: JSON inválido."
    end)
  end

  test "load_active logs and raises a localized error when a required field is invalid" do
    with_canonical_package(~s({"version": "1.0.0"}), fn ->
      assert capture_log(fn ->
               assert_raise RuntimeError,
                            "Falha ao validar o pacote ativo da estação: o conteúdo não atende ao contrato obrigatório.",
                            fn ->
                              StationLoader.load_active()
                            end
             end) =~
               "Falha ao validar o pacote ativo da estação: o conteúdo não atende ao contrato obrigatório."
    end)
  end

  test "load_active logs and raises a localized error when the package language is not pt-BR" do
    package = fixture_path("valid-package.json") |> File.read!() |> Jason.decode!()
    wrong_language_package = put_in(package, ["language"], "en-US") |> Jason.encode!()

    with_canonical_package(wrong_language_package, fn ->
      assert capture_log(fn ->
               assert_raise RuntimeError,
                            "Falha ao validar o pacote ativo da estação: o conteúdo não atende ao contrato obrigatório.",
                            fn ->
                              StationLoader.load_active()
                            end
             end) =~
               "Falha ao validar o pacote ativo da estação: o conteúdo não atende ao contrato obrigatório."
    end)
  end

  test "load_active logs and raises a localized error when impressos is malformed" do
    package = fixture_path("valid-package.json") |> File.read!() |> Jason.decode!()
    malformed_impressos_package = put_in(package, ["impressos"], "not_a_list") |> Jason.encode!()

    with_canonical_package(malformed_impressos_package, fn ->
      assert capture_log(fn ->
               assert_raise RuntimeError,
                            "Falha ao validar o pacote ativo da estação: o conteúdo não atende ao contrato obrigatório.",
                            fn ->
                              StationLoader.load_active()
                            end
             end) =~
               "Falha ao validar o pacote ativo da estação: o conteúdo não atende ao contrato obrigatório."
    end)
  end

  defp fixture_path(name), do: Path.join(@fixtures_path, name)

  defp with_canonical_package(contents, test) do
    original = File.read!(@canonical_package_path)

    on_exit(fn -> File.write!(@canonical_package_path, original) end)

    case contents do
      nil -> File.rm!(@canonical_package_path)
      _ -> File.write!(@canonical_package_path, contents)
    end

    test.()
  end
end
