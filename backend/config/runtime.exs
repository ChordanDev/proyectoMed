import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/backend start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :backend, BackendWeb.Endpoint, server: true
end

config :backend, BackendWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if api_key = System.get_env("OPENAI_API_KEY") do
  config :backend, Backend.StationAI.OpenAIAdapter, api_key: api_key
end

if base_url = System.get_env("OPENAI_BASE_URL") do
  config :backend, Backend.StationAI.OpenAIAdapter, base_url: base_url
end

if model = System.get_env("OPENAI_MODEL") do
  config :backend, Backend.StationAI.OpenAIAdapter, model: model
end

if api_key = System.get_env("OPENAI_API_KEY") do
  config :backend, :openai_api_key, api_key
end

if base_url = System.get_env("OPENAI_BASE_URL") do
  config :backend, :openai_base_url, base_url
end

if model = System.get_env("OPENAI_TRANSCRIPTION_MODEL") do
  config :backend, :openai_transcription_model, model
end

if model = System.get_env("OPENAI_TTS_MODEL") do
  config :backend, :openai_tts_model, model
end

if voice = System.get_env("OPENAI_TTS_VOICE") do
  config :backend, :openai_tts_voice, voice
end

with timeout when is_binary(timeout) <- System.get_env("CONVERSATION_TIMEOUT_MS"),
     {timeout_ms, ""} when timeout_ms > 0 <- Integer.parse(timeout) do
  config :backend, :conversation_timeout_ms, timeout_ms
end

with purge_interval when is_binary(purge_interval) <-
       System.get_env("CONVERSATION_PURGE_INTERVAL_MS"),
     {purge_interval_ms, ""} when purge_interval_ms > 0 <- Integer.parse(purge_interval) do
  config :backend, :conversation_purge_interval_ms, purge_interval_ms
end

# Live Jev provider (TypeSafe System One). Off unless `JEV_ADAPTER=typesafe` asks
# for it: without the variable the default `DisabledAdapter` stays in place. Live
# use is gated by the human privacy and legal acceptance tracked in issue #183.
#
# This block is the only place that reads the `TYPESAFE_*` variables: the adapter
# resolves call options and this application configuration, never the operating
# system environment. `:test` reads none of it and keeps its injected adapters.
#
# Nothing here fails the boot. Without a key the adapter fails every decision
# closed. A threshold that is not a number is kept as written, so the adapter
# rejects it (`:invalid_thresholds`) on every decision instead of falling back to
# its default.
if config_env() != :test do
  typesafe_adapter = Backend.Stations.JevDecision.TypesafeAdapter

  if System.get_env("JEV_ADAPTER") == "typesafe" do
    config :backend, :jev_decision_adapter, typesafe_adapter
  end

  for {variable, key} <- [
        {"TYPESAFE_API_KEY", :api_key},
        {"TYPESAFE_BASE_URL", :base_url},
        {"TYPESAFE_MODEL", :model}
      ],
      value = System.get_env(variable) do
    config :backend, typesafe_adapter, [{key, value}]
  end

  for {variable, key} <- [
        {"TYPESAFE_YES_THRESHOLD", :yes_threshold},
        {"TYPESAFE_NO_THRESHOLD", :no_threshold}
      ],
      raw = System.get_env(variable) do
    threshold =
      case Float.parse(String.trim(raw)) do
        {number, ""} -> number
        _ -> raw
      end

    config :backend, typesafe_adapter, [{key, threshold}]
  end
end

# Text provider (issue #252): `LLM_PROVIDER=anthropic` serves the three text
# seams (simulated patient, rubric resolver, learner feedback) from Claude's
# Messages API. Unset, or any other value, keeps OpenAI exactly as before. Jev
# (TypeSafe) and voice are not affected. `ANTHROPIC_API_KEY`,
# `ANTHROPIC_BASE_URL`, `ANTHROPIC_MODEL` (resolver and feedback, default
# `claude-opus-5-5`) and `ANTHROPIC_PATIENT_MODEL` (patient, default
# `claude-sonnet-5-5`, issue #256) are
# written to `Backend.Stations.StationAI.AnthropicClient`; the adapters never
# read the operating system environment. Selecting Claude without a key boots
# normally and every call fails as a technical failure (`:missing_credentials`),
# which each seam already handles. `:test` reads none of it.
anthropic_selected? = System.get_env("LLM_PROVIDER") == "anthropic"

if config_env() != :test do
  for {variable, key} <- [
        {"ANTHROPIC_API_KEY", :api_key},
        {"ANTHROPIC_BASE_URL", :base_url},
        {"ANTHROPIC_MODEL", :model},
        {"ANTHROPIC_PATIENT_MODEL", :patient_model}
      ],
      value = System.get_env(variable) do
    config :backend, Backend.Stations.StationAI.AnthropicClient, [{key, value}]
  end

  if anthropic_selected? do
    config :backend, :station_ai_adapter, Backend.Stations.StationAI.AnthropicAdapter

    config :backend,
           :learner_feedback_adapter,
           Backend.Stations.LearnerFeedback.AnthropicAdapter
  end
