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

  # Bearer access token of the Unreal client's device login (#337).
  pipeline :device_auth do
    plug BackendWeb.Plugs.DeviceAuth
  end

  # The learner's station API: a valid access token, and an `:id` session the
  # learner started (another learner's session is 404).
  pipeline :learner_api do
    plug BackendWeb.Plugs.DeviceAuth
    plug BackendWeb.Plugs.SessionOwner
  end

  # Deprecated routes: unauthenticated only in dev and test (#337).
  pipeline :legacy_station_api do
    plug BackendWeb.Plugs.LegacyStationAuth
  end

  # Admin case panel (#331): only the `admin` role (ADR-015 #347). The plugs
  # guard the first HTTP request; the on_mount hook guards live navigation.
  scope "/admin", BackendWeb do
    pipe_through [:browser, :require_authenticated_user, :require_admin_user]

    live_session :require_admin, on_mount: [{BackendWeb.UserAuth, :require_admin}] do
      live "/", AdminCaseLive.Index, :index
      live "/cases/:number", AdminCaseLive.Show, :show
    end
  end

  scope "/", BackendWeb do
    pipe_through :api

    get "/", HealthController, :index
  end

  scope "/", BackendWeb do
    pipe_through [:api, :learner_api]

    get "/stations", StationController, :index

    # Multi-station session API (issue #334, ADR-013 amendment on #209): a
    # session starts on a published station and every route is addressed by it.
    get "/pre-station-notice", SessionController, :notice
    post "/sessions", SessionController, :create
    get "/sessions/:id", StationController, :show_session
    post "/sessions/:id/messages", StationController, :create_message
    post "/sessions/:id/finish", StationController, :finish_session
    post "/sessions/:id/discard", StationController, :discard
    get "/sessions/:id/result", StationController, :show_educational_result
    post "/sessions/:id/impressos/request", StationController, :request_impresso
    get "/sessions/:id/impressos", StationController, :list_impressos
    post "/sessions/:id/transcribe", TranscriptionController, :create
    post "/sessions/:id/synthesize", TTSController, :create
    post "/sessions/:id/voice", VoiceSessionController, :create
  end

  # The learner's results history (#338): only the learner's own results.
  scope "/me", BackendWeb do
    pipe_through [:api, :device_auth]

    get "/results", MeResultController, :index
    get "/results/:id", MeResultController, :show
  end

  # Device login of the Unreal client (#337, RFC 8628 shape); the learner
  # confirms the user code at `/device` (`BackendWeb.DeviceLive`).
  scope "/device", BackendWeb do
    pipe_through :api

    post "/start", DeviceController, :start
    post "/token", DeviceController, :token
    post "/refresh", DeviceController, :refresh
  end

  scope "/device", BackendWeb do
    pipe_through [:api, :device_auth]

    post "/logout", DeviceController, :logout
  end

  # Deprecated aliases (issue #334): the frozen web harness and the current
  # Unreal client still start on the boot-time active station. The per-session
  # routes below serve any session, including one started by `POST /sessions`.

  scope "/api/stations", BackendWeb do
    pipe_through [:api, :legacy_station_api]

    get "/", StationController, :index
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
    post "/sessions/:id/usage", VoiceWorkerController, :report_usage
  end

  # RevenueCat webhook (#339): authenticated by its `Authorization` header and
  # HMAC signature in the controller. `log: false` keeps the payload out of
  # the logs.
  scope "/webhooks", BackendWeb do
    pipe_through :api

    post "/revenuecat", RevenueCatWebhookController, :create, log: false
  end

  scope "/api/v2/stations", BackendWeb do
    pipe_through [:api, :legacy_station_api]
    get "/active/sessions/:id/result", StationController, :show_educational_result
  end

  ## Authentication routes (`mix phx.gen.auth`). Public sign-up creates only
  ## learner (`student`) accounts (#336); admins are provisioned by
  ## `priv/repo/seeds.exs`.

  scope "/", BackendWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{BackendWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
      live "/device", DeviceLive, :confirm
      # Plans and subscription status (#339); `/conta` is also the success
      # page of the RevenueCat Web Purchase Link.
      live "/planos", BillingLive.Plans, :index
      live "/conta", BillingLive.Account, :show
    end

    post "/users/update-password", UserSessionController, :update_password
    post "/users/delete-account", UserAccountController, :delete
  end

  scope "/", BackendWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{BackendWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
      live "/users/reset-password", UserLive.ForgotPassword, :new
      live "/users/reset-password/:token", UserLive.ResetPassword, :edit
      live "/termos", UserLive.Legal, :terms
      live "/privacidade", UserLive.Legal, :privacy
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
