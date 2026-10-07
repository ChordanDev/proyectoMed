defmodule Backend.Stations.RubricAssessment.Points do
  @moduledoc """
  Exact rubric points as integer fortieths (issue #128, ADR-012 as amended by
  issue #130).

  Authored `points` are multiples of 0.025. They are converted once, at the
  boundary, to a non-negative integer counting fortieths of a point; every
  later operation is integer arithmetic, so sums never drift and rendering
  never depends on float formatting.

  The conversion is strict and never snaps to the nearest fortieth. Most
  multiples of 0.025 (`0.1`, `0.2`, `1.4`) have no exact binary float, so a
  JSON decoder yields the nearest float instead. `from_authored/1` accepts a
  float only when it is exactly a multiple of 1/8 or exactly the float nearest
  to a multiple of 0.025: `0.01`, `0.33`, `0.125000001` and the drifted sum
  `0.1 + 0.2` are rejected.

  The module is pure and never multiplies points by a probability or any other
  float.
  """

  @fortieths_per_point 40
  @fraction_digits 3
  @thousandths_per_fortieth 25
  # 2 ** 47. Below it adjacent floats are closer than 0.025, so each multiple
  # of 0.025 has its own nearest float, and its fortieths are an exact float.
  @unambiguous_limit 140_737_488_355_328.0

  @typedoc "Points as a non-negative count of fortieths (`40` is one point)."
  @type t :: non_neg_integer()

  @typedoc "Why an authored value cannot be represented as exact points."
  @type error :: :not_a_multiple_of_one_fortieth | :negative | :not_a_number

  @doc """
  Converts an authored `points` value, as decoded from JSON, into fortieths.

  Accepts non-negative integers and non-negative floats that are exact
  multiples of 0.025 as a JSON decoder represents them. Never raises.
  """
  @spec from_authored(term()) :: {:ok, t()} | {:error, error()}
  def from_authored(authored) when is_integer(authored) and authored < 0, do: {:error, :negative}

  def from_authored(authored) when is_integer(authored),
    do: {:ok, authored * @fortieths_per_point}

  def from_authored(authored) when is_float(authored) and authored < 0, do: {:error, :negative}

  def from_authored(authored) when is_float(authored),
    do: fortieths(authored, Float.ratio(authored))

  def from_authored(_authored), do: {:error, :not_a_number}

  @doc "Returns zero points."
  @spec zero() :: t()
  def zero, do: 0

  @doc "Sums a list of points exactly."
  @spec sum([t()]) :: t()
  def sum(points) when is_list(points), do: Enum.sum(points)

  @doc """
  Renders points as the shortest exact decimal string, such as `"0"`,
  `"0.025"`, `"0.4"`, `"1"` or `"2.5"`, using integer arithmetic only.
  """
  @spec to_decimal_string(t()) :: String.t()
  def to_decimal_string(points) when is_integer(points) and points >= 0 do
    whole = Integer.to_string(div(points, @fortieths_per_point))

    case rem(points, @fortieths_per_point) do
      0 -> whole
      fortieths -> whole <> "." <> fraction_digits(fortieths)
    end
  end

  # `Float.ratio/1` yields the exact value as a reduced fraction whose
  # denominator is a power of two. When that denominator divides 8 the float is
  # exactly a multiple of 1/8, hence of 1/40, at any magnitude.
  defp fortieths(_authored, {numerator, denominator}) when denominator in [1, 2, 4, 8] do
    {:ok, numerator * div(@fortieths_per_point, denominator)}
  end

  # Any other float is accepted only when it is the float nearest to its
  # candidate multiple of 0.025. Dividing two exact floats is correctly
  # rounded, which is also how a decoder reads the decimal literal, so the
  # round trip compares for equality with no tolerance.
  defp fortieths(authored, {_numerator, _denominator}) when authored < @unambiguous_limit do
    candidate = round(authored * @fortieths_per_point)

    if candidate / @fortieths_per_point == authored do
      {:ok, candidate}
    else
      {:error, :not_a_multiple_of_one_fortieth}
    end
  end

  defp fortieths(_authored, {_numerator, _denominator}),
    do: {:error, :not_a_multiple_of_one_fortieth}

  defp fraction_digits(fortieths) do
    (fortieths * @thousandths_per_fortieth)
    |> Integer.to_string()
    |> String.pad_leading(@fraction_digits, "0")
    |> String.trim_trailing("0")
  end
end
