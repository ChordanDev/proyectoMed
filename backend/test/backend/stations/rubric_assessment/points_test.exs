defmodule Backend.Stations.RubricAssessment.PointsTest do
  use ExUnit.Case, async: true

  alias Backend.Stations.RubricAssessment.Points

  defp points!(authored) do
    assert {:ok, points} = Points.from_authored(authored)
    points
  end

  describe "from_authored/1 accepted values" do
    test "accepts non-negative integers" do
      assert Points.from_authored(0) == {:ok, Points.zero()}
      assert Points.to_decimal_string(points!(1)) == "1"
      assert Points.to_decimal_string(points!(2)) == "2"
      assert Points.to_decimal_string(points!(10)) == "10"
    end

    test "accepts floats that are exact multiples of one eighth" do
      assert Points.to_decimal_string(points!(0.125)) == "0.125"
      assert Points.to_decimal_string(points!(0.25)) == "0.25"
      assert Points.to_decimal_string(points!(0.5)) == "0.5"
      assert Points.to_decimal_string(points!(1.375)) == "1.375"
      assert Points.to_decimal_string(points!(2.5)) == "2.5"
    end

    test "accepts the nearest float to a multiple of 0.025" do
      cases = [
        {0.025, 1, "0.025"},
        {0.05, 2, "0.05"},
        {0.075, 3, "0.075"},
        {0.1, 4, "0.1"},
        {0.2, 8, "0.2"},
        {0.3, 12, "0.3"},
        {0.4, 16, "0.4"},
        {0.6, 24, "0.6"},
        {0.7, 28, "0.7"},
        {0.8, 32, "0.8"},
        {1.2, 48, "1.2"},
        {1.4, 56, "1.4"},
        {9.975, 399, "9.975"}
      ]

      for {authored, fortieths, rendered} <- cases do
        assert Points.from_authored(authored) == {:ok, fortieths},
               "expected #{inspect(authored)} to be #{fortieths} fortieths"

        assert Points.to_decimal_string(fortieths) == rendered
      end
    end

    test "accepts tenths exactly as a JSON decoder produces them" do
      for literal <- ~w(0.1 0.2 0.3 0.4 0.6 0.7 0.8 1.2 1.4 0.025 0.125 0.375 0.625) do
        assert {:ok, points} = literal |> Jason.decode!() |> Points.from_authored()
        assert Points.to_decimal_string(points) == literal
      end
    end

    test "treats integer and float spellings of the same value as equal" do
      assert points!(1) == points!(1.0)
      assert points!(0) == points!(0.0)
      assert points!(0) == points!(-0.0)
    end

    test "accepts a very large float without overflowing" do
      assert {:ok, points} = Points.from_authored(1.0e308)
      assert is_integer(points)
    end

    test "accepts a multiple of 0.025 just below the unambiguous limit" do
      assert Points.from_authored(70_368_744_177_664.025) ==
               {:ok, 70_368_744_177_664 * 40 + 1}
    end

    test "still accepts an exact eighth beyond the unambiguous limit" do
      assert Points.from_authored(140_737_488_355_328.125) ==
               {:ok, 140_737_488_355_328 * 40 + 5}
    end
  end

  describe "from_authored/1 rejected values" do
    test "rejects floats that are not multiples of 0.025" do
      rejected = [
        0.01,
        0.33,
        0.0125,
        0.0625,
        0.15625,
        1.11,
        0.125000001,
        0.12499999999999999,
        0.20000000000000004,
        0.19999999999999998
      ]

      for authored <- rejected do
        assert Points.from_authored(authored) == {:error, :not_a_multiple_of_one_fortieth},
               "expected #{inspect(authored)} to be rejected"
      end
    end

    test "rejects the float sum that only approximates a multiple of 0.025" do
      drifted = 0.1 + 0.2

      refute drifted == 0.3
      assert Points.from_authored(drifted) == {:error, :not_a_multiple_of_one_fortieth}
    end

    test "rejects a non-eighth float too large to identify one multiple of 0.025" do
      # 2 ** 47 + 1 / 32 is the float nearest to 2 ** 47 + 0.025, but from
      # 2 ** 47 on, adjacent multiples of 0.025 can share one nearest float.
      assert 140_737_488_355_328.03125 == 140_737_488_355_328.025
      assert 140_737_488_355_328.05 == 140_737_488_355_328.075

      assert Points.from_authored(140_737_488_355_328.03125) ==
               {:error, :not_a_multiple_of_one_fortieth}
    end

    test "rejects negative numbers" do
      assert Points.from_authored(-1) == {:error, :negative}
      assert Points.from_authored(-0.125) == {:error, :negative}
      assert Points.from_authored(-0.1) == {:error, :negative}
    end

    test "rejects values that are not numbers" do
      for authored <- [nil, "1", "0.125", true, false, :one, [1], %{"points" => 1}] do
        assert Points.from_authored(authored) == {:error, :not_a_number},
               "expected #{inspect(authored)} to be rejected"
      end
    end
  end

  describe "sum/1" do
    test "sums an empty list to zero" do
      assert Points.sum([]) == Points.zero()
    end

    test "eight values of 0.125 equal exactly one point" do
      eighths = List.duplicate(points!(0.125), 8)

      assert Points.sum(eighths) == points!(1)
      assert Points.to_decimal_string(Points.sum(eighths)) == "1"
    end

    test "ten values of 0.1 equal exactly one point" do
      tenths = List.duplicate(points!(0.1), 10)

      assert Points.sum(tenths) == points!(1)
      assert Points.to_decimal_string(Points.sum(tenths)) == "1"
    end

    test "tenths and eighths sum exactly" do
      total = Points.sum([points!(0.2), points!(0.4), points!(0.7), points!(0.125)])

      assert Points.to_decimal_string(total) == "1.425"
    end

    test "0.125 plus 0.25 renders as 0.375" do
      total = Points.sum([points!(0.125), points!(0.25)])

      assert Points.to_decimal_string(total) == "0.375"
    end

    test "many small values accumulate without drift" do
      total = Points.sum(List.duplicate(points!(0.125), 1_000))

      assert total == points!(125)
      assert Points.to_decimal_string(total) == "125"
    end
  end

  describe "to_decimal_string/1" do
    test "renders the shortest exact decimal" do
      cases = [
        {0, "0"},
        {0.025, "0.025"},
        {0.05, "0.05"},
        {0.1, "0.1"},
        {0.125, "0.125"},
        {0.2, "0.2"},
        {0.25, "0.25"},
        {0.375, "0.375"},
        {0.5, "0.5"},
        {0.625, "0.625"},
        {0.75, "0.75"},
        {0.875, "0.875"},
        {1, "1"},
        {1.375, "1.375"},
        {1.4, "1.4"},
        {2.5, "2.5"},
        {100, "100"}
      ]

      for {authored, expected} <- cases do
        assert Points.to_decimal_string(points!(authored)) == expected
      end
    end

    test "renders zero as a bare zero" do
      assert Points.to_decimal_string(Points.zero()) == "0"
    end
  end
end
