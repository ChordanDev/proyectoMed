defmodule BackendWeb.StationController do
  use BackendWeb, :controller

  alias Backend.Stations

  def active(conn, _params) do
    json(conn, Stations.get_active_station())
  end

  def create_session(conn, params) do
    audio_consent =
      case params do
        %{"audio_consent" => val} -> val
        %{audio_consent: val} -> val
        _ -> nil
      end

    if is_boolean(audio_consent) do
      session = Stations.create_session(%{audio_consent: audio_consent})

      json(conn, %{
        session_id: session.session_id,
        station_id: session.station_id,
        station_version: session.station_version,
        audio_consent: session.audio_consent,
        started_at: DateTime.to_iso8601(session.started_at),
        expires_at: DateTime.to_iso8601(session.expires_at),
        server_now: DateTime.to_iso8601(DateTime.utc_now())
      })
    else
      conn
      |> put_status(:bad_request)
      |> json(%{
        error: "invalid_parameters",
        message: "Parâmetros inválidos: 'audio_consent' é obrigatório e deve ser um booleano."
      })
    end
  end

  def create_message(conn, %{"id" => session_id} = params) do
    role = params["role"]
    modality = params["modality"]
    text = params["text"]

    with :ok <- validate_message_params(role, modality, text),
         parsed_modality = parse_modality(modality),
         {:ok, reply} <-
           Stations.create_message(session_id, %{
             role: :learner,
             modality: parsed_modality,
             text: text
           }) do
      json(conn, %{
        reply_text: reply.reply_text,
        reply_audio_url: reply.reply_audio_url,
        server_now: DateTime.to_iso8601(DateTime.utc_now())
      })
    else
      {:error, :invalid_message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "invalid_message",
          message:
            "Mensagem inválida: 'role' deve ser 'learner', 'modality' deve ser 'voice' ou 'text', e 'text' não pode ser vazio."
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          error: "session_not_found",
          message: "Sessão não encontrada."
        })

      {:error, :expired} ->
        conn
        |> put_status(:gone)
        |> json(%{
          error: "session_expired",
          message: "A sessão expirou."
        })

      {:error, :completed} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "session_completed",
          message: "A sessão já foi concluída."
        })

      {:error, :timeout} ->
        conn
        |> put_status(:gateway_timeout)
        |> json(%{
          error: "timeout",
          message: "A verificação da resposta do paciente excedeu o tempo limite."
        })

      {:error, {tag, _detail}} when tag in [:denied, :refused] ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{
          error: "reply_verification_failed",
          message: "A verificação de segurança da resposta do paciente falhou."
        })

      {:error, tag} when tag in [:denied, :refused] ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{
          error: "reply_verification_failed",
          message: "A verificação de segurança da resposta do paciente falhou."
        })

      {:error, {:adapter_disabled, _detail}} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{
          error: "station_ai_unavailable",
          message: "O serviço da estação de IA está temporariamente indisponível."
        })

      {:error, :station_ai_unavailable} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{
          error: "station_ai_unavailable",
          message: "O serviço da estação de IA está temporariamente indisponível."
        })

      {:error, _reason} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{
          error: "station_ai_unavailable",
          message: "O serviço da estação de IA está temporariamente indisponível."
        })
    end
  end

  def finish_session(conn, %{"id" => session_id} = params) do
    reason_param =
      case params do
        %{"reason" => val} -> val
        %{reason: val} -> val
        _ -> "user"
      end

    with {:ok, reason_atom} <- parse_finish_reason(reason_param),
         {:ok, session} <- Stations.complete_session(session_id, reason_atom) do
      json(conn, %{
        session_id: session.session_id,
        status: "completed",
        completed_at: DateTime.to_iso8601(session.completed_at)
      })
    else
      {:error, :invalid_reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "invalid_reason",
          message: "Motivo de finalização inválido: deve ser 'user' ou 'timer'."
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          error: "session_not_found",
          message: "Sessão não encontrada."
        })

      {:error, :expired} ->
        conn
        |> put_status(:gone)
        |> json(%{
          error: "session_expired",
          message: "A sessão expirou."
        })
    end
  end

  def show_result(conn, %{"id" => session_id}) do
    case Stations.get_session_result(session_id) do
      {:ok, result} ->
        json(conn, result)

      {:error, :session_not_finished} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "session_not_finished",
          message: "A sessão ainda não foi finalizada."
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          error: "session_not_found",
          message: "Sessão não encontrada."
        })

      {:error, :expired} ->
        conn
        |> put_status(:gone)
        |> json(%{
          error: "session_expired",
          message: "A sessão expirou."
        })
    end
  end

  defp parse_finish_reason("user"), do: {:ok, :user}
  defp parse_finish_reason("timer"), do: {:ok, :timer}
  defp parse_finish_reason(_), do: {:error, :invalid_reason}

  defp validate_message_params(role, modality, text) do
    if role == "learner" and modality in ["voice", "text"] and is_binary(text) and
         byte_size(String.trim(text)) > 0 do
      :ok
    else
      {:error, :invalid_message}
    end
  end

  defp parse_modality("voice"), do: :voice
  defp parse_modality("text"), do: :text
end
