defmodule BackendWeb.TTSController do
  @moduledoc """
  `POST /api/stations/active/sessions/:id/synthesize`.

  Accepts JSON `{text, voice?}`, hands it to `Backend.Stations` and streams the
  synthesized audio back as `audio/mpeg`. The audio is never written to disk
  and neither the text nor the audio is logged.
  """

  use BackendWeb, :controller

  alias Backend.Stations

  def create(conn, %{"id" => session_id} = params) do
    case Stations.synthesize_speech(session_id, params["text"], params["voice"]) do
      {:ok, result} ->
        conn
        |> put_resp_content_type("audio/mpeg", nil)
        |> put_resp_header("x-synthesized-at", DateTime.to_iso8601(result.synthesized_at))
        |> send_resp(200, result.audio_binary)

      {:error, reason} ->
        send_error(conn, reason)
    end
  end

  defp send_error(conn, reason) do
    {status, message} = error_details(reason)

    conn
    |> put_status(status)
    |> json(%{error: to_string(reason), message: message})
  end

  defp error_details(:not_found), do: {404, "Sessão não encontrada."}
  defp error_details(:expired), do: {410, "A sessão expirou. Inicie uma nova estação."}
  defp error_details(:no_consent), do: {403, "A sessão não tem consentimento para áudio."}

  defp error_details(:openai_unavailable),
    do: {502, "O serviço de voz está indisponível. Continue pelo texto."}

  defp error_details(_),
    do:
      {400,
       "Texto ausente ou inválido. Vozes aceitas: #{Enum.join(Stations.allowed_tts_voices(), ", ")}."}
end
