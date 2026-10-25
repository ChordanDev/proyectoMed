# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :backend, :scopes,
  user: [
    default: true,
    module: Backend.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Backend.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :backend,
  ecto_repos: [Backend.Repo],
  generators: [timestamp_type: :utc_datetime],
  openai_transcription_model: "whisper-1",
  openai_tts_model: "tts-1",
  openai_tts_voice: "alloy",
  jev_decision_adapter: Backend.Stations.JevDecision.DisabledAdapter,
  jev_decision_default_deadline_ms: 3_000,
  jev_decision_max_context_turns: 10,
  jev_decision_max_characters: 2_000,
  jev_decision_max_context_characters: 24_000,
  jev_decision_max_rubric_context_characters: 120_000,
  learner_feedback_adapter: Backend.Stations.LearnerFeedback.OpenAIAdapter,
  # resolver 30 s + feedback 45 s fit the web client's 95 s wait for the
  # educational result (issue #301, see runtime.exs).
  learner_feedback_deadline_ms: 45_000,
  learner_feedback_cooldown_ms: 30_000,
  rubric_resolver_adapter: Backend.Stations.RubricAssessment.Resolver.DisabledAdapter,
  rubric_resolver_deadline_ms: 30_000,
  # Undecided-verdict adjudicator (issue #290): off unless runtime.exs selects it.
  patient_adjudicator_adapter: Backend.Stations.PatientAdjudicator.DisabledAdapter,
  patient_adjudicator_deadline_ms: 2_000,
  # Added to the turn's verification deadline only when the adjudicator asks for
  # a regeneration (3 s + 1.5 s = 4.5 s at most on that path).
  patient_adjudicator_regeneration_extension_ms: 1_500,
  # Patient reply verification mode (issue #307): `:audit` delivers after the
  # deterministic BoundedReply check and verifies with Jev afterwards;
  # `:blocking` keeps the pre-delivery Jev gate; `:off` skips Jev. Resolved from
  # PATIENT_VERIFICATION in runtime.exs outside :test.
  patient_verification: :audit,
  # Jev deadline of the after-delivery audit (off the critical path).
  patient_audit_deadline_ms: 10_000,
  learner_message_max_characters: 2_000,
  active_station_id: "chest-pain-initial-assessment",
  # The file loader serves the boot-time active station from priv/stations to
  # tests and local development; production turns it off and serves stations
  # only from the database (issue #334, see runtime.exs).
  file_station_loader: true,
  # Resolved from VOICE_MODE in runtime.exs outside :test (#270).
  voice_mode: "turn"

# Configure the endpoint
config :backend, BackendWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: BackendWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Backend.PubSub,
  live_view: [signing_salt: "Q4Y/CBmw"]

# LiveView (ADR-015 #347): the attribute set on all root tags, used by
# Phoenix.LiveView.ColocatedCSS.
config :phoenix_live_view, root_tag_attribute: "phx-r"

# esbuild bundles assets/js for the LiveView pages (the version is required).
config :esbuild,
  version: "0.25.4",
  backend: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Tailwind builds assets/css for the LiveView pages (the version is required).
config :tailwind,
  version: "4.3.0",
  backend: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Account emails (login links, confirmation, password reset, email change). The
# local adapter keeps them in memory (`/dev/mailbox` in development);
# config/runtime.exs switches to the provider named by `MAILER_PROVIDER` (#336),
# which production requires. `:mailer_from` is the sender `{name, email}`.
config :backend, Backend.Accounts.Mailer, adapter: Swoosh.Adapters.Local
config :backend, :mailer_from, {"proyectoMed", "contact@example.com"}
config :swoosh, :api_client, false

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Never leak a LiveKit token (or other secrets) into request logs.
# "code" hides the device and user codes of the device login (#337); "token"
# hides its access and refresh tokens.
config :phoenix, :filter_parameters, ["password", "secret", "token", "text", "code"]

# The deprecated `/api/stations/...` routes require the device access token
# (#337) unless an environment opts out (dev and test, for the frozen web
# harness and the E2E suite).
config :backend, :legacy_station_api_unauthenticated, false

# Rate limits of the public authentication and device-login endpoints (#380),
# counted in memory (`BackendWeb.RateLimit`). `:limits` overrides the defaults
# as `[action: [kind: {count, window_ms}]]`; config/runtime.exs reads the
# `RATE_LIMIT_*` variables.
config :backend, BackendWeb.RateLimit, enabled: true, limits: []

# The client IP is the socket peer unless a trusted proxy header is named
# (`TRUSTED_CLIENT_IP_HEADER`, for example `fly-client-ip` behind Fly).
config :backend, BackendWeb.Plugs.ClientIP, header: nil

# RevenueCat billing (#339, see docs/operations/revenuecat.md). Plans are keyed
# by RevenueCat `product_id` (research A9): the webhook carries no plan metadata
# or payment method. Card plans renew automatically; Pix plans are paid
# manually each period. The webhook secrets and the Web Purchase Links come from
# the environment in runtime.exs; unset, the webhook answers 503 and the plan
# page shows no purchase button.
config :backend, Backend.Billing,
  entitlement_id: "simulador",
  plans: [
    %{product_id: "revalida_mensal_cartao", name: "Mensal no cartão", payment: :card},
    %{product_id: "revalida_mensal_pix", name: "Mensal no Pix", payment: :pix}
  ],
  purchase_links: %{},
  webhook_authorization: nil,
  webhook_secret: nil,
  signature_tolerance_s: 300,
  accept_sandbox: true,
  pix_reminder_days: 3

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
