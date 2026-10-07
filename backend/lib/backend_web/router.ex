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
    get "/active/sessions/:id", StationController, :show_session
    post "/active/sessions/:id/messages", StationController, :create_message
    post "/active/sessions/:id/finish", StationController, :finish_session
    post "/active/sessions/:id/discard", StationController, :discard
    get "/active/sessions/:id/result", StationController, :show_result

    post "/active/sessions/:id/impressos/request",
         StationController,
         :request_impresso

    get "/active/sessions/:id/impressos", StationController, :list_impressos

    post "/active/sessions/:id/transcribe",
         TranscriptionController,
         :create

    post "/active/sessions/:id/synthesize",
         TTSController,
         :create
  end

  scope "/api/v2/stations", BackendWeb do
    pipe_through :api
    get "/active/sessions/:id/result", StationController, :show_educational_result
  end
end
