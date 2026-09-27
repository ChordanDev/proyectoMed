defmodule Backend.Stations.Transcription do
  @moduledoc """
  Single point of contact between the backend and OpenAI's audio transcription API.

  Audio bytes are streamed in, transcribed and discarded: nothing is persisted
  server-side and audio content is never logged.

  ## Retry policy

  None. On any OpenAI failure the error is surfaced as `{:error, :openai_unavailable}`
  and the client decides the fallback policy.
  """

  alias Backend.Stations.Conversation

  @allowed_formats ~w(m4a wav webm)
  @default_model "whisper-1"
  @default_base_url "https://api.openai.com"

  @type result :: %{
          text: String.t(),
          duration_seconds: number() | nil,
          transcribed_at: DateTime.t()
        }
  @type error :: :expired | :not_found | :no_consent | :openai_unavailable | :invalid_audio

  @spec allowed_formats() :: [String.t()]
  def allowed_formats, do: @allowed_formats

  @spec transcribe(String.t(), binary(), String.t(), keyword()) ::
          {:ok, result()} | {:error, error()}
  def transcribe(session_id, audio, format, opts \\ []) do
    with :ok <- validate_audio(audio, format),
         {:ok, session} <- fetch_session(session_id),
         :ok <- validate_consent(session),
         {:ok, body} <- request(audio, format, config(opts)) do
      parse(body)
    end
  end

  defp validate_audio(audio, format)
       when is_binary(audio) and byte_size(audio) > 0 and format in @allowed_formats,
       do: :ok

  defp validate_audio(_audio, _format), do: {:error, :invalid_audio}

  defp fetch_session(session_id), do: Conversation.fetch(session_id)

  defp validate_consent(%{audio_consent: true}), do: :ok
  defp validate_consent(_session), do: {:error, :no_consent}

  defp config(opts) do
    %{
      api_key: opts[:api_key] || Application.get_env(:backend, :openai_api_key),
      base_url:
        opts[:base_url] || Application.get_env(:backend, :openai_base_url) || @default_base_url,
      model:
        opts[:model] || Application.get_env(:backend, :openai_transcription_model) ||
          @default_model,
      req_options:
        :backend
        |> Application.get_env(:openai_req_options, [])
        |> Keyword.merge(Keyword.take(opts, [:plug, :retry, :receive_timeout]))
    }
  end

  defp request(_audio, _format, %{api_key: key}) when key in [nil, ""],
    do: {:error, :openai_unavailable}

  defp request(audio, format, config) do
    url = String.trim_trailing(config.base_url, "/") <> "/v1/audio/transcriptions"

    req_opts =
      [
        auth: {:bearer, config.api_key},
        retry: false,
        form_multipart: [
          model: config.model,
          response_format: "verbose_json",
          file: {audio, filename: "audio.#{format}"}
        ]
      ]
      |> Keyword.merge(config.req_options)

    case Req.post(url, req_opts) do
      {:ok, %Req.Response{status: s, body: body}} when s in 200..299 -> {:ok, body}
      _ -> {:error, :openai_unavailable}
    end
  end

  defp parse(%{"text" => text} = body) when is_binary(text) do
    {:ok,
     %{
       text: text,
       duration_seconds: body["duration"],
       transcribed_at: DateTime.utc_now()
     }}
  end

  defp parse(_body), do: {:error, :openai_unavailable}
end

defmodule Backend.Transcription do
  @moduledoc false
  defdelegate allowed_formats(), to: Backend.Stations.Transcription
  defdelegate transcribe(session_id, audio, format), to: Backend.Stations.Transcription
  defdelegate transcribe(session_id, audio, format, opts), to: Backend.Stations.Transcription
end
