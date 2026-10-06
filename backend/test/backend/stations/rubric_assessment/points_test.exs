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

    test "treats integer and float spellings of the same value as equal" do
      assert points!(1) == points!(1.0)
      assert points!(0) == points!(0.0)
      assert points!(0) == points!(-0.0)
    end

    test "accepts a very large float without overflowing" do
      assert {:ok, points} = Points.from_authored(1.0e308)
      assert is_integer(points)
    end
  end

  describe "from_authored/1 rejected values" do
    test "rejects floats that are not multiples of one eighth" do
      for authored <- [0.1, 0.3, 0.2, 0.0625, 1.1, 0.125000001, 0.12499999999999999] do
        assert Points.from_authored(authored) == {:error, :not_a_multiple_of_one_eighth},
               "expected #{inspect(authored)} to be rejected"
      end
    end

    test "rejects the float sum that only approximates a multiple of one eighth" do
      assert Points.from_authored(0.1 + 0.2 + 0.075) == {:error, :not_a_multiple_of_one_eighth}
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
        {0.125, "0.125"},
        {0.25, "0.25"},
        {0.375, "0.375"},
        {0.5, "0.5"},
        {0.625, "0.625"},
        {0.75, "0.75"},
        {0.875, "0.875"},
        {1, "1"},
        {1.375, "1.375"},
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
