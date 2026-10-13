defmodule Backend.Stations.AcuteAppendicitisPackageTest do
  use ExUnit.Case, async: true

  alias Backend.Stations.RubricAssessment.AuthoredRules
  alias Backend.Stations.RubricAssessment.Points
  alias Backend.Stations.StationPackage

  @package_path Path.expand(
                  "../../../priv/stations/acute-appendicitis/package.json",
                  __DIR__
                )

  @labels ~w(inadequado parcialmente_adequado adequado)

  # The partner's PEP, items 1 to 11: the points of each level as exact decimal
  # strings and the count thresholds, both as {inadequado, parcialmente
  # adequado, adequado}.
  @authored [
    {"item-01", {"0", "0.1", "0.2"}, {0, 1, 2}},
    {"item-02", {"0", "0.4", "0.8"}, {0, 3, 5}},
    {"item-03", {"0", "0.4", "0.8"}, {0, 2, 4}},
    {"item-04", {"0", "0.3", "0.6"}, {0, 2, 4}},
    {"item-05", {"0", "0.6", "1.2"}, {0, 2, 3}},
    {"item-06", {"0", "0.4", "0.8"}, {0, 2, 3}},
    {"item-07", {"0", "0.4", "0.8"}, {0, 2, 3}},
    {"item-08", {"0", "0.7", "1.4"}, {0, 1, 4}},
    {"item-09", {"0", "0.6", "1.2"}, {0, 2, 4}},
    {"item-10", {"0", "0.6", "1.2"}, {0, 2, 3}},
    {"item-11", {"0", "0.5", "1"}, {0, 2, 3}}
  ]

  defp package, do: @package_path |> File.read!() |> Jason.decode!()

  defp level(criterion, label), do: Enum.find(criterion["levels"], &(&1["label"] == label))

  defp points(criterion, label) do
    {:ok, points} = Points.from_authored(level(criterion, label)["points"])
    points
  end

  defp roles(criterion) do
    for %{"id" => id, "role" => role} <- criterion["actions"], role != "counted", do: {id, role}
  end

  test "decodes and passes the package contract" do
    package = package()

    assert {:ok, ^package} = StationPackage.validate(package)
  end

  test "is the pt-BR acute appendicitis station, still a placeholder" do
    package = package()

    assert package["station_id"] == "acute-appendicitis"
    assert package["version"] == StationPackage.version()
    assert package["language"] == "pt-BR"
    assert package["placeholder"] == true
  end

  test "authors the eleven items in order, each with the three levels" do
    rubric = package()["rubric"]

    assert Enum.map(rubric, & &1["id"]) == Enum.map(@authored, &elem(&1, 0))

    for criterion <- rubric do
      assert Enum.map(criterion["levels"], & &1["label"]) == @labels
    end
  end

  test "keeps the partner's points for every level" do
    rubric = package()["rubric"]

    authored =
      for criterion <- rubric do
        decimals = Enum.map(@labels, &Points.to_decimal_string(points(criterion, &1)))
        {criterion["id"], List.to_tuple(decimals)}
      end

    assert authored == Enum.map(@authored, fn {id, points, _thresholds} -> {id, points} end)
  end

  test "keeps the partner's count thresholds for every level" do
    rubric = package()["rubric"]

    authored =
      for criterion <- rubric do
        thresholds = Enum.map(@labels, &level(criterion, &1)["min_actions"])
        {criterion["id"], List.to_tuple(thresholds)}
      end

    assert authored == Enum.map(@authored, fn {id, _points, thresholds} -> {id, thresholds} end)
  end

  test "the adequado levels total exactly 10 points" do
    total = package()["rubric"] |> Enum.map(&points(&1, "adequado")) |> Points.sum()

    assert total == 400
    assert Points.to_decimal_string(total) == "10"
  end

  test "authors a role only where the partner's levels name a single action" do
    non_counted =
      for criterion <- package()["rubric"], roles(criterion) != [] do
        {criterion["id"], roles(criterion), criterion["veto"]}
      end

    assert non_counted == [
             {"item-07", [{"atribuicao-a-infeccao-urinaria", "forbidden"}], true},
             {"item-08", [{"criterio-4", "mandatory"}], false}
           ]
  end

  test "every criterion has rule fields the assessment can apply" do
    for criterion <- package()["rubric"] do
      assert AuthoredRules.check(criterion) == :ok
      assert criterion["exclusion"] == false
      assert criterion["rule"] == nil
    end
  end
end
