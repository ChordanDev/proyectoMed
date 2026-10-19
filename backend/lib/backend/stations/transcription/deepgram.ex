defmodule Backend.Stations.Transcription.Deepgram do
  @moduledoc """
  Deepgram pre-recorded transcription (`POST /v1/listen`) for the turn-based voice.

  Used by `Backend.Stations.Transcription` when `:voice_provider` is
  `:deepgram_elevenlabs`. The raw audio bytes are posted as the request body with the
  content type of their format and the transcript is requested in pt-BR. Neither the
  audio nor the transcript is logged or persisted.

  Every provider failure (missing key, transport error or timeout, non-2xx status,
  malformed body) is `{:error, :openai_unavailable}`, the outcome the controllers and
  the web already handle for the voice service.
  """

  @default_base_url "https://api.deepgram.com"
  @default_model "nova-3"
  @language "pt-BR"
  @content_types %{"m4a" => "audio/mp4", "wav" => "audio/wav", "webm" => "audio/webm"}

  @spec transcribe(binary(), String.t(), keyword()) ::
          {:ok, %{text: String.t(), duration_seconds: number() | nil}}
          | {:error, :openai_unavailable}
  def transcribe(audio, format, opts) do
    with {:ok, body} <- request(audio, format, config(opts)) do
      parse(body)
    end
  end

  defp config(opts) do
    %{
      api_key: opts[:api_key] || Application.get_env(:backend, :deepgram_api_key),
      base_url:
        opts[:base_url] || Application.get_env(:backend, :deepgram_base_url) ||
          @default_base_url,
      model: opts[:model] || Application.get_env(:backend, :deepgram_model) || @default_model,
      req_options: Keyword.take(opts, [:plug, :retry, :receive_timeout])
    }
  end

  defp request(_audio, _format, %{api_key: key}) when key in [nil, ""],
    do: {:error, :openai_unavailable}

  defp request(audio, format, config) do
    url = String.trim_trailing(config.base_url, "/") <> "/v1/listen"

    req_opts =
      [
        headers: [
          {"authorization", "Token " <> config.api_key},
          {"content-type", Map.fetch!(@content_types, format)}
        ],
        params: [model: config.model, language: @language, smart_format: true],
        body: audio,
        retry: false
      ]
      |> Keyword.merge(config.req_options)

    case Req.post(url, req_opts) do
      {:ok, %Req.Response{status: s, body: %{} = body}} when s in 200..299 -> {:ok, body}
      _ -> {:error, :openai_unavailable}
    end
  end

  defp parse(%{"results" => %{"channels" => channels}} = body) when is_list(channels) do
    with {:ok, text} <- first_transcript(channels) do
      {:ok, %{text: text, duration_seconds: duration(body["metadata"])}}
    end
  end

  defp parse(_body), do: {:error, :openai_unavailable}

  defp duration(%{"duration" => seconds}) when is_number(seconds), do: seconds
  defp duration(_metadata), do: nil

  # No channel means Deepgram heard nothing: an empty transcript, as OpenAI returns.
  defp first_transcript([]), do: {:ok, ""}

  defp first_transcript([%{"alternatives" => [%{"transcript" => text} | _]} | _])
       when is_binary(text),
       do: {:ok, text}

  defp first_transcript([%{"alternatives" => []} | _]), do: {:ok, ""}
  defp first_transcript(_channels), do: {:error, :openai_unavailable}
end
