defmodule BackendWeb.TranscriptionController do
  @moduledoc """
  `POST /api/stations/active/sessions/:id/transcribe`.

  Accepts a `multipart/form-data` audio blob, hands it to `Backend.Stations`
  and returns the transcription. Audio is never written to disk by this
  controller beyond the temporary upload Plug already manages, and never logged.
  """

  use BackendWeb, :controller

  alias Backend.Stations

  @max_bytes 10 * 1024 * 1024

  def create(conn, %{"id" => session_id, "audio" => %Plug.Upload{} = upload}) do
    with {:ok, audio} <- read_audio(upload),
         {:ok, result} <- Stations.transcribe_audio(session_id, audio, format(upload)) do
      json(conn, %{
        text: result.text,
        duration_seconds: result.duration_seconds,
        transcribed_at: DateTime.to_iso8601(result.transcribed_at)
      })
    else
      {:error, reason} -> send_error(conn, reason)
    end
  end

  def create(conn, _params), do: send_error(conn, :invalid_audio)

  defp read_audio(%Plug.Upload{path: path}) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} when size > @max_bytes -> {:error, :audio_too_large}
      {:ok, %File.Stat{size: 0}} -> {:error, :invalid_audio}
      {:ok, _} -> File.read(path) |> normalize_read()
      {:error, _} -> {:error, :invalid_audio}
    end
  end

  defp normalize_read({:ok, audio}), do: {:ok, audio}
  defp normalize_read({:error, _}), do: {:error, :invalid_audio}

  defp format(%Plug.Upload{filename: filename}) do
    filename |> Path.extname() |> String.trim_leading(".") |> String.downcase()
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
  defp error_details(:audio_too_large), do: {413, "O áudio excede o limite de 10 MB."}

  defp error_details(:openai_unavailable),
    do: {502, "O serviço de transcrição está indisponível. Tente novamente."}

  defp error_details(_),
    do: {400, "Áudio ausente ou inválido. Formatos aceitos: m4a, wav, webm."}
end
