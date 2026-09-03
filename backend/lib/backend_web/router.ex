defmodule BackendWeb.Router do
  use BackendWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", BackendWeb do
    pipe_through :api

    get "/", HealthController, :index
    get "/api/stations/active", StationController, :active
  end
end