end

# Rubric resolver (issue #214): an LLM that decides only the rubric actions Jev
# left undecided. Off unless `RUBRIC_RESOLVER` turns it on (`openai`, kept for
# compatibility, or `on`): without the variable the default `DisabledAdapter`
# leaves those actions uncertain. `LLM_PROVIDER` picks who serves it: Claude
# with `LLM_PROVIDER=anthropic` (configured above), OpenAI otherwise. On OpenAI
# it reuses the OpenAI key and base URL configured above, and
# `RUBRIC_RESOLVER_MODEL` picks its model, which otherwise falls back to
# `OPENAI_MODEL`; on Claude `ANTHROPIC_MODEL` applies. `:test` reads none of it.
if config_env() != :test do
  resolver_adapter = Backend.Stations.RubricAssessment.Resolver.OpenAIAdapter

  if System.get_env("RUBRIC_RESOLVER") in ["openai", "on"] do
    selected_resolver =
      if anthropic_selected?,
        do: Backend.Stations.RubricAssessment.Resolver.AnthropicAdapter,
        else: resolver_adapter

    config :backend, :rubric_resolver_adapter, selected_resolver
  end

  if model = System.get_env("RUBRIC_RESOLVER_MODEL") do
    config :backend, resolver_adapter, model: model
  end

  # `RUBRIC_RESOLVER_DEADLINE_MS` overrides the resolver's own deadline (10 s).
  with raw when is_binary(raw) <- System.get_env("RUBRIC_RESOLVER_DEADLINE_MS"),
       {deadline_ms, ""} when deadline_ms > 0 <- Integer.parse(String.trim(raw)) do
    config :backend, :rubric_resolver_deadline_ms, deadline_ms
  end

  # `LEARNER_FEEDBACK_DEADLINE_MS` overrides the learner feedback deadline (60 s,
  # issue #226). Anything but a positive integer keeps the default. Values above
  # 65 s are capped: with the resolver's 10 s, the request must still finish
  # inside the web client's 80 s wait for the educational result.
  with raw when is_binary(raw) <- System.get_env("LEARNER_FEEDBACK_DEADLINE_MS"),
       {deadline_ms, ""} when deadline_ms > 0 <- Integer.parse(String.trim(raw)) do
    config :backend, :learner_feedback_deadline_ms, min(deadline_ms, 65_000)
  end
end

# Active station (issue #238): `ACTIVE_STATION_ID` names the station directory
# under `priv/stations` that the Station Loader loads at boot, for example
# `acute-appendicitis`. Unset or blank keeps the default from `config.exs`
# (`chest-pain-initial-assessment`). The loader rejects anything but a plain
# directory name (`[a-z0-9-]+`) and fails the boot, naming the id, when the id is
# malformed, unknown, or its package is invalid. `:test` reads none of it, so the
# suite always starts from the default station.
if config_env() != :test do
  case System.get_env("ACTIVE_STATION_ID", "") |> String.trim() do
    "" -> :ok
    station_id -> config :backend, :active_station_id, station_id
  end
end

# Turn-based voice providers (issue #253). Off unless
# `VOICE_PROVIDER=deepgram_elevenlabs` asks for it: without the variable both voice
# endpoints keep the OpenAI configuration above. Deepgram transcribes the learner
# (pt-BR) and ElevenLabs speaks the patient. Without the selected provider's key, or
# without `ELEVENLABS_VOICE_ID`, voice is unavailable, as it is without an OpenAI
# key. `:test` reads none of it.
if config_env() != :test do
  if System.get_env("VOICE_PROVIDER") == "deepgram_elevenlabs" do
    config :backend, :voice_provider, :deepgram_elevenlabs
  end

  for {variable, key} <- [
        {"DEEPGRAM_API_KEY", :deepgram_api_key},
        {"DEEPGRAM_MODEL", :deepgram_model},
        {"ELEVENLABS_API_KEY", :elevenlabs_api_key},
        {"ELEVENLABS_VOICE_ID", :elevenlabs_voice_id},
        {"ELEVENLABS_MODEL", :elevenlabs_model}
      ],
      value = System.get_env(variable),
      String.trim(value) != "" do
    config :backend, key, String.trim(value)
  end
end

# E2E-only: bypasses Jev verification with a deterministic approving adapter.
# The harness boots Phoenix under `:dev`, so the variable is honored only there:
# `:test` keeps its injected adapters and `:prod` never compiles this module.
# It is evaluated after the live selection above, so it wins when both are set.
if config_env() == :dev and System.get_env("JEV_E2E_APPROVING_ADAPTER") == "true" do
  config :backend, :jev_decision_adapter, Backend.E2ESupport.ApprovingJevAdapter
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :backend, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :backend, BackendWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :backend, BackendWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :backend, BackendWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
