defmodule Backend.Stations.Usage.Store do
  @moduledoc """
  Persists the usage of finished sessions and reports their cost (issue #342).

  `persist/1` writes the session's current `Backend.Stations.Usage` totals and
  their estimate (`Backend.Stations.Usage.Prices`) as one
  `Backend.Stations.Usage.SessionUsage` row. It is an upsert keyed by the
  session id, so a later write (after the educational result's provider
  calls, or after the voice worker's report) replaces the row with the newer
  totals. A session that is not finished is never written.

  The row is computed at the call (counters and prices are in memory) and
  written in a separate process by default, so finishing a session or reading
  its result never waits for the database. Each row carries the time it was
  computed as `updated_at`, and an upsert never replaces a newer row with an
  older one, so writes that land out of order keep the latest totals.

  `config :backend, Backend.Stations.Usage.Store` takes `enabled: false` to
  turn the writes off (the test default, since most session tests run without
  a database sandbox) and `async: false` to write in the calling process. A
  database or price-table failure is logged without content and never fails
  the session operation that triggered the write.
  """

  import Ecto.Query

  require Logger

  alias Backend.Repo
  alias Backend.Stations.Usage
  alias Backend.Stations.Usage.Prices
  alias Backend.Stations.Usage.SessionUsage

  @replaced_fields SessionUsage.__schema__(:fields) -- [:session_id, :inserted_at]

  @doc "Writes the usage row of a finished session; anything else is left alone."
  @spec persist(map()) :: :ok
  def persist(%{status: :completed, session_id: session_id} = session) do
    config = Application.get_env(:backend, __MODULE__, [])

    if Keyword.get(config, :enabled, true) do
      guarded(fn ->
        session_id |> build(session) |> dispatch(Keyword.get(config, :async, true))
      end)
    end

    :ok
  end

  def persist(_session), do: :ok

  defp dispatch(row, true), do: Task.start(fn -> guarded(fn -> write(row) end) end)
  defp dispatch(row, false), do: write(row)

  defp guarded(fun) do
    fun.()
  rescue
    error in [ArgumentError, DBConnection.ConnectionError, Postgrex.Error] ->
      Logger.error("[Stations] session usage not persisted reason=#{inspect(error.__struct__)}")
  end

  defp build(session_id, session) do
    snapshot = Usage.snapshot(session_id)
    estimate = Prices.estimate(snapshot)
    now = DateTime.utc_now()

    %SessionUsage{
      session_id: session_id,
      station_id: to_string(session.station_id),
      station_version: to_string(session.station_version),
      station_version_id: Map.get(session, :station_version_id),
      started_at: session.started_at,
      finished_at: Map.get(session, :completed_at) || now,
      claude_usage:
        Map.new(snapshot.claude, fn {model, tokens} -> {model, stringify(tokens)} end),
      jev_calls: snapshot.jev_calls,
      deepgram_audio_seconds: snapshot.voice.deepgram_audio_seconds * 1.0,
      cartesia_characters: snapshot.voice.cartesia_characters,
      livekit_participant_minutes: snapshot.voice.livekit_participant_minutes * 1.0,
      cost_by_provider: Map.new(estimate.by_provider, fn {k, v} -> {k, Float.round(v, 8)} end),
      unpriced_models: estimate.unpriced_models,
      estimated_cost_usd: estimate.total_usd |> Decimal.from_float() |> Decimal.round(6),
      inserted_at: now,
      updated_at: now
    }
  end

  # `insert_all/3`: an upsert whose conflict update is skipped (an older
  # computation) affects no row, which is the intended outcome.
  defp write(%SessionUsage{} = row) do
    changes = Enum.map(@replaced_fields, &{&1, Map.fetch!(row, &1)})
    computed_at = row.updated_at

    Repo.insert_all(
      SessionUsage,
      [Map.new([{:session_id, row.session_id} | changes] ++ [inserted_at: row.inserted_at])],
      on_conflict:
        from(u in SessionUsage, where: u.updated_at <= ^computed_at, update: [set: ^changes]),
      conflict_target: :session_id
    )
  end

  defp stringify(tokens),
    do: Map.new(tokens, fn {field, count} -> {Atom.to_string(field), count} end)

  @doc """
  The cost of the sessions finished in `[from, to)`, per station, ordered by
  station id: `sessions`, `median_cost_usd` and `total_cost_usd`.
  """
  @spec cost_report(DateTime.t(), DateTime.t()) :: [
          %{
            station_id: String.t(),
            sessions: pos_integer(),
            median_cost_usd: float(),
            total_cost_usd: float()
          }
        ]
  def cost_report(%DateTime{} = from, %DateTime{} = to) do
    from(u in SessionUsage,
      where: u.finished_at >= ^from and u.finished_at < ^to,
      group_by: u.station_id,
      order_by: u.station_id,
      select: %{
        station_id: u.station_id,
        sessions: count(u.session_id),
        median_cost_usd:
          fragment(
            "percentile_cont(0.5) WITHIN GROUP (ORDER BY ?::double precision)",
            u.estimated_cost_usd
          ),
        total_cost_usd: sum(u.estimated_cost_usd)
      }
    )
    |> Repo.all()
    |> Enum.map(fn row ->
      %{
        row
        | median_cost_usd: Float.round(row.median_cost_usd * 1.0, 6),
          total_cost_usd: row.total_cost_usd |> Decimal.to_float() |> Float.round(6)
      }
    end)
  end
end
