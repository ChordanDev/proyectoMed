defmodule Backend.Stations.CaseFormat.Values do
  @moduledoc """
  Reads the attribute values of a tagged case (issue #330): points, integers,
  id lists, PEP references and the closed vocabularies. Shared by the rule
  checks and the package builder so both read a value the same way.
  """

  alias Backend.Stations.CaseFormat.Tags

  @points ~r/^(\d+)(?:[.,](\d+))?$/
  @thousandths_per_fortieth 25

  @categories %{
    "EXAME-FISICO" => "physical_exam",
    "LABORATORIO" => "laboratory",
    "IMAGEM" => "imaging",
    "REGISTRO" => "report"
  }

  @types %{
    "PERGUNTA" => "question",
    "SOLICITACAO" => "request",
    "VERBALIZACAO" => "verbalization",
    "COMUNICACAO" => "communication"
  }

  @roles %{"PACIENTE" => "patient", "ACOMPANHANTE" => "companion"}
  @booleans %{"SIM" => true, "NAO" => false}

  @max_integer_digits 6

  @doc """
  Reads authored points (`0,2`, `0.2` or `1`) as `{:ok, number, fortieths}`.
  The number is an integer when it has no fraction, as a JSON package holds it.
  """
  @spec points(String.t()) ::
          {:ok, number(), non_neg_integer()} | {:error, :invalid | :not_a_multiple}
  def points(value) do
    case Regex.run(@points, value) do
      [_all, integer] -> fortieths(integer, "")
      [_all, integer, fraction] -> fortieths(integer, String.trim_trailing(fraction, "0"))
      nil -> {:error, :invalid}
    end
  end

  # No station awards a million points; capping the integer digits keeps the
  # float built for a JSON package finite instead of raising on overflow.
  defp fortieths(integer, _fraction) when byte_size(integer) > @max_integer_digits,
    do: {:error, :invalid}

  defp fortieths(integer, fraction) when byte_size(fraction) <= 3 do
    thousandths = String.to_integer(integer) * 1000 + fraction_thousandths(fraction)

    if rem(thousandths, @thousandths_per_fortieth) == 0 do
      {:ok, number(integer, fraction), div(thousandths, @thousandths_per_fortieth)}
    else
      {:error, :not_a_multiple}
    end
  end

  defp fortieths(_integer, _fraction), do: {:error, :not_a_multiple}

  defp fraction_thousandths(""), do: 0

  defp fraction_thousandths(fraction),
    do: fraction |> String.pad_trailing(3, "0") |> String.to_integer()

  defp number(integer, ""), do: String.to_integer(integer)
  defp number(integer, fraction), do: String.to_float("#{integer}.#{fraction}")

  @doc "Formats fortieths the way the PEP writes points: `8` is `0,2` and `40` is `1,0`."
  @spec format_points(non_neg_integer()) :: String.t()
  def format_points(fortieths) do
    thousandths = fortieths * @thousandths_per_fortieth

    fraction =
      thousandths
      |> rem(1000)
      |> Integer.to_string()
      |> String.pad_leading(3, "0")
      |> String.trim_trailing("0")

    "#{div(thousandths, 1000)},#{if fraction == "", do: "0", else: fraction}"
  end

  @doc "Reads a non-negative integer."
  @spec non_negative_integer(String.t()) :: {:ok, non_neg_integer()} | :error
  def non_negative_integer(value) do
    if Regex.match?(~r/^\d+$/, value), do: {:ok, String.to_integer(value)}, else: :error
  end

  @doc "Splits a comma-separated id list."
  @spec ids(String.t()) :: [String.t()]
  def ids(value), do: value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

  @doc "Splits the semicolon-separated release keywords of an impresso."
  @spec keywords(String.t()) :: [String.t()]
  def keywords(value) do
    value |> String.split(";") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  @doc "Reads a PEP reference `item-id.criterion-id`."
  @spec pep(String.t()) :: {:ok, String.t(), String.t()} | :error
  def pep(value) do
    case String.split(value, ".") do
      [item, criterion] when item != "" and criterion != "" -> {:ok, item, criterion}
      _other -> :error
    end
  end

  @doc "Reads an impresso `categoria`."
  @spec category(String.t()) :: {:ok, String.t()} | :error
  def category(value), do: Map.fetch(@categories, Tags.normalize(value))

  @doc "Reads a criterion `tipo` as `question`, `request`, `verbalization` or `communication`."
  @spec type(String.t()) :: {:ok, String.t()} | :error
  def type(value), do: Map.fetch(@types, Tags.normalize(value))

  @doc "Reads an actor `papel` as `patient` or `companion`."
  @spec role(String.t()) :: {:ok, String.t()} | :error
  def role(value), do: Map.fetch(@roles, Tags.normalize(value))

  @doc "Reads `sim` or `não`."
  @spec boolean(String.t()) :: {:ok, boolean()} | :error
  def boolean(value), do: Map.fetch(@booleans, Tags.normalize(value))
end
