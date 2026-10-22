defmodule BackendWeb.Router do
  use BackendWeb, :router

  # LiveView pages (ADR-015 #347): cookie session, CSRF and browser headers.
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BackendWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Placeholder admin page (#329); the admin case panel (#344) replaces it and
  # adds the `admin` role check.
  scope "/admin", BackendWeb do
    pipe_through :browser

    live "/", AdminLive, :index
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

    post "/active/sessions/:id/voice",
         VoiceSessionController,
         :create
  end

  # Server-to-server API for the Python voice worker (#118, #119); bearer-secret auth
  # lives in the controller.
  scope "/api/internal/voice", BackendWeb do
    pipe_through :api

    get "/sessions/:id", VoiceWorkerController, :show
    post "/sessions/:id/transcripts", VoiceWorkerController, :create_transcript
    post "/sessions/:id/cancel", VoiceWorkerController, :cancel
  end

  scope "/api/v2/stations", BackendWeb do
    pipe_through :api
    get "/active/sessions/:id/result", StationController, :show_educational_result
  end
end
