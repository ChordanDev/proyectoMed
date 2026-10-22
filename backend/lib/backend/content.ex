defmodule Backend.Content do
  @moduledoc """
  The Content context (ADR-007 #92 amendment): generated cases and their review
  status. n8n inserts cases as pending rows (ADR-014 #346); this module reads
  them for the admin case panel (#331), where admins edit their Markdown with
  optimistic locking and a kept revision per save (#332). It calls no other context: format
  errors come from `Backend.Stations.parse_case/1`, which the caller composes.
  """

  import Ecto.Query, warn: false

  alias Backend.Content.Case
  alias Backend.Content.CaseRevision
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

  @typedoc "The admin saving an edit: only its `id` and `email` are read."
  @type editor :: %{
          required(:id) => integer(),
          required(:email) => String.t(),
          optional(atom()) => any()
        }

  @doc """
  Replaces a case's Markdown with an admin's edit (issue #332).

  `kase` is the case as the admin loaded it: the save applies only if nobody
  saved the case since (its `lock_version` is unchanged), otherwise it returns
  `{:error, :stale}` and changes nothing. A successful save increments
  `lock_version` and keeps the replaced Markdown as a `CaseRevision` with the
  editor, in one transaction. Saving the same Markdown changes nothing.

  It never validates the case format: the caller shows the parser errors of
  the saved Markdown, and the status, area and theme stay as they are. Only
  `cases` and `case_revisions` are written.
  """
  @spec update_case_markdown(Case.t(), String.t(), editor()) ::
          {:ok, Case.t()} | {:error, :stale} | {:error, Ecto.Changeset.t()}
  def update_case_markdown(%Case{markdown: markdown} = kase, markdown, _editor), do: {:ok, kase}

  def update_case_markdown(%Case{} = kase, markdown, %{id: editor_id, email: editor_email}) do
    changeset = Case.markdown_changeset(kase, markdown)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:case, changeset, stale_error_field: :lock_version)
    |> Ecto.Multi.insert(:revision, fn _changes ->
      %CaseRevision{
        case_id: kase.id,
        markdown: kase.markdown,
        lock_version: kase.lock_version,
        editor_id: editor_id,
        editor_email: editor_email
      }
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{case: saved}} -> {:ok, saved}
      {:error, :case, changeset, _changes} -> update_error(changeset)
    end
  end

  defp update_error(changeset) do
    if Keyword.has_key?(changeset.errors, :lock_version),
      do: {:error, :stale},
      else: {:error, changeset}
  end

  @doc "Lists the kept revisions of a case, newest first (issue #332)."
  @spec list_case_revisions(Case.t()) :: [CaseRevision.t()]
  def list_case_revisions(%Case{id: case_id}) do
    Repo.all(
      from r in CaseRevision,
        where: r.case_id == ^case_id,
        order_by: [desc: r.lock_version]
    )
  end
end
