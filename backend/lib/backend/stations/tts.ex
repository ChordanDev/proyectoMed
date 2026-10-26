defmodule Backend.Stations.TTS do
  @moduledoc """
  Single point of contact between the backend and the text-to-speech provider.

  OpenAI's speech API is the default. When `:voice_provider` is
  `:deepgram_cartesia`, the text goes to Cartesia instead
  (`Backend.Stations.TTS.Cartesia`); text and voice validation, consent and session
  checks, the mp3 format and the error outcomes are the same for both providers.

  Before either provider is called, the patient's stage directions (`*…*` spans and a
  leading or standalone closing parenthesized action) are removed from the text
  (`Backend.Stations.TTS.StageDirections`). A reply made only of stage directions is
  `{:error, :invalid_text}` and no provider is called.

  Symmetric to `Backend.Stations.Transcription`: text goes in, audio comes out. The
  synthesized audio is streamed straight back to the caller and discarded:
  nothing is persisted server-side and the text is never logged.

  ## Retry policy

  None. On any provider failure the error is surfaced as `{:error, :openai_unavailable}`
  and the client decides the fallback policy (text-only render).
  """

  alias Backend.Stations.Conversation
  alias Backend.Stations.TTS.Cartesia
  alias Backend.Stations.TTS.StageDirections

  @allowed_voices ~w(alloy echo fable onyx nova shimmer)
  @default_voice "alloy"
  @default_model "tts-1"
  @default_base_url "https://api.openai.com"
  @format "mp3"
  # OpenAI rejects inputs above 4096 characters.
  @max_text_length 4096

  @type result :: %{
          audio_binary: binary(),
          format: String.t(),
          synthesized_at: DateTime.t()
        }
  @type error :: :expired | :not_found | :no_consent | :openai_unavailable | :invalid_text

  @spec allowed_voices() :: [String.t()]
  def allowed_voices, do: @allowed_voices

  @spec format() :: String.t()
  def format, do: @format

  @spec synthesize(String.t(), String.t(), String.t() | nil, keyword()) ::
          {:ok, result()} | {:error, error()}
  def synthesize(session_id, text, voice \\ nil, opts \\ []) do
    with {:ok, text} <- validate_text(text),
         {:ok, voice} <- validate_voice(voice),
         {:ok, session} <- fetch_session(session_id),
         :ok <- validate_consent(session),
         {:ok, audio} <- provider_synthesize(text, voice, opts) do
      {:ok, %{audio_binary: audio, format: @format, synthesized_at: DateTime.utc_now()}}
    end
  end

  defp provider_synthesize(text, voice, opts) do
    case Application.get_env(:backend, :voice_provider, :openai) do
      :deepgram_cartesia -> Cartesia.synthesize(text, opts)
      _openai -> request(text, voice, config(opts))
    end
  end

  # Stage directions are removed here, before any provider is chosen, so neither
  # provider reads them aloud; a reply made only of them has nothing to synthesize.
  defp validate_text(text) when is_binary(text) and byte_size(text) <= @max_text_length do
    case StageDirections.strip(text) do
      "" -> {:error, :invalid_text}
      speakable -> {:ok, speakable}
    end
  end

  defp validate_text(_text), do: {:error, :invalid_text}

  defp validate_voice(voice) when voice in [nil, ""], do: {:ok, default_voice()}
  defp validate_voice(voice) when voice in @allowed_voices, do: {:ok, voice}
  defp validate_voice(_voice), do: {:error, :invalid_text}

  defp default_voice do
    case Application.get_env(:backend, :openai_tts_voice) do
      voice when voice in @allowed_voices -> voice
      _ -> @default_voice
    end
  end

  defp fetch_session(session_id), do: Conversation.fetch(session_id)

  defp validate_consent(%{audio_consent: true}), do: :ok
  defp validate_consent(_session), do: {:error, :no_consent}

  defp config(opts) do
    %{
      api_key: opts[:api_key] || Application.get_env(:backend, :openai_api_key),
      base_url:
        opts[:base_url] || Application.get_env(:backend, :openai_base_url) || @default_base_url,
      model: opts[:model] || Application.get_env(:backend, :openai_tts_model) || @default_model,
      req_options:
        :backend
        |> Application.get_env(:openai_req_options, [])
        |> Keyword.merge(Keyword.take(opts, [:plug, :retry, :receive_timeout]))
    }
  end

  defp request(_text, _voice, %{api_key: key}) when key in [nil, ""],
    do: {:error, :openai_unavailable}

  defp request(text, voice, config) do
    url = String.trim_trailing(config.base_url, "/") <> "/v1/audio/speech"

    req_opts =
      [
        auth: {:bearer, config.api_key},
        retry: false,
        json: %{
          model: config.model,
          input: text,
          voice: voice,
          response_format: @format
        }
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

defmodule Backend.TTS do
  @moduledoc false
  defdelegate allowed_voices(), to: Backend.Stations.TTS
  defdelegate format(), to: Backend.Stations.TTS
  defdelegate synthesize(session_id, text), to: Backend.Stations.TTS
  defdelegate synthesize(session_id, text, voice), to: Backend.Stations.TTS
  defdelegate synthesize(session_id, text, voice, opts), to: Backend.Stations.TTS
end
