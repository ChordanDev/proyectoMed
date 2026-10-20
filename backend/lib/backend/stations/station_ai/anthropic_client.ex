defmodule Backend.Stations.StationAI.AnthropicClient do
  @moduledoc """
  Minimal client for Anthropic's Messages API (`POST /v1/messages`), shared by
  the three text seams that can run on Claude (issue #252): the simulated
  patient (`Backend.Stations.StationAI.AnthropicAdapter`), the rubric resolver
  (`Backend.Stations.RubricAssessment.Resolver.AnthropicAdapter`) and learner
  feedback (`Backend.Stations.LearnerFeedback.AnthropicAdapter`).

  Elixir has no official Anthropic SDK, so this speaks raw HTTP with Req. It
  never goes through an OpenAI-compatibility layer.

  ## Request

  Every request sends `x-api-key`, `anthropic-version: 2023-06-01` and the
  `server-side-fallback-2026-07-01` beta with `fallbacks: "default"`, so a
  safety-classifier decline is retried server-side on the model Anthropic
  recommends for that category (both Claude Opus 5.5 and Claude Sonnet 5.5
  accept the `"default"` form on the Claude API). No `temperature`, `top_p` or
  `budget_tokens` is ever sent; `output_config.effort` is the latency control.
  A JSON schema, when given, becomes `output_config.format` (structured
  outputs).

  ## Prompt caching

  The request's `system` is the stable prefix (issue #272): it is sent as one
  text block carrying `cache_control: {type: "ephemeral"}` (5-minute TTL), so
  the rendered `system` up to that block is cached and reused while it stays
  byte-identical. An optional `system_suffix` (per-turn instructions) follows
  as a second block without a marker, and `messages` come after it, so
  per-turn content never enters the cached prefix. Callers keep timestamps and
  ids out of `system`. A prefix shorter than the model's minimum (512 tokens on
  Claude Opus 5.5 and Claude Sonnet 5.5) silently does not cache; one
  breakpoint at the end of the whole stable prefix keeps it as long as
  possible.

  Thinking is left at the model default (adaptive) unless a seam asks for the
  lowest setting (`thinking: :lowest`, the patient, issue #256). On Claude
  Sonnet 5.5 that is `thinking: {type: "between_tools"}` with no other
  thinking field (`{type: "disabled"}` is a 400 there); every other model
  rejects `between_tools`, so it gets no `thinking` field at all. The patient's
  effort (`low`) stays within the `high`-or-below limit of `between_tools`.

  ## Configuration

  `config :backend, Backend.Stations.StationAI.AnthropicClient` holds
  `:api_key`, `:base_url` (default `https://api.anthropic.com`), `:model`
  (default `claude-opus-5-5`, the resolver and feedback), `:patient_model`
  (default `claude-sonnet-5-5`, the patient) and `:req_options`;
  `config/runtime.exs` writes them from `ANTHROPIC_API_KEY`,
  `ANTHROPIC_BASE_URL`, `ANTHROPIC_MODEL` and `ANTHROPIC_PATIENT_MODEL`.
  A seam picks its model setting with the `:model_key` default. Call options
  (`:api_key`, `:base_url`, `:model`, `:effort`, `:plug`, `:retry`,
  `:req_options`) override it. The operating system environment is never
  read here.

  ## Outcomes

    * `{:ok, text}` - the concatenated `text` blocks of a response that ended
      normally (`end_turn` or `stop_sequence`); `thinking` and `fallback`
      blocks are skipped;
    * `{:error, :missing_credentials}` - the API key is absent or blank;
    * `{:error, :upstream_error}` - a non-2xx HTTP response;
    * `{:error, :timeout}` - the request timed out;
    * `{:error, :network_error}` - a transport or connection failure;
    * `{:error, :refused}` - `stop_reason: "refusal"` after the fallbacks;
      partial text is discarded;
    * `{:error, :malformed_response}` - any other stop (`max_tokens`,
      `pause_turn`, ...) or a body without non-blank text.

  `stop_reason` is checked before any content is read. Nothing here logs the
  key, the prompt or the provider output.

  ## Usage log

  Each 2xx response logs, at debug level, the model, `input_tokens`,
  `cache_read_input_tokens`, `cache_creation_input_tokens` and the request
  latency in milliseconds (missing usage fields are logged as 0), so a live run
  shows whether the cache hits. It carries no prompt, output or key.
  """

  require Logger

  @default_base_url "https://api.anthropic.com"
  @default_models %{model: "claude-opus-5-5", patient_model: "claude-sonnet-5-5"}
  @between_tools_models ["claude-sonnet-5-5"]
  @default_effort "medium"
  @anthropic_version "2023-06-01"
  @fallback_beta "server-side-fallback-2026-07-01"
  @normal_stops ["end_turn", "stop_sequence"]

  @type config :: %{
          api_key: String.t() | nil,
          base_url: String.t(),
          model: String.t(),
          effort: String.t(),
          thinking: :default | :lowest,
          req_options: keyword()
        }

  @type request :: %{
          required(:system) => String.t(),
          required(:messages) => [map()],
          required(:max_tokens) => pos_integer(),
          optional(:system_suffix) => String.t() | nil,
          optional(:schema) => map()
        }

  @type error ::
          :missing_credentials
          | :upstream_error
          | :timeout
          | :network_error
          | :refused
          | :malformed_response

  @doc """
  Builds the request configuration from call options, then the application
  configuration, then the defaults.

  `defaults` carries a seam's own `:effort`, `:receive_timeout`, `:model_key`
  (`:model`, the default, or `:patient_model`) and `:thinking` (`:default`,
  or `:lowest`); the call options and the configured `:req_options` still win
  over them.
  """
  @spec config(keyword(), keyword()) :: config()
  def config(opts, defaults \\ []) do
    app = Application.get_env(:backend, __MODULE__, [])

    req_options =
      app
      |> Keyword.get(:req_options, [])
      |> Keyword.merge(Keyword.get(opts, :req_options, []))
      |> Keyword.merge(Keyword.take(opts, [:plug, :retry]))

    req_options =
      case defaults[:receive_timeout] do
        timeout when is_integer(timeout) ->
          Keyword.put_new(req_options, :receive_timeout, timeout)

        _none ->
          req_options
      end

    model_key = Keyword.get(defaults, :model_key, :model)

    %{
      api_key: Keyword.get(opts, :api_key, app[:api_key]),
      base_url: opts[:base_url] || app[:base_url] || @default_base_url,
      model: opts[:model] || app[model_key] || Map.fetch!(@default_models, model_key),
      effort: opts[:effort] || defaults[:effort] || @default_effort,
      thinking: Keyword.get(defaults, :thinking, :default),
      req_options: req_options
    }
  end

  @doc "Sends one Messages request and returns its text, or a typed error."
  @spec create_message(config(), request()) :: {:ok, String.t()} | {:error, error()}
  def create_message(config, request) do
    with :ok <- validate_credentials(config.api_key),
         {:ok, body} <- post(config, body(config, request)) do
      parse(body)
    end
  end

  @doc """
  Streams one Messages request (`"stream": true`, issue #271) and calls
  `on_text` with each `text_delta` as it arrives, in order, from the calling
  process. The request body is `body/2` plus `stream`, so the cached system
  prefix, thinking and effort are unchanged.

  Returns the same outcomes as `create_message/2` once the stream ends:
  `{:ok, text}` (all deltas joined) after a normal stop, `{:error, :refused}`
  after a refusal, `{:error, :malformed_response}` after any other stop or
  without text, `{:error, :upstream_error}` on a non-2xx status or an `error`
  event. Deltas already handed over before an error stay handed over: the
  caller treats every delta as unverified candidate text. A non-2xx body is
  never handed over. Server-side fallbacks continue on the same stream, so
  their text arrives as more deltas.
  """
  @spec stream_message(config(), request(), (String.t() -> any())) ::
          {:ok, String.t()} | {:error, error()}
  def stream_message(config, request, on_text) when is_function(on_text, 1) do
    with :ok <- validate_credentials(config.api_key) do
      body = config |> body(request) |> Map.put("stream", true)
      stream_post(config, body, on_text)
    end
  end

  @doc "The request body sent for `request` under `config`."
  @spec body(config(), request()) :: map()
  def body(config, request) do
    output_config =
      case request[:schema] do
        schema when is_map(schema) ->
          %{"effort" => config.effort, "format" => %{"type" => "json_schema", "schema" => schema}}

        _none ->
          %{"effort" => config.effort}
      end

    %{
      "model" => config.model,
      "max_tokens" => request.max_tokens,
      "system" => system_blocks(request.system, request[:system_suffix]),
      "messages" => request.messages,
      "output_config" => output_config,
      "fallbacks" => "default"
    }
    |> put_thinking(config)
  end

  # The stable prefix ends at the cached block; a per-turn suffix follows it.
  defp system_blocks(system, suffix) do
    cached = %{"type" => "text", "text" => system, "cache_control" => %{"type" => "ephemeral"}}

    if is_binary(suffix) and String.trim(suffix) != "" do
      [cached, %{"type" => "text", "text" => suffix}]
    else
      [cached]
    end
  end

  # `between_tools` is valid only on Claude Sonnet 5.5, alone in `thinking`.
  defp put_thinking(body, %{thinking: :lowest, model: model})
       when model in @between_tools_models,
       do: Map.put(body, "thinking", %{"type" => "between_tools"})

  defp put_thinking(body, _config), do: body

  defp validate_credentials(key) when is_binary(key) do
    if String.trim(key) == "", do: {:error, :missing_credentials}, else: :ok
  end

  defp validate_credentials(_key), do: {:error, :missing_credentials}

  defp request_headers(config) do
    [
      {"x-api-key", config.api_key},
      {"anthropic-version", @anthropic_version},
      {"anthropic-beta", @fallback_beta}
    ]
  end

  defp post(config, body) do
    url = String.trim_trailing(config.base_url, "/") <> "/v1/messages"

    req_opts =
      Keyword.merge(
        [headers: request_headers(config), json: body, retry: false],
        config.req_options
      )

    started = System.monotonic_time()

    case Req.post(url, req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        log_usage(config.model, body, started)
        {:ok, body}

      {:ok, %Req.Response{}} ->
        {:error, :upstream_error}

      {:error, %Req.TransportError{reason: reason}} ->
        transport_error(reason)

      {:error, _exception} ->
        {:error, :network_error}
    end
  end

  @stream_key :anthropic_stream

  defp stream_post(config, body, on_text) do
    url = String.trim_trailing(config.base_url, "/") <> "/v1/messages"

    into = fn {:data, data}, {req, resp} ->
      state = Req.Response.get_private(resp, @stream_key, new_stream_state())

      state =
        if resp.status in 200..299,
          do: consume_sse(state, data, on_text),
          else: state

      {:cont, {req, Req.Response.put_private(resp, @stream_key, state)}}
    end

    req_opts =
      Keyword.merge(
        [headers: request_headers(config), json: body, retry: false, into: into],
        config.req_options
      )

    started = System.monotonic_time()

    case Req.post(url, req_opts) do
      {:ok, %Req.Response{status: status} = resp} when status in 200..299 ->
        state = Req.Response.get_private(resp, @stream_key, new_stream_state())
        log_usage(config.model, %{"usage" => state.usage}, started)
        stream_result(state)

      {:ok, %Req.Response{}} ->
        {:error, :upstream_error}

      {:error, %Req.TransportError{reason: reason}} ->
        transport_error(reason)

      {:error, _exception} ->
        {:error, :network_error}
    end
  end

  defp new_stream_state,
    do: %{buffer: "", text: [], stop_reason: nil, error?: false, usage: %{}}

  # SSE events end with a blank line; an event cut across chunks waits in the
  # buffer for the rest of it.
  defp consume_sse(state, data, on_text) do
    parts = String.split(state.buffer <> String.replace(data, "\r\n", "\n"), "\n\n")
    {events, [buffer]} = Enum.split(parts, -1)

    Enum.reduce(events, %{state | buffer: buffer}, &apply_event(&1, &2, on_text))
  end

  defp apply_event(raw_event, state, on_text) do
    data =
      raw_event
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "data:"))
      |> Enum.map_join("\n", &(&1 |> String.replace_prefix("data:", "") |> String.trim_leading()))

    case Jason.decode(data) do
      {:ok, event} when is_map(event) -> apply_decoded(event, state, on_text)
      _other -> state
    end
  end

  defp apply_decoded(
         %{"type" => "content_block_delta", "delta" => %{"type" => "text_delta", "text" => text}},
         state,
         on_text
       )
       when is_binary(text) do
    on_text.(text)
    %{state | text: [state.text | text]}
  end

  defp apply_decoded(%{"type" => "message_start", "message" => %{"usage" => usage}}, state, _)
       when is_map(usage),
       do: %{state | usage: Map.merge(state.usage, usage)}

  defp apply_decoded(%{"type" => "message_delta", "delta" => %{"stop_reason" => stop}}, state, _)
       when is_binary(stop),
       do: %{state | stop_reason: stop}

  defp apply_decoded(%{"type" => "error"}, state, _), do: %{state | error?: true}
  defp apply_decoded(_event, state, _), do: state

  defp stream_result(%{error?: true}), do: {:error, :upstream_error}
  defp stream_result(%{stop_reason: "refusal"}), do: {:error, :refused}

  defp stream_result(%{stop_reason: stop, text: text}) when stop in @normal_stops do
    text = IO.iodata_to_binary(text)
    if String.trim(text) == "", do: {:error, :malformed_response}, else: {:ok, text}
  end

  defp stream_result(_state), do: {:error, :malformed_response}

  defp log_usage(model, body, started) do
    latency_ms =
      System.convert_time_unit(System.monotonic_time() - started, :native, :millisecond)

    usage = if is_map(body) and is_map(body["usage"]), do: body["usage"], else: %{}

    Logger.debug(fn ->
      "anthropic_messages model=#{model} input_tokens=#{usage_count(usage, "input_tokens")}" <>
        " cache_read_input_tokens=#{usage_count(usage, "cache_read_input_tokens")}" <>
        " cache_creation_input_tokens=#{usage_count(usage, "cache_creation_input_tokens")}" <>
        " latency_ms=#{latency_ms}"
    end)
  end

  defp usage_count(usage, key) do
    case usage[key] do
      count when is_integer(count) -> count
      _missing -> 0
    end
  end

  defp transport_error(reason) when reason in [:timeout, :connect_timeout],
    do: {:error, :timeout}

  defp transport_error({:timeout, _detail}), do: {:error, :timeout}
  defp transport_error(_reason), do: {:error, :network_error}

  defp parse(%{"stop_reason" => "refusal"}), do: {:error, :refused}

  defp parse(%{"stop_reason" => stop, "content" => content})
       when stop in @normal_stops and is_list(content) do
    text =
      content
      |> Enum.filter(&match?(%{"type" => "text", "text" => text} when is_binary(text), &1))
      |> Enum.map_join(& &1["text"])

    if String.trim(text) == "", do: {:error, :malformed_response}, else: {:ok, text}
  end

  defp parse(_body), do: {:error, :malformed_response}
end
