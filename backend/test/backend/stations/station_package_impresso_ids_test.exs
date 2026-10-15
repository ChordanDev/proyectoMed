defmodule Backend.Stations.StationPackageImpressoIdsTest do
  @moduledoc """
  The optional `impresso_ids` field of a rubric action (issue #228): the
  impressos whose release means the learner requested what the action asks.
  """
  use ExUnit.Case, async: true

  alias Backend.Stations.StationPackage

  @package_path Path.expand("../../../priv/stations/acute-appendicitis/package.json", __DIR__)
  @labs "item-06"

  defp package, do: @package_path |> File.read!() |> Jason.decode!()

  # The package without any authored `impresso_ids`.
  defp without_impresso_ids do
    Map.update!(package(), "rubric", &Enum.map(&1, fn criterion -> strip(criterion) end))
  end

  defp strip(criterion) do
    Map.update!(
      criterion,
      "actions",
      &Enum.map(&1, fn action -> Map.delete(action, "impresso_ids") end)
    )
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

  defp put_criterion(package, criterion_id, key, value) do
    Map.update!(package, "rubric", fn rubric ->
      Enum.map(rubric, fn
        %{"id" => ^criterion_id} = criterion -> Map.put(criterion, key, value)
        criterion -> criterion
      end)
    end)
  end

  test "a package without impresso_ids stays valid" do
    package = without_impresso_ids()

    assert {:ok, ^package} = StationPackage.validate(package)
  end

  test "accepts authored impresso ids on an action" do
    package =
      put_action(without_impresso_ids(), @labs, 3, "impresso_ids", [
        "impresso-2-ureia",
        "impresso-2-creatinina"
      ])

    assert {:ok, ^package} = StationPackage.validate(package)
  end

  test "rejects every invalid impresso_ids value with its own error" do
    base = without_impresso_ids()

    cases = [
      {put_action(base, @labs, 0, "impresso_ids", []),
       "rubric actions impresso_ids must be a non-empty list of strings"},
      {put_action(base, @labs, 0, "impresso_ids", "impresso-2-hemograma"),
       "rubric actions impresso_ids must be a non-empty list of strings"},
      {put_action(base, @labs, 0, "impresso_ids", nil),
       "rubric actions impresso_ids must be a non-empty list of strings"},
      {put_action(base, @labs, 0, "impresso_ids", ["impresso-2-hemograma", 7]),
       "rubric actions impresso_ids must be a non-empty list of strings"},
      {put_action(base, @labs, 0, "impresso_ids", [""]),
       "rubric actions impresso_ids must be a non-empty list of strings"},
      {put_action(base, @labs, 0, "impresso_ids", ["impresso-9-unknown"]),
       "rubric actions impresso_ids must name authored impressos: impresso-9-unknown"}
    ]

    for {package, message} <- cases do
      assert {:error, errors} = StationPackage.validate(package)
      assert message in errors, "expected #{inspect(message)} in #{inspect(errors)}"
    end
  end

  test "rejects impresso_ids when the package authors no impressos" do
    package =
      without_impresso_ids()
      |> put_action(@labs, 0, "impresso_ids", ["impresso-2-hemograma"])
      |> Map.put("impressos", nil)

    assert {:error, errors} = StationPackage.validate(package)

    assert "rubric actions impresso_ids must name authored impressos: impresso-2-hemograma" in errors
  end

  # Under first_n, an action's eligibility depends on the position of the
  # learner's answer, which a released impresso does not have.
  test "rejects impresso_ids on a first_n criterion" do
    package =
      without_impresso_ids()
      |> put_action(@labs, 0, "impresso_ids", ["impresso-2-hemograma"])
      |> put_criterion(@labs, "first_n", 3)

    assert {:error, errors} = StationPackage.validate(package)
    assert "rubric criteria with first_n must not author action impresso_ids" in errors
  end
end
