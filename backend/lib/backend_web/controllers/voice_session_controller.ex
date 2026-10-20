defmodule BackendWeb.VoiceSessionController do
  @moduledoc """
  `POST /api/stations/active/sessions/:id/voice`.

  Issues a short-lived, session-scoped LiveKit access token so the browser
  can join the voice room over WebRTC. The LiveKit API secret never leaves
  `Backend.Stations`; only the signed token is returned.
  """

  use BackendWeb, :controller

  alias Backend.Stations

  def create(conn, %{"id" => session_id}) do
    case Stations.create_voice_session(session_id) do
      {:ok, result} ->
        conn
        |> put_status(:created)
        |> json(%{
          url: result.url,
          token: result.token,
          room: result.room,
          identity: result.identity,
          expires_at: DateTime.to_iso8601(result.expires_at)
        })

      {:error, reason} ->
        send_error(conn, reason)
    end
  end

  defp send_error(conn, reason) do
    {status, code, message} = error_details(reason)

    conn
    |> put_status(status)
    |> json(%{error: code, message: message})
  end

  defp error_details(:not_found),
    do: {404, "session_not_found", "Sessão não encontrada."}

  defp error_details(:expired),
    do: {410, "session_expired", "A sessão expirou."}

  defp error_details(:completed),
    do: {422, "session_completed", "A sessão já foi concluída."}

  defp error_details(:no_consent),
    do: {403, "no_consent", "A sessão não tem consentimento para áudio."}

  defp error_details(:rate_limited),
    do:
      {429, "rate_limited",
       "Muitas solicitações de voz para esta sessão. Aguarde um instante e tente novamente."}

  defp error_details(:voice_unavailable),
    do:
      {503, "voice_unavailable",
       "O serviço de voz em tempo real está indisponível. Continue pelo texto."}
end
