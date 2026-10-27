defmodule BackendWeb.Plugs.SessionOwner do
  @moduledoc """
  Answers `404 session_not_found` when the `:id` session of the route belongs
  to another learner than the authenticated one (#337). Runs after
  `BackendWeb.Plugs.DeviceAuth`.
  """

  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Backend.Stations

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%{path_params: %{"id" => session_id}} = conn, _opts) do
    if Stations.session_accessible_by?(session_id, conn.assigns.current_scope.user.id) do
      conn
    else
      conn
      |> put_status(:not_found)
      |> json(%{error: "session_not_found", message: "Sessão não encontrada."})
      |> halt()
    end
  end

  def call(conn, _opts), do: conn
end
