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
    post "/active/sessions/:id/finish", StationController, :finish_session
    get "/active/sessions/:id/result", StationController, :show_result

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

  # Server-to-server API for the Python voice worker (#118); bearer-secret auth
  # lives in the controller.
  scope "/api/internal/voice", BackendWeb do
    pipe_through :api

    get "/sessions/:id", VoiceWorkerController, :show
    post "/sessions/:id/transcripts", VoiceWorkerController, :create_transcript
  end
end
