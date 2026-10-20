defmodule Backend.Stations.StationPackageInterpretsImpressoIdsTest do
  @moduledoc """
  The optional `interprets_impresso_ids` field of a rubric action (issue #265):
  the impressos the action interprets, so that only learner turns sent after one
  of them was released can be its evidence.
  """
  use ExUnit.Case, async: true

  alias Backend.Stations.StationPackage

  @package_path Path.expand("../../../priv/stations/acute-appendicitis/package.json", __DIR__)
  @key "interprets_impresso_ids"
  @labs_interpretation "item-07"
  @labs_request "item-06"

  defp package, do: @package_path |> File.read!() |> Jason.decode!()

  # The package without any authored `interprets_impresso_ids`.
  defp without_dependencies do
    Map.update!(package(), "rubric", fn rubric ->
      Enum.map(rubric, fn criterion ->
        Map.update!(
          criterion,
          "actions",
          &Enum.map(&1, fn action -> Map.delete(action, @key) end)
        )
      end)
    end)
  end

  defp put_action(package, criterion_id, index, key, value) do
    Map.update!(package, "rubric", fn rubric ->
      Enum.map(rubric, fn
        %{"id" => ^criterion_id} = criterion ->
          update_in(criterion, ["actions", Access.at(index)], &Map.put(&1, key, value))

        criterion ->
          criterion
      end)
    end)
  end

  test "a package without interprets_impresso_ids stays valid" do
    package = without_dependencies()

    assert {:ok, ^package} = StationPackage.validate(package)
  end

  test "accepts authored impresso ids on an action" do
    package =
      put_action(without_dependencies(), @labs_interpretation, 3, @key, [
        "impresso-2-ureia",
        "impresso-2-creatinina"
      ])

    assert {:ok, ^package} = StationPackage.validate(package)
  end

  test "rejects every invalid interprets_impresso_ids value with its own error" do
    base = without_dependencies()
    shape = "rubric actions interprets_impresso_ids must be a non-empty list of strings"

    cases = [
      {put_action(base, @labs_interpretation, 0, @key, []), shape},
      {put_action(base, @labs_interpretation, 0, @key, "impresso-2-hemograma"), shape},
      {put_action(base, @labs_interpretation, 0, @key, nil), shape},
      {put_action(base, @labs_interpretation, 0, @key, ["impresso-2-hemograma", 7]), shape},
      {put_action(base, @labs_interpretation, 0, @key, [""]), shape},
      {put_action(base, @labs_interpretation, 0, @key, ["impresso-9-unknown"]),
       "rubric actions interprets_impresso_ids must name authored impressos: impresso-9-unknown"}
    ]

    for {package, message} <- cases do
      assert {:error, errors} = StationPackage.validate(package)
      assert message in errors, "expected #{inspect(message)} in #{inspect(errors)}"
    end
  end

  test "rejects interprets_impresso_ids when the package authors no impressos" do
    package =
      without_dependencies()
      |> put_action(@labs_interpretation, 0, @key, ["impresso-2-hemograma"])
      |> Map.put("impressos", nil)

    assert {:error, errors} = StationPackage.validate(package)

    assert "rubric actions interprets_impresso_ids must name authored impressos: impresso-2-hemograma" in errors
  end

  # A request is decided by the release itself; an interpretation by what the
  # learner said afterwards. One action cannot be both.
  test "rejects an action that authors both impresso_ids and interprets_impresso_ids" do
    package =
      put_action(without_dependencies(), @labs_request, 0, @key, ["impresso-2-hemograma"])

    assert {:error, errors} = StationPackage.validate(package)

    assert "rubric actions must not author both impresso_ids and interprets_impresso_ids" in errors
  end
end
