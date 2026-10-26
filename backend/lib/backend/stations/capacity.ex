defmodule Backend.Stations.Capacity do
  @moduledoc """
  The concurrent-session cap of this node (#344).

  `:max_concurrent_sessions` (`MAX_CONCURRENT_SESSIONS`, default 200) bounds
  the running sessions one node holds. At the cap a new session is refused
  with `:capacity_exhausted`. An admitted session that brings the node to 80%
  of the cap or more logs a warning and emits
  `[:backend, :stations, :capacity, :warning]`; a refusal logs and emits
  `[:backend, :stations, :capacity, :exhausted]`. Both carry the `active` and
  `limit` measurements and no session or learner data.

  The check runs when a session is admitted, before it starts, so concurrent
  starts racing for the last slot may exceed the cap by the few in flight.
  """

  require Logger

  @warning_ratio 0.8

  @doc """
  Admits one more session on a node with `active` running sessions:
  `:ok` or `{:error, :capacity_exhausted}`.
  """
  @spec admit(non_neg_integer()) :: :ok | {:error, :capacity_exhausted}
  def admit(active) do
    case limit() do
      limit when is_integer(limit) and active >= limit ->
        :telemetry.execute(
          [:backend, :stations, :capacity, :exhausted],
          %{active: active, limit: limit},
          %{}
        )

        Logger.warning(
          "concurrent-session cap reached: #{active} of #{limit} active, new session refused"
        )

        {:error, :capacity_exhausted}

      limit when is_integer(limit) ->
        admitted = active + 1

        if admitted >= Float.ceil(limit * @warning_ratio) do
          :telemetry.execute(
            [:backend, :stations, :capacity, :warning],
            %{active: admitted, limit: limit},
            %{}
          )

          Logger.warning("concurrent sessions near the cap: #{admitted} of #{limit}")
        end

        :ok

      nil ->
        :ok
    end
  end

  @doc "The configured cap, or `nil` for none."
  @spec limit() :: pos_integer() | nil
  def limit, do: Application.get_env(:backend, :max_concurrent_sessions)
end
