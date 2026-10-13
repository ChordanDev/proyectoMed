defmodule BackendWeb.VoiceWorkerController do
  @moduledoc """
  Server-to-server API for the Python voice worker (#118, #119).

    * `GET  /api/internal/voice/sessions/:id` — context before streaming audio
      to Deepgram (language, station keyterms, last committed turn).
    * `POST /api/internal/voice/sessions/:id/transcripts` — processes one final
      transcript as a learner turn via `Backend.Stations.process_voice_turn/3`,
      returning only verified `reply_text` with `turn_id` and `generation_id` on success.
      Duplicate finals stay 200 and never replay text. Once the station time is
      over it answers `409` with `station_time_elapsed`: a new turn at or after
      the deadline, any turn on a session the timer completed, or a reply that
      missed the deadline grace window. Unlike `409 stale_generation`, which only
      drops one superseded turn, this ends the voice session and must not be retried.
    * `POST /api/internal/voice/sessions/:id/cancel` — cancels a pending voice
      generation via `Backend.Stations.cancel_voice_turn/2`.

  Authenticated with a shared bearer secret (`VOICE_WORKER_SECRET`). With no
  secret configured every request is refused. Transcript and reply text are never logged.
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
         {:ok, result} <- Stations.process_voice_turn(session_id, turn_id, text) do
      case result do
        :duplicate ->
          conn
          |> put_status(:ok)
          |> json(%{turn_id: turn_id, status: "duplicate"})

        %{reply_text: reply_text, turn_id: ^turn_id, generation_id: generation_id} ->
          conn
          |> put_status(:created)
          |> json(%{
            turn_id: turn_id,
            status: "committed",
            generation_id: generation_id,
            reply_text: reply_text
          })
      end
    else
      {:error, reason} -> send_error(conn, reason)
    end
  end

  def cancel(conn, %{"id" => session_id} = params) do
    with {:ok, cancel_target} <- validate_cancel_params(params),
         {:ok, :cancelled} <- Stations.cancel_voice_turn(session_id, cancel_target) do
      conn
      |> put_status(:ok)
      |> json(%{status: "cancelled", session_id: session_id})
    else
      {:error, reason} -> send_error(conn, reason)
    end
  end

  defp validate_cancel_params(params) do
    with {:ok, generation_id} <- validate_generation_id(params),
         {:ok, turn_id} <- validate_turn_id(params) do
      case {generation_id, turn_id} do
        {nil, nil} -> {:ok, nil}
        {gen_id, nil} -> {:ok, gen_id}
        {nil, turn_id} -> {:ok, [turn_id: turn_id]}
        {gen_id, turn_id} -> {:ok, [turn_id: turn_id, generation_id: gen_id]}
      end
    end
  end

  defp validate_generation_id(%{"generation_id" => nil}), do: {:ok, nil}

  defp validate_generation_id(%{"generation_id" => id})
       when is_integer(id) and id > 0,
       do: {:ok, id}

  defp validate_generation_id(%{"generation_id" => _}), do: {:error, :invalid_generation_id}
  defp validate_generation_id(_params), do: {:ok, nil}

  defp validate_turn_id(%{"turn_id" => nil}), do: {:ok, nil}

  defp validate_turn_id(%{"turn_id" => id})
       when is_integer(id) and id > 0,
       do: {:ok, id}

  defp validate_turn_id(%{"turn_id" => _}), do: {:error, :invalid_turn_id}
  defp validate_turn_id(_params), do: {:ok, nil}

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
  defp error_details(:invalid_generation_id), do: {400, "invalid_generation_id"}
  defp error_details(:invalid_turn_id), do: {400, "invalid_turn_id"}
  defp error_details(:not_found), do: {404, "session_not_found"}
  defp error_details(:no_consent), do: {403, "no_consent"}
  defp error_details(:stale_generation), do: {409, "stale_generation"}
  defp error_details(:station_time_elapsed), do: {409, "station_time_elapsed"}
  defp error_details(:expired), do: {410, "session_expired"}
  defp error_details(:completed), do: {422, "session_completed"}
  defp error_details(:station_ai_unavailable), do: {503, "station_ai_unavailable"}
end
