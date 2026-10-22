defmodule BackendWeb.Router do
  use BackendWeb, :router

  import BackendWeb.UserAuth

  # LiveView pages (ADR-015 #347): cookie session, CSRF and browser headers.
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BackendWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Admin case panel (#331): only the `admin` role (ADR-015 #347). The plugs
  # guard the first HTTP request; the on_mount hook guards live navigation.
  scope "/admin", BackendWeb do
    pipe_through [:browser, :require_authenticated_user, :require_admin_user]

    live_session :require_admin, on_mount: [{BackendWeb.UserAuth, :require_admin}] do
      live "/", AdminLive, :index
    end
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

  ## Authentication routes (`mix phx.gen.auth`). There is no public sign-up
  ## route: admins are provisioned by `priv/repo/seeds.exs`, and learner
  ## sign-up is #336.

  scope "/", BackendWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{BackendWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", BackendWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{BackendWeb.UserAuth, :mount_current_scope}] do
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  # Development only: the in-memory mailbox of the local mail adapter.
  if Application.compile_env(:backend, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
