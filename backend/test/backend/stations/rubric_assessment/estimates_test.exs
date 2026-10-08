defmodule Backend.Stations.RubricAssessment.EstimatesTest do
  use ExUnit.Case, async: true

  alias Backend.Stations.RubricAssessment.Estimates
  alias Backend.Stations.RubricAssessment.Points

  @fixtures_path Path.expand("../../../../priv/stations/fixtures", __DIR__)

  defp fixture(name) do
    @fixtures_path
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
  end

  defp points!(authored) do
    assert {:ok, points} = Points.from_authored(authored)
    points
  end

  defp assessed(id, points, max_points) do
    %{id: id, status: :assessed, points: points!(points), max_points: points!(max_points)}
  end

  defp unscored(id, status, max_points) do
    %{id: id, status: status, max_points: points!(max_points)}
  end

  defp rendered(estimates) do
    %{
      total: estimates.total && Points.to_decimal_string(estimates.total),
      scored_subtotal: Points.to_decimal_string(estimates.scored_subtotal),
      scored_max: Points.to_decimal_string(estimates.scored_max),
      eligible_max: Points.to_decimal_string(estimates.eligible_max)
    }
  end

  describe "max_points/1" do
    test "returns the maximum over the authored levels" do
      criterion = %{
        "id" => "criterion",
        "levels" => [
          %{"label" => "inadequado", "points" => 0},
          %{"label" => "adequado", "points" => 1},
          %{"label" => "parcialmente_adequado", "points" => 0.5}
        ]
      }

      assert Estimates.max_points(criterion) == {:ok, points!(1)}
    end

    test "returns the only level of a single-level criterion" do
      criterion = %{"levels" => [%{"label" => "parcialmente_adequado", "points" => 0.125}]}

      assert Estimates.max_points(criterion) == {:ok, points!(0.125)}
    end

    test "returns zero when every level is worth zero" do
      criterion = %{"levels" => [%{"label" => "inadequado", "points" => 0}]}

      assert Estimates.max_points(criterion) == {:ok, Points.zero()}
    end

    test "propagates the reason for a level with inexact points" do
      criterion = %{"levels" => [%{"points" => 1}, %{"points" => 0.33}]}

      assert Estimates.max_points(criterion) == {:error, :not_a_multiple_of_one_fortieth}
    end

    test "propagates the reason for negative or missing level points" do
      assert Estimates.max_points(%{"levels" => [%{"points" => -1}]}) == {:error, :negative}
      assert Estimates.max_points(%{"levels" => [%{"label" => "x"}]}) == {:error, :not_a_number}
      assert Estimates.max_points(%{"levels" => ["adequado"]}) == {:error, :not_a_number}
    end

    test "rejects a criterion without authored levels" do
      assert Estimates.max_points(%{"levels" => []}) == {:error, :no_levels}
      assert Estimates.max_points(%{"id" => "criterion"}) == {:error, :no_levels}
      assert Estimates.max_points(%{"levels" => nil}) == {:error, :no_levels}
      assert Estimates.max_points(nil) == {:error, :no_levels}
    end
  end

  describe "estimate/1 reconciliation with the #126 fixture" do
    test "one assessed and one uncertain criterion reconcile to 0.25 / 0.25 / 1.25 / nil" do
      package = fixture("valid-package-v2-partial-reconciliation.json")
      [criterion_a, criterion_b] = package["rubric"]

      selected = Enum.find(criterion_a["levels"], &(&1["label"] == "parcialmente_adequado"))
      assert {:ok, max_a} = Estimates.max_points(criterion_a)
      assert {:ok, max_b} = Estimates.max_points(criterion_b)

      estimates =
        Estimates.estimate([
          %{
            id: criterion_a["id"],
            status: :assessed,
            points: points!(selected["points"]),
            max_points: max_a
          },
          %{id: criterion_b["id"], status: :uncertain, max_points: max_b}
        ])

      assert rendered(estimates) == %{
               total: nil,
               scored_subtotal: "0.25",
               scored_max: "0.25",
               eligible_max: "1.25"
             }

      assert estimates.unresolved == [%{id: "criterion-b", status: :uncertain}]
    end
  end

  describe "estimate/1 totals" do
    test "every active criterion assessed yields a total equal to the subtotal" do
      estimates =
        Estimates.estimate([
          assessed("a", 0.125, 0.25),
          assessed("b", 1, 1),
          assessed("c", 0.25, 0.5)
        ])

      assert estimates.total == estimates.scored_subtotal

      assert rendered(estimates) == %{
               total: "1.375",
               scored_subtotal: "1.375",
               scored_max: "1.75",
               eligible_max: "1.75"
             }

      assert estimates.unresolved == []
    end

    test "an uncertain criterion withholds the total and is listed as unresolved" do
      estimates = Estimates.estimate([assessed("a", 1, 1), unscored("b", :uncertain, 2)])

      assert estimates.total == nil
      assert estimates.unresolved == [%{id: "b", status: :uncertain}]
    end

    test "a not-observable criterion withholds the total and is listed as unresolved" do
      estimates = Estimates.estimate([assessed("a", 1, 1), unscored("b", :not_observable, 2)])

      assert estimates.total == nil
      assert estimates.unresolved == [%{id: "b", status: :not_observable}]

      assert rendered(estimates) == %{
               total: nil,
               scored_subtotal: "1",
               scored_max: "1",
               eligible_max: "3"
             }
    end

    test "unresolved criteria keep the input order" do
      estimates =
        Estimates.estimate([
          unscored("z", :not_observable, 1),
          assessed("m", 1, 1),
          unscored("a", :uncertain, 1),
          unscored("k", :not_applicable, 1),
          unscored("b", :not_observable, 1)
        ])

      assert estimates.unresolved == [
               %{id: "z", status: :not_observable},
               %{id: "a", status: :uncertain},
               %{id: "b", status: :not_observable}
             ]
    end

    test "a not-applicable criterion is outside both maxima and not unresolved" do
      estimates = Estimates.estimate([assessed("a", 0.5, 1), unscored("b", :not_applicable, 4)])

      assert rendered(estimates) == %{
               total: "0.5",
               scored_subtotal: "0.5",
               scored_max: "1",
               eligible_max: "1"
             }

      assert estimates.unresolved == []
    end

    test "an assessed zero-point level adds nothing to the subtotal and its maximum to scored_max" do
      estimates = Estimates.estimate([assessed("a", 0, 1), assessed("b", 0.25, 0.25)])

      assert rendered(estimates) == %{
               total: "0.25",
               scored_subtotal: "0.25",
               scored_max: "1.25",
               eligible_max: "1.25"
             }
    end

    test "an attempt assessed entirely at zero has a numeric zero total" do
      estimates = Estimates.estimate([assessed("a", 0, 1), assessed("b", 0, 2)])

      assert estimates.total == Points.zero()
      assert rendered(estimates).scored_max == "3"
    end

    test "the subtotal is never rescaled to the eligible maximum" do
      estimates = Estimates.estimate([assessed("a", 0.5, 0.5), unscored("b", :uncertain, 0.5)])

      assert rendered(estimates) == %{
               total: nil,
               scored_subtotal: "0.5",
               scored_max: "0.5",
               eligible_max: "1"
             }
    end

    test "no criterion assessed keeps zero scored values and the full eligible maximum" do
      estimates =
        Estimates.estimate([unscored("a", :uncertain, 1), unscored("b", :not_observable, 0.5)])

      assert rendered(estimates) == %{
               total: nil,
               scored_subtotal: "0",
               scored_max: "0",
               eligible_max: "1.5"
             }
    end
  end

  describe "estimate/1 without active criteria" do
    @empty %{
      total: nil,
      scored_subtotal: 0,
      scored_max: 0,
      eligible_max: 0,
      unresolved: []
    }

    test "an empty rubric has no total" do
      assert Estimates.estimate([]) == @empty
    end

    test "a rubric with every criterion excluded has no total" do
      results = [unscored("a", :not_applicable, 1), unscored("b", :not_applicable, 2)]

      assert Estimates.estimate(results) == @empty
    end
  end
end
