defmodule Backend.Stations.StationAI.OpenAIAdapter do
  @moduledoc """
  `Backend.Stations.StationAI` adapter backed by OpenAI's Chat Completions API.

  Translates the active Station Package and conversation history into OpenAI
  messages, sends a `POST /v1/chat/completions` request using Req, and normalizes
  the response into the StationAI contract.

  ## Error Normalization

  Errors are normalized into a small provider-neutral vocabulary:

    * `{:error, :missing_credentials}` - API key is absent or blank
    * `{:error, :upstream_error}` - non-2xx HTTP response from OpenAI
    * `{:error, :timeout}` - request timed out
    * `{:error, :network_error}` - transport or connection failure
    * `{:error, :malformed_response}` - invalid or unparseable completion payload
  """

  @behaviour Backend.Stations.StationAI

  alias Backend.Stations.StationAI

  @default_model "gpt-4o-mini"
  @default_base_url "https://api.openai.com"

  @impl true
  def next_reply(package, context, opts \\ []) do
    config = get_config(opts)

    with :ok <- validate_credentials(config.api_key),
         payload <- build_payload(package, context, config.model),
         {:ok, response} <- execute_request(config, payload) do
      parse_response(response)
    end
  end

  defp get_config(opts) do
    legacy_app = Application.get_env(:backend, Backend.StationAI.OpenAIAdapter, [])
    current_app = Application.get_env(:backend, __MODULE__, [])
    app = Keyword.merge(legacy_app, current_app)

    %{
      api_key: opts[:api_key] || Keyword.get(app, :api_key) || System.get_env("OPENAI_API_KEY"),
      base_url:
        opts[:base_url] || Keyword.get(app, :base_url) || System.get_env("OPENAI_BASE_URL") ||
          @default_base_url,
      model:
        opts[:model] || Keyword.get(app, :model) || System.get_env("OPENAI_MODEL") ||
          @default_model,
      req_options:
        app
        |> Keyword.get(:req_options, [])
        |> Keyword.merge(Keyword.get(opts, :req_options, []))
        |> Keyword.merge(Keyword.take(opts, [:plug, :retry]))
    }
  end

  defp validate_credentials(key) when is_binary(key) do
    if String.trim(key) == "", do: {:error, :missing_credentials}, else: :ok
  end

  defp validate_credentials(_), do: {:error, :missing_credentials}

  defp build_payload(package, context, model) do
    system_msg = %{
      "role" => "system",
      "content" => StationAI.system_prompt(package)
    }

    history =
      (context[:conversation] || Map.get(context, "conversation", []))
      |> Enum.map(&format_message/1)

    %{"model" => model, "messages" => [system_msg | history]}
  end

  defp format_message(msg) do
    role =
      case msg[:role] || msg["role"] do
        r when r in [:student, "student"] -> "user"
        r when r in [:patient, "patient"] -> "assistant"
        other -> to_string(other)
      end

    %{"role" => role, "content" => msg[:text] || msg["text"]}
  end

  defp execute_request(config, payload) do
    url = String.trim_trailing(config.base_url, "/") <> "/v1/chat/completions"

    req_opts =
      [auth: {:bearer, config.api_key}, json: payload, retry: false]
      |> Keyword.merge(config.req_options)

    case Req.post(url, req_opts) do
      {:ok, %Req.Response{status: s, body: body}} when s in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{}} ->
        {:error, :upstream_error}

      {:error, %Req.TransportError{reason: r}} when r in [:timeout, :connect_timeout] ->
        {:error, :timeout}

      {:error, %Req.TransportError{reason: {:timeout, _}}} ->
        {:error, :timeout}

      {:error, _} ->
        {:error, :network_error}
    end
  end

  defp parse_response(%{"choices" => [%{"message" => %{"content" => content}} | _]})
       when is_binary(content) do
    {:ok, %{text: content}}
  end

  defp parse_response(_), do: {:error, :malformed_response}
end

defmodule Backend.StationAI.OpenAIAdapter do
  @moduledoc false
  @behaviour Backend.StationAI

  alias Backend.Stations.StationAI.OpenAIAdapter, as: Target

  @impl true
  defdelegate next_reply(package, context), to: Target

  defdelegate next_reply(package, context, opts), to: Target
end
