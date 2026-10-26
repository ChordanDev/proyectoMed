defmodule BackendWeb.Router do
  use BackendWeb, :router

  import BackendWeb.UserAuth

  # LiveView pages (ADR-015 #347): cookie session, CSRF and browser headers.
  pipeline :browser do
    plug :accepts, ["html"]
    plug BackendWeb.Plugs.ClientIP
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BackendWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug BackendWeb.Plugs.ClientIP
  end

  # Bearer access token of the Unreal client's device login (#337).
  pipeline :device_auth do
    plug BackendWeb.Plugs.DeviceAuth
  end

  # The learner's station API: a valid access token, and an `:id` session the
  # learner started (another learner's session is 404). A session held by
  # another Fly machine is replayed to it first (#344).
  pipeline :learner_api do
    plug BackendWeb.Plugs.SessionReplay
    plug BackendWeb.Plugs.DeviceAuth
    plug BackendWeb.Plugs.SessionOwner
  end

  # Deprecated routes: unauthenticated only in dev and test (#337).
  # Sessions of another Fly machine are replayed to it (#344).
  pipeline :legacy_station_api do
    plug BackendWeb.Plugs.SessionReplay
    plug BackendWeb.Plugs.LegacyStationAuth
  end

  # A session held by another Fly machine is replayed to it (#344).
  pipeline :session_replay do
    plug BackendWeb.Plugs.SessionReplay
  end

  # Per-session and per-learner limits of the routes that call paid
  # providers (#395, `BackendWeb.RateLimit`), after the session owner check.
  pipeline :limit_session_message do
    plug BackendWeb.Plugs.SessionRateLimit, :session_message
  end

  pipeline :limit_session_transcribe do
    plug BackendWeb.Plugs.SessionRateLimit, :session_transcribe
  end

  pipeline :limit_session_synthesize do
    plug BackendWeb.Plugs.SessionRateLimit, :session_synthesize
  end

  pipeline :limit_session_voice do
    plug BackendWeb.Plugs.SessionRateLimit, :session_voice
  end

  pipeline :limit_session_impresso do
    plug BackendWeb.Plugs.SessionRateLimit, :session_impresso
  end

  pipeline :limit_session_exam_mode do
    plug BackendWeb.Plugs.SessionRateLimit, :session_exam_mode
  end

  pipeline :limit_session_result do
    plug BackendWeb.Plugs.SessionRateLimit, :session_result
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
    # Fly health checks (#344): plain HTTP, outside force_ssl (config/prod.exs).
    get "/health", HealthController, :index
  end

  scope "/", BackendWeb do
    pipe_through [:api, :learner_api]

    get "/stations", StationController, :index

    # Multi-station session API (issue #334, ADR-013 amendment on #209): a
    # session starts on a published station and every route is addressed by it.
    get "/pre-station-notice", SessionController, :notice
    post "/sessions", SessionController, :create
    get "/sessions/:id", StationController, :show_session
    post "/sessions/:id/finish", StationController, :finish_session
    post "/sessions/:id/discard", StationController, :discard
    get "/sessions/:id/impressos", StationController, :list_impressos

    # The routes below call paid providers and are throttled (#395).
    scope "/sessions/:id" do
      pipe_through :limit_session_message
      post "/messages", StationController, :create_message
    end

    scope "/sessions/:id" do
      pipe_through :limit_session_result
      get "/result", StationController, :show_educational_result
    end

    scope "/sessions/:id" do
      pipe_through :limit_session_impresso
      post "/impressos/request", StationController, :request_impresso
    end

    # The exam button's spoken request (#364): arms or cancels the exam mode.
    scope "/sessions/:id" do
      pipe_through :limit_session_exam_mode
      post "/exam-mode", SessionController, :arm_exam_mode
      delete "/exam-mode", SessionController, :cancel_exam_mode
    end

    scope "/sessions/:id" do
      pipe_through :limit_session_transcribe
      post "/transcribe", TranscriptionController, :create
    end

    scope "/sessions/:id" do
      pipe_through :limit_session_synthesize
      post "/synthesize", TTSController, :create
    end

    scope "/sessions/:id" do
      pipe_through :limit_session_voice
      post "/voice", VoiceSessionController, :create
    end
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
    post "/active/sessions/:id/finish", StationController, :finish_session
    post "/active/sessions/:id/discard", StationController, :discard
    get "/active/sessions/:id/impressos", StationController, :list_impressos

    # Throttled like the `/sessions/:id/...` routes, on the same counters (#395).
    scope "/active/sessions/:id" do
      pipe_through :limit_session_message
      post "/messages", StationController, :create_message
    end

    scope "/active/sessions/:id" do
      pipe_through :limit_session_result
      get "/result", StationController, :show_result
    end

    scope "/active/sessions/:id" do
      pipe_through :limit_session_impresso
      post "/impressos/request", StationController, :request_impresso
    end

    scope "/active/sessions/:id" do
      pipe_through :limit_session_transcribe
      post "/transcribe", TranscriptionController, :create
    end

    scope "/active/sessions/:id" do
      pipe_through :limit_session_synthesize
      post "/synthesize", TTSController, :create
    end

    scope "/active/sessions/:id" do
      pipe_through :limit_session_voice
      post "/voice", VoiceSessionController, :create
    end
  end

  # Server-to-server API for the Python voice worker (#118, #119); bearer-secret auth
  # lives in the controller. Never throttled (#395): a refused transcript would
  # drop a spoken turn. Voice cost is bounded at the learner's entry points
  # (`POST /sessions/:id/voice`, `.../exam-mode`) and by the station deadline.
  scope "/api/internal/voice", BackendWeb do
    pipe_through [:api, :session_replay]

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
    pipe_through [:api, :legacy_station_api, :limit_session_result]
    get "/active/sessions/:id/result", StationController, :show_educational_result
  end

  ## Authentication routes (`mix phx.gen.auth`). Public sign-up creates only
  ## learner (`student`) accounts (#336); admins are provisioned by
  ## `priv/repo/seeds.exs`.

  scope "/", BackendWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{BackendWeb.UserAuth, :require_authenticated}],
      session: {BackendWeb.RateLimit, :live_session, []} do
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
      on_mount: [{BackendWeb.UserAuth, :mount_current_scope}],
      session: {BackendWeb.RateLimit, :live_session, []} do
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
