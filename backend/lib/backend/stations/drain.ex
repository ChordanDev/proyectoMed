defmodule Backend.Stations.Drain do
  @moduledoc """
  The pre-deploy drain gate of this node (#344).

  Fly stops a machine at most 300 s after the stop signal (`kill_timeout`),
  shorter than a 10-minute station. Before `fly deploy`, an operator switches
  the node to "no new sessions" (`bin/drain start`, see
  `docs/operations/deploy.md`): `POST /sessions` then answers `503 draining`
  while running sessions finish. The flag lives in this node's memory only, so
  a new machine always starts accepting sessions.
  """

  @key {__MODULE__, :draining}

  @doc "Stops admitting new sessions on this node."
  @spec start() :: :ok
  def start, do: put(true)

  @doc "Admits new sessions again."
  @spec stop() :: :ok
  def stop, do: put(false)

  @doc "Whether this node refuses new sessions."
  @spec draining?() :: boolean()
  def draining?, do: :persistent_term.get(@key, false)

  # Only change the term when the value changes: an update of a persistent
  # term triggers a global garbage collection.
  defp put(value) do
    if draining?() != value, do: :persistent_term.put(@key, value)
    :ok
  end
end
