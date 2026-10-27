defmodule Backend.Stations.Drain do
  @moduledoc """
  The pre-deploy drain gate of this node (#344).

  Fly stops a machine at most 300 s after the stop signal (`kill_timeout`),
  shorter than a 10-minute station. Before `fly deploy`, an operator switches
  the node to "no new sessions" (`bin/drain start`, see
  `docs/operations/deploy.md`): `POST /sessions` then answers `503 draining`
  while running sessions finish. The flag lives in this node's memory only, so
  a new machine always starts accepting sessions.

  Conversations live only in the memory of the machine that started them, and
  during a deploy the Fly proxy may send a request for a running session to
  the new machine. So a session started on a Fly machine names its owner: its
  id is `<FLY_MACHINE_ID>.<random>`, and `placement/1` tells the web layer to
  answer `fly-replay: instance=<owner>` for a session of another machine.
  """

  # Fly machine ids are lowercase hexadecimal (14 characters today).
  @machine_id_format ~r/\A[a-z0-9]{1,32}\z/

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

  @doc "This node's Fly machine id (`FLY_MACHINE_ID`), or `nil` outside Fly."
  @spec machine_id() :: String.t() | nil
  def machine_id, do: Application.get_env(:backend, :machine_id)

  @doc "Whether `id` has the shape of a Fly machine id."
  @spec valid_machine_id?(term()) :: boolean()
  def valid_machine_id?(id), do: is_binary(id) and Regex.match?(@machine_id_format, id)

  @doc """
  A new session id: `<machine id>.<random>` on a Fly machine, otherwise the
  random part alone (22 URL-safe characters).
  """
  @spec new_session_id() :: String.t()
  def new_session_id do
    random = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)

    case machine_id() do
      nil -> random
      machine -> machine <> "." <> random
    end
  end

  @doc """
  Where a request for `session_id` is served: `{:replay, machine}` when the id
  names another Fly machine than this one, otherwise `:local`.
  """
  @spec placement(String.t()) :: :local | {:replay, String.t()}
  def placement(session_id) when is_binary(session_id) do
    with this when is_binary(this) <- machine_id(),
         [owner, random] when random != "" <- String.split(session_id, "."),
         true <- owner != this and valid_machine_id?(owner) do
      {:replay, owner}
    else
      _local -> :local
    end
  end

  def placement(_session_id), do: :local

  # Only change the term when the value changes: an update of a persistent
  # term triggers a global garbage collection.
  defp put(value) do
    if draining?() != value, do: :persistent_term.put(@key, value)
    :ok
  end
end
