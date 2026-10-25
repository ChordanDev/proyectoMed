import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Account emails are captured by the test adapter.
config :backend, Backend.Accounts.Mailer, adapter: Swoosh.Adapters.Test

# Local Postgres for tests (ADR-014 #346), checked out per test through the
# SQL sandbox. Without a host, username or password, Postgrex uses `PGHOST`,
# `PGUSER` and `PGPASSWORD` when set (the GitHub workflow sets them), otherwise
# localhost and the operating system user with no password. `mix test` creates
# and migrates this database first. `DATABASE_URL` is never read in `:test`.
# `MIX_TEST_PARTITION` keeps partitioned runs on separate databases.
config :backend, Backend.Repo,
  database: "backend_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :backend, BackendWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "P0fSl/7r5KTqP8NFwBX2znavfZMI0499/1ZgT42JR55mBOSm898GM8cnXO4kR9cV",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# The periodic orphan-room sweep is disabled in tests; tests trigger it
# explicitly via Backend.Stations.MediaSession.sweep_orphans/0.
config :backend, :livekit_orphan_sweep_enabled, false

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Learner feedback never calls a provider in tests unless a test swaps in a double,
# and a failed generation has no cooldown unless a test configures one.
config :backend,
  learner_feedback_adapter: Backend.Stations.LearnerFeedback.DisabledAdapter,
  learner_feedback_cooldown_ms: 0

# Session usage rows (issue #342) are written only by tests that turn the store
# on: most session tests run without a database sandbox.
config :backend, Backend.Stations.Usage.Store, enabled: false

# The frozen web harness and the E2E suite call the deprecated
# `/api/stations/...` routes without a device access token (#337).
config :backend, :legacy_station_api_unauthenticated, true

# RevenueCat webhook secrets and purchase links for the fixtures (#339); no
# test calls RevenueCat.
config :backend, Backend.Billing,
  entitlement_id: "simulador",
  plans: [
    %{product_id: "revalida_mensal_cartao", name: "Mensal no cartão", payment: :card},
    %{product_id: "revalida_mensal_pix", name: "Mensal no Pix", payment: :pix}
  ],
  default_daily_quota: 3,
  purchase_links: %{
    card: "https://pay.rev.cat/test-card-token",
    pix: "https://pay.rev.cat/test-pix-token"
  },
  webhook_authorization: "Bearer test-webhook-authorization",
  webhook_secret: "test-webhook-secret",
  signature_tolerance_s: 300,
  accept_sandbox: true,
  pix_reminder_days: 3
