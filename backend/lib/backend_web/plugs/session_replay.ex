defmodule BackendWeb.Plugs.SessionReplay do
  @moduledoc """
  Sends a request for a session held by another Fly machine to that machine
  (#344). Conversations live in the memory of the machine that started them;
  during a deploy the Fly proxy may route a request for a running session to
  the new machine, which answers `409` with `fly-replay: instance=<owner>` so
  the proxy replays the request to the owner. The owner comes from the session
  id (`Backend.Stations.session_placement/1`).

  A request that already carries `fly-replay-src` was replayed once and is
  served here, never replayed again. Runs first on every route addressed by a
  session (`:id`), before authentication: the owning machine authenticates.
  The proxy cannot replay a request body above 1 MB.
  """

  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Backend.Stations

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%{path_params: %{"id" => session_id}} = conn, _opts) when is_binary(session_id) do
    with [] <- get_req_header(conn, "fly-replay-src"),
         {:replay, machine_id} <- Stations.session_placement(session_id) do
      conn
      |> put_resp_header("fly-replay", "instance=#{machine_id}")
      |> put_status(:conflict)
      |> json(%{error: "session_on_other_machine", message: "Sessão em outro servidor."})
      |> halt()
    else
      _serve_here -> conn
    end
  end

  def call(conn, _opts), do: conn
end
