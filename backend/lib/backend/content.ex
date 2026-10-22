defmodule Backend.Content do
  @moduledoc """
  The Content context (ADR-007 #92 amendment): generated cases and their review
  status. n8n inserts cases as pending rows (ADR-014 #346); this module reads
  them for the admin case panel (#331). It calls no other context: format
  errors come from `Backend.Stations.parse_case/1`, which the caller composes.
  """

  import Ecto.Query, warn: false

  alias Backend.Content.Case
  alias Backend.Repo

  @type filter :: {:status, String.t() | atom() | nil} | {:area, String.t() | nil}

  @doc "The review statuses, in workflow order: `[:pending, :approved, :disapproved]`."
  @spec statuses() :: [atom()]
  def statuses, do: Case.statuses()

  @doc """
  Lists cases ordered by number. `status:` and `area:` filter the list; a
  blank or unknown value is ignored.
  """
  @spec list_cases([filter()]) :: [Case.t()]
  def list_cases(filters \\ []) do
    filters
    |> Enum.reduce(from(c in Case, order_by: c.number), &filter/2)
    |> Repo.all()
  end

  defp filter({:status, status}, query) do
    case cast_status(status) do
      nil -> query
      status -> where(query, [c], c.status == ^status)
    end
  end

  defp filter({:area, area}, query) when is_binary(area) and area != "",
    do: where(query, [c], c.area == ^area)

  defp filter(_filter, query), do: query

  defp cast_status(status) when is_atom(status) and not is_nil(status),
    do: if(status in Case.statuses(), do: status)

  defp cast_status(status) when is_binary(status),
    do: Enum.find(Case.statuses(), &(Atom.to_string(&1) == status))

  defp cast_status(_status), do: nil

  @doc "Returns the distinct case areas in alphabetical order."
  @spec list_areas() :: [String.t()]
  def list_areas do
    Repo.all(from c in Case, distinct: true, select: c.area, order_by: c.area)
  end

  @doc "Gets a case by id. Raises `Ecto.NoResultsError` when it does not exist."
  @spec get_case!(integer()) :: Case.t()
  def get_case!(id), do: Repo.get!(Case, id)

  @doc "Gets a case by its human number, or nil."
  @spec get_case_by_number(integer()) :: Case.t() | nil
  def get_case_by_number(number), do: Repo.get_by(Case, number: number)
end
