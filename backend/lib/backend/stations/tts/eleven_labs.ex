defmodule Backend.Stations.TTS.ElevenLabs do
  @moduledoc """
  ElevenLabs text-to-speech (`POST /v1/text-to-speech/:voice_id`) for the patient voice.

  Used by `Backend.Stations.TTS` when `:voice_provider` is `:deepgram_elevenlabs`. The
  patient always speaks with the configured `:elevenlabs_voice_id`; the OpenAI voice
  names the endpoint accepts are not ElevenLabs voices and are ignored here. Audio is
  requested as mp3 (`mp3_44100_128`), the format the web already plays. Neither the
  text nor the audio is logged or persisted.

  Every provider failure (missing key or voice id, transport error or timeout, non-2xx
  status, empty body) is `{:error, :openai_unavailable}`, the outcome the controllers
  and the web already handle for the voice service.
  """

  @default_base_url "https://api.elevenlabs.io"
  # Lowest-latency ElevenLabs model that covers pt-BR (same choice as #120).
  @default_model "eleven_flash_v2_5"
  @output_format "mp3_44100_128"

  @spec synthesize(String.t(), keyword()) :: {:ok, binary()} | {:error, :openai_unavailable}
  def synthesize(text, opts), do: request(text, config(opts))

  defp config(opts) do
    %{
      api_key: opts[:api_key] || Application.get_env(:backend, :elevenlabs_api_key),
      voice_id: opts[:voice_id] || Application.get_env(:backend, :elevenlabs_voice_id),
      base_url:
        opts[:base_url] || Application.get_env(:backend, :elevenlabs_base_url) ||
          @default_base_url,
      model: opts[:model] || Application.get_env(:backend, :elevenlabs_model) || @default_model,
      req_options: Keyword.take(opts, [:plug, :retry, :receive_timeout])
    }
  end

  defp request(_text, %{api_key: key}) when key in [nil, ""], do: {:error, :openai_unavailable}
  defp request(_text, %{voice_id: id}) when id in [nil, ""], do: {:error, :openai_unavailable}

  defp request(text, config) do
    url =
      String.trim_trailing(config.base_url, "/") <>
        "/v1/text-to-speech/" <> URI.encode(config.voice_id, &URI.char_unreserved?/1)

    req_opts =
      [
        headers: [{"xi-api-key", config.api_key}],
        params: [output_format: @output_format],
        json: %{text: text, model_id: config.model},
        retry: false
      ]
      |> Keyword.merge(config.req_options)

    case Req.post(url, req_opts) do
      {:ok, %Req.Response{status: s, body: audio}}
      when s in 200..299 and is_binary(audio) and byte_size(audio) > 0 ->
        {:ok, audio}

      _ ->
        {:error, :openai_unavailable}
    end
  end
end
