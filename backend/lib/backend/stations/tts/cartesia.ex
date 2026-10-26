defmodule Backend.Stations.TTS.Cartesia do
  @moduledoc """
  Cartesia text-to-speech (`POST /tts/bytes`) for the patient voice (#398).

  Used by `Backend.Stations.TTS` when `:voice_provider` is `:deepgram_cartesia`. The
  patient always speaks with the configured `:cartesia_voice_id`; the OpenAI voice
  names the endpoint accepts are not Cartesia voices and are ignored here. Audio is
  requested as mp3 (44.1 kHz, 128 kbps), the format the web already plays, in
  Portuguese. Neither the text nor the audio is logged or persisted.

  Every provider failure (missing key or voice id, transport error or timeout, non-2xx
  status, empty body) is `{:error, :openai_unavailable}`, the outcome the controllers
  and the web already handle for the voice service.
  """

  @default_base_url "https://api.cartesia.ai"
  # Same model as the real-time voice worker (#360); override with CARTESIA_MODEL.
  @default_model "sonic-3"
  @api_version "2026-08-14"
  @output_format %{container: "mp3", sample_rate: 44_100, bit_rate: 128_000}

  @spec synthesize(String.t(), keyword()) :: {:ok, binary()} | {:error, :openai_unavailable}
  def synthesize(text, opts), do: request(text, config(opts))

  defp config(opts) do
    %{
      api_key: opts[:api_key] || Application.get_env(:backend, :cartesia_api_key),
      voice_id: opts[:voice_id] || Application.get_env(:backend, :cartesia_voice_id),
      base_url:
        opts[:base_url] || Application.get_env(:backend, :cartesia_base_url) ||
          @default_base_url,
      model: opts[:model] || Application.get_env(:backend, :cartesia_model) || @default_model,
      req_options: Keyword.take(opts, [:plug, :retry, :receive_timeout])
    }
  end

  defp request(_text, %{api_key: key}) when key in [nil, ""], do: {:error, :openai_unavailable}
  defp request(_text, %{voice_id: id}) when id in [nil, ""], do: {:error, :openai_unavailable}

  defp request(text, config) do
    req_opts =
      [
        headers: [
          {"authorization", "Bearer " <> config.api_key},
          {"cartesia-version", @api_version}
        ],
        json: %{
          model_id: config.model,
          transcript: text,
          voice: %{mode: "id", id: config.voice_id},
          language: "pt",
          output_format: @output_format
        },
        retry: false
      ]
      |> Keyword.merge(config.req_options)

    case Req.post(String.trim_trailing(config.base_url, "/") <> "/tts/bytes", req_opts) do
      {:ok, %Req.Response{status: s, body: audio}}
      when s in 200..299 and is_binary(audio) and byte_size(audio) > 0 ->
        {:ok, audio}

      _ ->
        {:error, :openai_unavailable}
    end
  end
end
