defmodule BackendWeb.StationController do
  use BackendWeb, :controller

  alias Backend.StationLoader

  def active(conn, _params) do
    package = StationLoader.active_package()

    json(conn, Map.take(package, ["station_id", "version", "language", "display_title"]))
  end
end
