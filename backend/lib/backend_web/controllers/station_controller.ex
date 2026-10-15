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
        deadline_at: DateTime.to_iso8601(session.deadline_at),
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

      {:error, :message_too_long} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "message_too_long",
          message: "Mensagem muito longa: o limite é de 2.000 caracteres."
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

      {:error, {:refused, _reason, _learner_turn}} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{
          error: "reply_verification_failed",
          message: "A verificação de segurança da resposta do paciente falhou."
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

      {:error, :station_time_elapsed} ->
        conn
        |> put_status(:conflict)
        |> json(%{
          error: "station_time_elapsed",
          message: "O tempo da estação se esgotou."
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
        completed_at: DateTime.to_iso8601(session.completed_at),
        completion_reason: to_string(session.completion_reason),
        deadline_at: DateTime.to_iso8601(session.deadline_at),
        server_now: DateTime.to_iso8601(DateTime.utc_now())
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

      {:error, :deadline_not_reached} ->
        conn
        |> put_status(:conflict)
        |> json(%{
          error: "deadline_not_reached",
          message: "O prazo da estação ainda não foi atingido."
        })
    end
  end

  def discard(conn, %{"id" => session_id}) do
    :ok = Stations.discard_session(session_id)
    send_resp(conn, :no_content, "")
  end

  def show_session(conn, %{"id" => session_id}) do
    case Stations.get_session(session_id) do
      {:ok, session} ->
        json(conn, %{
          session_id: session.session_id,
          station_id: session.station_id,
          station_version: session.station_version,
          audio_consent: session.audio_consent,
          started_at: DateTime.to_iso8601(session.started_at),
          expires_at: DateTime.to_iso8601(session.expires_at),
          deadline_at: DateTime.to_iso8601(session.deadline_at),
          status: to_string(session.status),
          completion_reason:
            session |> Map.get(:completion_reason) |> completion_reason_to_string(),
          messages: Enum.map(session.messages, &message_to_json/1),
          server_now: DateTime.to_iso8601(DateTime.utc_now())
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

  def show_educational_result(conn, %{"id" => session_id}) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case Stations.get_educational_result(session_id) do
      {:ok, result} ->
        json(conn, result)

      {:error, :session_not_finished} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "session_not_finished", message: "A sessão ainda não foi finalizada."})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "session_not_found", message: "Sessão não encontrada."})

      {:error, :expired} ->
        conn
        |> put_status(:gone)
        |> json(%{error: "session_expired", message: "A sessão expirou."})

      {:error, {:invalid_attempt, _reason}} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{
          error: "invalid_attempt",
          message:
            "Não foi possível avaliar esta tentativa. Nenhuma estimativa foi gerada. Reinicie a estação."
        })
    end
  end

  def request_impresso(conn, %{"id" => session_id} = params) do
    request_params = %{"text" => params["text"], "request_id" => params["request_id"]}

    case Stations.request_impresso(session_id, request_params) do
      {:ok, result} ->
        json(conn, %{
          request_id: result.request_id,
          decision: result.decision,
          released_impressos: result.released_impressos,
          newly_released: result.newly_released,
          feedback_message: result.feedback_message
        })

      {:error, :invalid_request} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "invalid_request",
          message: "Requisição inválida: 'text' é obrigatório e não pode ser vazio."
        })

      {:error, :message_too_long} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "message_too_long",
          message: "Mensagem muito longa: o limite é de 2.000 caracteres."
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
        |> put_status(:conflict)
        |> json(%{
          error: "session_completed",
          message: "A sessão já foi concluída."
        })
    end
  end

  def list_impressos(conn, %{"id" => session_id}) do
    case Stations.list_impressos(session_id) do
      {:ok, result} ->
        json(conn, %{released_impressos: result.released_impressos})

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

  defp completion_reason_to_string(nil), do: nil
  defp completion_reason_to_string(reason), do: to_string(reason)

  defp message_to_json(msg) do
    %{
      role: to_string(msg.role),
      modality: to_string(msg.modality),
      text: msg.text,
      at: DateTime.to_iso8601(msg.at)
    }
  end
end
