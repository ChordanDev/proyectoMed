defmodule BackendWeb.VoiceWorkerController do
  @moduledoc """
  Server-to-server API for the Python voice worker (#118, #119).

    * `GET  /api/internal/voice/sessions/:id` — context before streaming audio
      to Deepgram (language, station keyterms, last committed turn).
    * `POST /api/internal/voice/sessions/:id/transcripts` — processes one final
      transcript as a learner turn via `Backend.Stations.process_voice_turn/3`,
      returning only verified `reply_text` with `turn_id` and `generation_id` on success.
      A refused patient reply keeps the learner turn and answers `201` with
      `status: "kept"`, `addressee: "patient"` and no text (#269). A turn Jev
      decides is addressed to the examiner (#274) is kept before any generation
      and answers `201` with `status: "kept"` and `addressee: "examiner"`.
      With `application/x-ndjson` in `Accept` (#271; the worker sends `application/x-ndjson, application/json`, since the API pipeline accepts JSON) the reply is streamed: the
      first verified sentence opens a `200` chunked NDJSON body, one line per
      verified sentence (`{"type":"sentence","turn_id","generation_id","index","text"}`,
      text without stage directions), then one last line: the `result`
      (`status: "committed"` with the spoken `reply_text`) or an `error` with
      the same code the status response would carry. A turn that speaks
      nothing answers exactly as without the header.
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

  @ndjson "application/x-ndjson"

  plug :authenticate

  def show(conn, %{"id" => session_id}) do
    case Stations.voice_worker_context(session_id) do
      {:ok, context} -> json(conn, context)
      {:error, reason} -> send_error(conn, reason)
    end
  end

  def create_transcript(conn, %{"id" => session_id} = params) do
    case validate_transcript(params) do
      {:ok, turn_id, text} ->
        if sentence_stream?(conn) do
          {result, conn} =
            Stations.stream_voice_turn(session_id, turn_id, text, conn, &send_sentence/2)

          finish_transcript(conn, turn_id, result)
        else
          render_transcript(conn, turn_id, Stations.process_voice_turn(session_id, turn_id, text))
        end

      {:error, reason} ->
        send_error(conn, reason)
    end
  end

  defp sentence_stream?(conn) do
    conn
    |> get_req_header("accept")
    |> Enum.any?(&String.contains?(&1, @ndjson))
  end

  # The first verified sentence opens the chunked NDJSON body (#271).
  defp send_sentence({:sentence, sentence}, conn) do
    conn =
      if conn.state == :chunked,
        do: conn,
        else: conn |> put_resp_content_type(@ndjson) |> send_chunked(200)

    line = Map.put(sentence, :type, "sentence")

    case chunk(conn, [Jason.encode_to_iodata!(line), "\n"]) do
      {:ok, conn} -> {:cont, conn}
      {:error, _reason} -> {:halt, conn}
    end
  end

  # Once a sentence was streamed the status is sent, so the result or the
  # error is the last line; otherwise the answer is the single-reply form.
  defp finish_transcript(%Plug.Conn{state: :chunked} = conn, turn_id, result) do
    line =
      case result do
        {:ok, %{reply_text: reply_text, generation_id: generation_id}} ->
          %{
            type: "result",
            turn_id: turn_id,
            status: "committed",
            generation_id: generation_id,
            reply_text: reply_text
          }

        {:ok, {:kept, %{generation_id: generation_id} = kept}} ->
          %{
            type: "result",
            turn_id: turn_id,
            status: "kept",
            generation_id: generation_id,
            addressee: kept_addressee(kept)
          }

        {:ok, :duplicate} ->
          %{type: "result", turn_id: turn_id, status: "duplicate"}

        {:error, reason} ->
          {_status, code} = error_details(reason)
          %{type: "error", error: code}
      end

    case chunk(conn, [Jason.encode_to_iodata!(line), "\n"]) do
      {:ok, conn} -> conn
      {:error, _reason} -> conn
    end
  end

  defp finish_transcript(conn, turn_id, result), do: render_transcript(conn, turn_id, result)

  defp render_transcript(conn, turn_id, {:ok, result}) do
    case result do
      :duplicate ->
        conn
        |> put_status(:ok)
        |> json(%{turn_id: turn_id, status: "duplicate"})

      %{reply_text: reply_text, turn_id: ^turn_id, generation_id: generation_id} = reply ->
        conn
        |> put_status(:created)
        |> json(%{
          turn_id: turn_id,
          status: "committed",
          generation_id: generation_id,
          reply_text: reply_text,
          speaker: reply |> Map.get(:speaker, :patient) |> to_string()
        })

      # A refused reply kept the learner turn (#269): no text to speak.
      {:kept, %{turn_id: ^turn_id, generation_id: generation_id} = kept} ->
        conn
        |> put_status(:created)
        |> json(%{
          turn_id: turn_id,
          status: "kept",
          generation_id: generation_id,
          addressee: kept_addressee(kept)
        })
    end
  end

  defp render_transcript(conn, _turn_id, {:error, reason}), do: send_error(conn, reason)

  # Who the kept turn was addressed to (#274): `examiner` (acknowledged, never
  # sent to the patient) or `patient` (the patient reply was refused).
  defp kept_addressee(%{addressee: :examiner}), do: "examiner"
  defp kept_addressee(_kept), do: "patient"

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
  defp error_details(_other), do: {503, "station_ai_unavailable"}
end
