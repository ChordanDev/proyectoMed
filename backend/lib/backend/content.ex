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
  alias Backend.Content.StationVersion
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

    Repo.transact(fn ->
      with {:ok, saved} <- Repo.update(changeset, stale_error_field: :lock_version),
           {:ok, _revision} <-
             Repo.insert(%CaseRevision{
               case_id: kase.id,
               markdown: kase.markdown,
               lock_version: kase.lock_version,
               editor_id: editor_id,
               editor_email: editor_email
             }) do
        {:ok, saved}
      end
    end)
    |> case do
      {:ok, saved} -> {:ok, saved}
      {:error, changeset} -> update_error(changeset)
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

  @typedoc "The admin approving a case: its `id` and `email` are recorded."
  @type approver :: %{
          required(:id) => integer(),
          required(:email) => String.t(),
          optional(atom()) => any()
        }

  @doc """
  Approves a case and publishes it as an immutable Station version (issue #333).

  Only a case with a valid parsed package (no parser errors) can be approved;
  if the package is invalid or an `{:error, _}` tuple is passed, it returns
  `{:error, :invalid_case}` without touching the database.

  Approval records the approver's `id` and `email` snapshot and timestamp on
  the case, updates its status to `:approved` (and syncs `area` and `theme`),
  increments `lock_version` with optimistic locking, and inserts a new immutable
  `StationVersion` referencing its case and revision (if edited).
  """
  @spec approve_case(Case.t(), {:ok, map()} | {:error, term()} | map() | term(), approver()) ::
          {:ok, Case.t()}
          | {:error, :invalid_case}
          | {:error, :stale}
          | {:error, Ecto.Changeset.t()}
  def approve_case(%Case{} = kase, package_or_result, approver) do
    case extract_package(package_or_result) do
      {:ok, package} ->
        do_approve_case(kase, package, approver)

      :error ->
        {:error, :invalid_case}
    end
  end

  defp extract_package({:ok, package}) when is_map(package), do: validate_package(package)
  defp extract_package(package) when is_map(package), do: validate_package(package)
  defp extract_package(_other), do: :error

  defp validate_package(package) do
    if is_binary(package["station_id"]) and
         is_binary(package["area"]) and
         is_binary(package["theme"]) and
         is_list(package["actors"]) do
      {:ok, package}
    else
      :error
    end
  end

  defp do_approve_case(%Case{} = kase, package, approver) do
    if already_approved_with_same_markdown?(kase) do
      {:ok, kase}
    else
      execute_approval(kase, package, approver)
    end
  end

  defp execute_approval(%Case{} = kase, package, %{id: approver_id, email: approver_email}) do
    now = DateTime.utc_now(:second)

    attrs = %{
      status: :approved,
      area: package["area"],
      theme: package["theme"],
      approved_by_id: approver_id,
      approved_by_email: approver_email,
      approved_at: now
    }

    changeset = Case.approve_changeset(kase, attrs)

    Repo.transact(fn ->
      with {:ok, saved_case} <- Repo.update(changeset, stale_error_field: :lock_version),
           {:ok, _version} <-
             insert_station_version(kase, package, approver_id, approver_email, now) do
        {:ok, saved_case}
      end
    end)
    |> case do
      {:ok, saved_case} -> {:ok, saved_case}
      {:error, changeset} -> update_error(changeset)
    end
  end

  defp already_approved_with_same_markdown?(%Case{
         status: :approved,
         id: case_id,
         markdown: markdown
       }) do
    case Repo.one(
           from sv in StationVersion,
             where: sv.case_id == ^case_id,
             order_by: [desc: sv.version_number],
             limit: 1,
             select: sv.markdown
         ) do
      ^markdown -> true
      _other -> false
    end
  end

  defp already_approved_with_same_markdown?(_kase), do: false

  defp insert_station_version(kase, package, approver_id, approver_email, now) do
    latest_revision =
      Repo.one(
        from r in CaseRevision,
          where: r.case_id == ^kase.id,
          order_by: [desc: r.lock_version],
          limit: 1
      )

    revision_id = if latest_revision, do: latest_revision.id, else: nil

    max_version =
      Repo.one(
        from sv in StationVersion,
          where: sv.case_id == ^kase.id,
          select: max(sv.version_number)
      ) || 0

    version = %StationVersion{
      case_id: kase.id,
      case_revision_id: revision_id,
      version_number: max_version + 1,
      station_id: package["station_id"],
      area: package["area"],
      theme: package["theme"],
      markdown: kase.markdown,
      package: package,
      approved_by_id: approver_id,
      approved_by_email: approver_email,
      approved_at: now
    }

    Repo.insert(version)
  end

  @doc """
  Disapproves a case with one click (issue #333).

  Sets status to `:disapproved` with optimistic locking over the case's
  `lock_version`.
  """
  @spec disapprove_case(Case.t()) ::
          {:ok, Case.t()} | {:error, :stale} | {:error, Ecto.Changeset.t()}
  def disapprove_case(%Case{} = kase) do
    changeset = Case.disapprove_changeset(kase)

    case Repo.update(changeset, stale_error_field: :lock_version) do
      {:ok, saved} -> {:ok, saved}
      {:error, changeset} -> update_error(changeset)
    end
  end

  @doc "Gets a published station version by id. Raises `Ecto.NoResultsError` if missing."
  @spec get_station_version!(integer()) :: StationVersion.t()
  def get_station_version!(id), do: Repo.get!(StationVersion, id)

  @doc "Gets a published station version by id, or nil."
  @spec get_station_version(integer()) :: StationVersion.t() | nil
  def get_station_version(id), do: Repo.get(StationVersion, id)

  @doc "Lists all published versions of a case, newest first."
  @spec list_station_versions(Case.t() | integer()) :: [StationVersion.t()]
  def list_station_versions(%Case{id: case_id}), do: list_station_versions(case_id)

  def list_station_versions(case_id) when is_integer(case_id) do
    Repo.all(
      from sv in StationVersion,
        where: sv.case_id == ^case_id,
        order_by: [desc: sv.version_number]
    )
  end

  @doc """
  Lists the latest published `StationVersion` for each approved case, ordered by
  the case's human number ascending. Cases that are pending or disapproved are
  omitted. Each version has its `case` preloaded: the case number is the
  catalog identity, because several cases may share one `[ESTAÇÃO]` slug
  (`station_id`).
  """
  @spec list_published_stations() :: [StationVersion.t()]
  def list_published_stations do
    Repo.all(
      from sv in StationVersion,
        join: c in assoc(sv, :case),
        where: c.status == :approved,
        distinct: c.number,
        order_by: [asc: c.number, desc: sv.version_number],
        preload: [case: c]
    )
  end

  @doc """
  The published version a new session plays for case `number` (issue #334):
  the latest version of an approved case, with its case preloaded, or `nil`
  when the number is unknown or the case is pending or disapproved.
  """
  @spec get_published_station(integer()) :: StationVersion.t() | nil
  def get_published_station(number) when is_integer(number) do
    Repo.one(
      from sv in StationVersion,
        join: c in assoc(sv, :case),
        where: c.status == :approved and c.number == ^number,
        order_by: [desc: sv.version_number],
        limit: 1,
        preload: [case: c]
    )
  end

  @doc """
  Draws one published station at random (issue #334): the latest version of a
  random approved case, within `area` (the `[ÁREA]` of that version) when one
  is given. Returns `nil` when nothing is published there.
  """
  @spec random_published_station(String.t() | nil) :: StationVersion.t() | nil
  def random_published_station(area \\ nil) do
    latest_ids =
      from sv in StationVersion,
        join: c in assoc(sv, :case),
        where: c.status == :approved,
        distinct: c.number,
        order_by: [asc: c.number, desc: sv.version_number],
        select: sv.id

    query =
      from sv in StationVersion,
        where: sv.id in subquery(latest_ids),
        order_by: fragment("random()"),
        limit: 1,
        preload: [:case]

    query
    |> where_area(area)
    |> Repo.one()
  end

  defp where_area(query, area) when is_binary(area), do: where(query, [sv], sv.area == ^area)
  defp where_area(query, _area), do: query
end
