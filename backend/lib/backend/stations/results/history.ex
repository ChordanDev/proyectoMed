defmodule Backend.Stations.Results.History do
  @moduledoc """
  The learner's results history (#338, ADR-014 #346, ADR-013 amendment on
  #209).

  `record/2` stores the Educational Result of a graded session once, the
  first time it is served, so the stored `result` is exactly what the learner
  saw at the end of the session. Only sessions that belong to a learner are
  stored; a technical failure never reaches `record/2`.

  Reads are scoped to the learner: another learner's result is not found.
  Nothing here computes anything across sessions: no aggregate score, no
  pass/fail and no readiness signal (ADR-005 #38, ADR-012 #124).
  """

  import Ecto.Query

  require Logger

  alias Backend.Repo
  alias Backend.Stations.PreStationNotice
  alias Backend.Stations.Results.StoredResult

  @default_page_size 20
  @max_page_size 100

  @doc """
  Stores `result`, the serialized Educational Result of the finished
  `session`, for the session's learner. A session without a learner or a
  published Station version stores nothing, and a session already stored is
  left unchanged. A storage failure is logged without content and does not
  fail the result.
  """
  @spec record(map(), map()) :: :ok
  def record(%{user_id: user_id, station_version_id: version_id} = session, result)
      when is_integer(user_id) and is_integer(version_id) do
    %StoredResult{
      user_id: user_id,
      session_id: session.session_id,
      station_version_id: version_id,
      case_number: session.station_id,
      version_number: session.station_version,
      station_slug: Map.get(session, :station_slug),
      area: Map.get(session, :station_area),
      theme: Map.get(session, :station_theme),
      display_title: get_in(session, [:package, "display_title"]),
      finished_at: Map.get(session, :completed_at) || DateTime.utc_now(),
      result: result
    }
    |> Repo.insert(on_conflict: :nothing, conflict_target: :session_id)
    |> case do
      {:ok, _stored} ->
        :ok

      {:error, _changeset} ->
        Logger.error("[Stations] educational result not stored")
        :ok
    end
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error, Ecto.ConstraintError] ->
      Logger.error("[Stations] educational result not stored: #{error.__struct__}")
      :ok
  end

  def record(_session_without_learner, _result), do: :ok

  @doc """
  Lists the learner's stored results, newest first. Options: `:area` (exact
  `[ÁREA]`, `nil` for every area), `:page` (1-based) and `:page_size`
  (1..#{@max_page_size}, default #{@default_page_size}).
  """
  @spec list(pos_integer(), keyword()) :: map()
  def list(user_id, opts \\ []) do
    page = max(Keyword.get(opts, :page, 1), 1)
    page_size = opts |> Keyword.get(:page_size, @default_page_size) |> min(@max_page_size)

    rows =
      StoredResult
      |> where(user_id: ^user_id)
      |> filter_area(Keyword.get(opts, :area))
      |> order_by(desc: :finished_at, desc: :id)
      |> limit(^(page_size + 1))
      |> offset(^((page - 1) * page_size))
      |> select([r], struct(r, ^summary_fields()))
      |> Repo.all()

    %{
      results: rows |> Enum.take(page_size) |> Enum.map(&summary/1),
      page: page,
      page_size: page_size,
      has_more: length(rows) > page_size,
      educational_disclaimer: disclaimer()
    }
  end

  @doc """
  The learner's stored result `id`: its summary fields plus `result`, the
  Educational Result served at the end of the session. Another learner's
  result, or an unknown id, is `{:error, :not_found}`.
  """
  @spec get(pos_integer(), term()) :: {:ok, map()} | {:error, :not_found}
  def get(user_id, id) do
    with {:ok, id} <- cast_id(id),
         %StoredResult{} = stored <- Repo.get_by(StoredResult, id: id, user_id: user_id) do
      {:ok,
       stored
       |> summary()
       |> Map.merge(%{result: stored.result, educational_disclaimer: disclaimer()})}
    else
      _ -> {:error, :not_found}
    end
  end

  defp filter_area(query, nil), do: query
  defp filter_area(query, area), do: where(query, area: ^area)

  defp summary_fields do
    [
      :id,
      :session_id,
      :case_number,
      :version_number,
      :station_slug,
      :area,
      :theme,
      :display_title,
      :finished_at
    ]
  end

  defp summary(stored) do
    %{
      id: stored.id,
      session_id: stored.session_id,
      finished_at: stored.finished_at,
      station: %{
        id: stored.case_number,
        version: stored.version_number,
        slug: stored.station_slug,
        area: stored.area,
        theme: stored.theme,
        display_title: stored.display_title
      }
    }
  end

  defp cast_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  defp cast_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {number, ""} when number > 0 and number <= 9_223_372_036_854_775_807 -> {:ok, number}
      _other -> :error
    end
  end

  defp cast_id(_id), do: :error

  defp disclaimer, do: PreStationNotice.build()["educational_disclaimer"]
end
