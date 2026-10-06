defmodule Backend.Stations.RubricAssessment.Points do
  @moduledoc """
  Exact rubric points as integer eighths (issue #128, ADR-012).

  Authored `points` are multiples of 0.125. They are converted once, at the
  boundary, to a non-negative integer counting eighths of a point; every later
  operation is integer arithmetic, so sums never drift and rendering never
  depends on float formatting.

  The conversion is lossless and strict. A multiple of 1/8 is exactly
  representable as a binary float, so `from_authored/1` inspects the float's
  exact ratio instead of rounding: `0.1`, `0.3` and `0.125000001` are rejected
  rather than snapped to the nearest eighth.

  The module is pure and never multiplies points by a probability or any other
  float.
  """

  @eighths_per_point 8
  @fraction_digits 3
  @thousandths_per_eighth 125

  @typedoc "Points as a non-negative count of eighths (`8` is one point)."
  @type t :: non_neg_integer()

  @typedoc "Why an authored value cannot be represented as exact points."
  @type error :: :not_a_multiple_of_one_eighth | :negative | :not_a_number

  @doc """
  Converts an authored `points` value, as decoded from JSON, into eighths.

  Accepts non-negative integers and non-negative floats that are exact
  multiples of 0.125. Never raises.
  """
  @spec from_authored(term()) :: {:ok, t()} | {:error, error()}
  def from_authored(authored) when is_integer(authored) and authored < 0, do: {:error, :negative}
  def from_authored(authored) when is_integer(authored), do: {:ok, authored * @eighths_per_point}
  def from_authored(authored) when is_float(authored) and authored < 0, do: {:error, :negative}
  def from_authored(authored) when is_float(authored), do: authored |> Float.ratio() |> eighths()
  def from_authored(_authored), do: {:error, :not_a_number}

  @doc "Returns zero points."
  @spec zero() :: t()
  def zero, do: 0

  @doc "Sums a list of points exactly."
  @spec sum([t()]) :: t()
  def sum(points) when is_list(points), do: Enum.sum(points)

  @doc """
  Renders points as the shortest exact decimal string, such as `"0"`,
  `"0.125"`, `"1"` or `"2.5"`, using integer arithmetic only.
  """
  @spec to_decimal_string(t()) :: String.t()
  def to_decimal_string(points) when is_integer(points) and points >= 0 do
    whole = Integer.to_string(div(points, @eighths_per_point))

    case rem(points, @eighths_per_point) do
      0 -> whole
      eighths -> whole <> "." <> fraction_digits(eighths)
    end
  end

  # `Float.ratio/1` yields the exact value as a reduced fraction whose
  # denominator is a power of two, so the value is a multiple of 1/8 exactly
  # when that denominator divides 8.
  defp eighths({numerator, denominator}) when denominator in [1, 2, 4, 8] do
    {:ok, numerator * div(@eighths_per_point, denominator)}
  end

  defp eighths({_numerator, _denominator}), do: {:error, :not_a_multiple_of_one_eighth}

  defp fraction_digits(eighths) do
    (eighths * @thousandths_per_eighth)
    |> Integer.to_string()
    |> String.pad_leading(@fraction_digits, "0")
    |> String.trim_trailing("0")
  end
end
