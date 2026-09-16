defmodule BackendWeb.Router do
  use BackendWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", BackendWeb do
    pipe_through :api

    get "/", HealthController, :index
  end

  scope "/api/stations", BackendWeb do
    pipe_through :api

    get "/active", StationController, :active
    post "/active/sessions", StationController, :create_session
    post "/active/sessions/:id/messages", StationController, :create_message
  end
end
