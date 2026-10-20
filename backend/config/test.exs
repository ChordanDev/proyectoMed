import Config

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

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Learner feedback never calls a provider in tests unless a test swaps in a double.
config :backend,
  learner_feedback_adapter: Backend.Stations.LearnerFeedback.DisabledAdapter
