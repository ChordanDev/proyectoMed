defmodule BackendWeb.VoiceWorkerController do
  @moduledoc """
  Server-to-server API for the Python voice worker (#118).

    * `GET  /api/internal/voice/sessions/:id` — context before streaming audio
      to Deepgram (language, station keyterms, last committed turn).
    * `POST /api/internal/voice/sessions/:id/transcripts` — commits one final
      transcript as a learner turn, at most once per monotonic `turn_id`.

  Authenticated with a shared bearer secret (`VOICE_WORKER_SECRET`). With no
  secret configured every request is refused. Transcript text is never logged.
  """

  use BackendWeb, :controller

  alias Backend.Stations

  plug :authenticate

  def show(conn, %{"id" => session_id}) do
    case Stations.voice_worker_context(session_id) do
      {:ok, context} -> json(conn, context)
      {:error, reason} -> send_error(conn, reason)
    end
  end

  def create_transcript(conn, %{"id" => session_id} = params) do
    with {:ok, turn_id, text} <- validate_transcript(params),
         {:ok, status} <- Stations.commit_voice_transcript(session_id, turn_id, text) do
      conn
      |> put_status(if status == :committed, do: :created, else: :ok)
      |> json(%{turn_id: turn_id, status: status})
    else
      {:error, reason} -> send_error(conn, reason)
    end
  end

  defp validate_transcript(%{"turn_id" => turn_id, "text" => text})
       when is_integer(turn_id) and turn_id > 0 and is_binary(text) do
    case String.trim(text) do
      "" -> {:error, :invalid_transcript}
      trimmed -> {:ok, turn_id, trimmed}
    end
  end

  defp validate_transcript(_params), do: {:error, :invalid_transcript}

  defp authenticate(conn, _opts) do
    secret = Application.get_env(:backend, :voice_worker_secret)

    with true <- is_binary(secret) and secret != "",
         ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         true <- Plug.Crypto.secure_compare(token, secret) do
      conn
    else
      _ -> conn |> send_error(:unauthorized) |> halt()
    end
  end

  defp send_error(conn, reason) do
    {status, code} = error_details(reason)
    conn |> put_status(status) |> json(%{error: code})
  end

  defp error_details(:unauthorized), do: {401, "unauthorized"}
  defp error_details(:invalid_transcript), do: {400, "invalid_transcript"}
  defp error_details(:not_found), do: {404, "session_not_found"}
  defp error_details(:expired), do: {410, "session_expired"}
  defp error_details(:completed), do: {422, "session_completed"}
  defp error_details(:no_consent), do: {403, "no_consent"}
end
