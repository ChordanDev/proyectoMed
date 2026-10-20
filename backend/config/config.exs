# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :backend,
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
  learner_feedback_deadline_ms: 60_000,
  rubric_resolver_adapter: Backend.Stations.RubricAssessment.Resolver.DisabledAdapter,
  rubric_resolver_deadline_ms: 10_000,
  # Undecided-verdict adjudicator (issue #290): off unless runtime.exs selects it.
  patient_adjudicator_adapter: Backend.Stations.PatientAdjudicator.DisabledAdapter,
  patient_adjudicator_deadline_ms: 2_000,
  learner_message_max_characters: 2_000,
  active_station_id: "chest-pain-initial-assessment",
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
  pubsub_server: Backend.PubSub

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Never leak a LiveKit token (or other secrets) into request logs.
config :phoenix, :filter_parameters, ["password", "secret", "token", "text"]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
