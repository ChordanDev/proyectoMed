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

if url = System.get_env("LIVEKIT_URL") do
  config :backend, :livekit_url, url
end

if api_key = System.get_env("LIVEKIT_API_KEY") do
  config :backend, :livekit_api_key, api_key
end

if api_secret = System.get_env("LIVEKIT_API_SECRET") do
  config :backend, :livekit_api_secret, api_secret
end

if secret = System.get_env("VOICE_WORKER_SECRET") do
  config :backend, :voice_worker_secret, secret
end

# Voice experience the web offers (#270): `realtime` (LiveKit voice panel and the
# voice worker), `turn` (record and "Ouvir resposta" buttons through
# `VOICE_PROVIDER`) or `off` (text only, no audio consent). Unset or unknown, it is
# `realtime` when LIVEKIT_URL, LIVEKIT_API_KEY and LIVEKIT_API_SECRET are all set,
# otherwise `turn`. Served as `voice_mode` on GET /api/stations/active. `:test`
# keeps the compiled default from config.exs.
if config_env() != :test do
  livekit_configured? =
    Enum.all?(
      ["LIVEKIT_URL", "LIVEKIT_API_KEY", "LIVEKIT_API_SECRET"],
      &(String.trim(System.get_env(&1, "")) != "")
    )

  voice_mode =
    case System.get_env("VOICE_MODE", "") |> String.trim() |> String.downcase() do
      mode when mode in ["realtime", "turn", "off"] -> mode
      _ when livekit_configured? -> "realtime"
      _ -> "turn"
    end

  config :backend, :voice_mode, voice_mode
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
        {"TYPESAFE_NO_THRESHOLD", :no_threshold},
        {"TYPESAFE_OUT_OF_ROLE_NO_THRESHOLD", :out_of_role_no_threshold}
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

# Patient reply verification (issue #307): `PATIENT_VERIFICATION=audit` (the
# default) delivers a patient reply once the deterministic BoundedReply check
# passes and verifies it with Jev after delivery; `blocking` keeps the
# pre-delivery Jev gate with the adjudicator and the single regeneration; `off`
# makes no patient-side Jev call. Case and surrounding whitespace are ignored.
# Any other value fails the boot, naming it. `:test` reads none of it.
if config_env() != :test do
  case System.get_env("PATIENT_VERIFICATION", "") |> String.trim() |> String.downcase() do
    "" ->
      :ok

    mode when mode in ["blocking", "audit", "off"] ->
      config :backend, :patient_verification, String.to_existing_atom(mode)

    _invalid ->
      raise ArgumentError,
            "PATIENT_VERIFICATION must be blocking, audit or off, got: " <>
              inspect(System.get_env("PATIENT_VERIFICATION"))
  end
end

# Text provider (issue #252): `LLM_PROVIDER=anthropic` serves the three text
# seams (simulated patient, rubric resolver, learner feedback) from Claude's
# Messages API. Unset, or any other value, keeps OpenAI exactly as before. Jev
# (TypeSafe) and voice are not affected. `ANTHROPIC_API_KEY`,
# `ANTHROPIC_BASE_URL`, `ANTHROPIC_MODEL` (resolver and feedback, default
# `claude-opus-5-5`) and `ANTHROPIC_PATIENT_MODEL` (patient, default
# `claude-sonnet-5-5`, issue #256) and `ANTHROPIC_ADJUDICATOR_MODEL`
# (undecided-verdict adjudicator, default `claude-haiku-5-5`, issue #290) are
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
        {"ANTHROPIC_PATIENT_MODEL", :patient_model},
        {"ANTHROPIC_ADJUDICATOR_MODEL", :adjudicator_model}
      ],
      value = System.get_env(variable) do
    config :backend, Backend.Stations.StationAI.AnthropicClient, [{key, value}]
  end

  if anthropic_selected? do
    config :backend, :station_ai_adapter, Backend.Stations.StationAI.AnthropicAdapter

    config :backend,
           :learner_feedback_adapter,
           Backend.Stations.LearnerFeedback.AnthropicAdapter

    # Undecided-verdict adjudicator (issue #290): with Claude selected, a
    # low-confidence Jev verdict gets one call to `ANTHROPIC_ADJUDICATOR_MODEL`
    # (default `claude-haiku-5-5`). `PATIENT_ADJUDICATOR=off` keeps today's
    # refusal path.
    if System.get_env("PATIENT_ADJUDICATOR") != "off" do
      config :backend,
             :patient_adjudicator_adapter,
             Backend.Stations.PatientAdjudicator.AnthropicAdapter
    end
  end

  # `PATIENT_ADJUDICATOR_DEADLINE_MS` overrides the adjudicator's own deadline
  # (2 s); the turn's verification budget still caps it. Anything but a
  # positive integer keeps the default.
  with raw when is_binary(raw) <- System.get_env("PATIENT_ADJUDICATOR_DEADLINE_MS"),
       {deadline_ms, ""} when deadline_ms > 0 <- Integer.parse(String.trim(raw)) do
    config :backend, :patient_adjudicator_deadline_ms, deadline_ms
  end

  # `PATIENT_ADJUDICATOR_REGENERATION_EXTENSION_MS` is added to the turn's
  # verification deadline only when the adjudicator asks for a regeneration
  # (default 1500 ms, so 4.5 s at most on that path; `0` turns it off). Anything
  # but a non-negative integer keeps the default.
  with raw when is_binary(raw) <- System.get_env("PATIENT_ADJUDICATOR_REGENERATION_EXTENSION_MS"),
       {extension_ms, ""} when extension_ms >= 0 <- Integer.parse(String.trim(raw)) do
    config :backend, :patient_adjudicator_regeneration_extension_ms, extension_ms
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

  # Educational result budget (issue #301). The first fetch of the result runs
  # the rubric resolver and then learner feedback before answering, and the web
  # client waits 95 s for it (`EDUCATIONAL_RESULT_TIMEOUT_MS`). 15 s are kept
  # for Jev's rubric calls, the network and serialization, so resolver plus
  # feedback get at most 80 s. Defaults (config.exs): resolver 30 s, feedback
  # 45 s. `test/backend/educational_result_budget_test.exs` pins this.
  educational_result_budget_ms = 80_000
  max_resolver_deadline_ms = 40_000

  # `RUBRIC_RESOLVER_DEADLINE_MS` overrides the resolver's own deadline (30 s),
  # capped at 40 s. Anything but a positive integer keeps the default.
  resolver_deadline_ms =
    with raw when is_binary(raw) <- System.get_env("RUBRIC_RESOLVER_DEADLINE_MS"),
         {deadline_ms, ""} when deadline_ms > 0 <- Integer.parse(String.trim(raw)) do
      deadline_ms = min(deadline_ms, max_resolver_deadline_ms)
      config :backend, :rubric_resolver_deadline_ms, deadline_ms
      deadline_ms
    else
      _default -> 30_000
    end

  # `LEARNER_FEEDBACK_DEADLINE_MS` overrides the learner feedback deadline (45 s,
  # issues #226 and #301). Anything but a positive integer keeps the default.
  # Values above what the resolver leaves of the budget are capped.
  with raw when is_binary(raw) <- System.get_env("LEARNER_FEEDBACK_DEADLINE_MS"),
       {deadline_ms, ""} when deadline_ms > 0 <- Integer.parse(String.trim(raw)) do
    config :backend,
           :learner_feedback_deadline_ms,
           min(deadline_ms, educational_result_budget_ms - resolver_deadline_ms)
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
