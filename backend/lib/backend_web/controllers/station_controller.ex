defmodule BackendWeb.StationController do
  use BackendWeb, :controller

  alias Backend.Conversation
  alias Backend.Evaluator
  alias Backend.StationAI
  alias Backend.StationLoader

  def active(conn, _params) do
    package = StationLoader.active_package()

    json(conn, Map.take(package, ["station_id", "version", "language", "display_title"]))
  end

  def create_session(conn, params) do
    audio_consent =
      case params do
        %{"audio_consent" => val} -> val
        %{audio_consent: val} -> val
        _ -> nil
      end

    if is_boolean(audio_consent) do
      package = StationLoader.active_package()

      session =
        Conversation.start(%{
          station_id: package["station_id"],
          station_version: package["version"],
          audio_consent: audio_consent
        })

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
         {:ok, _session} <-
           Conversation.append_message(session_id, %{
             role: :learner,
             modality: parsed_modality,
             text: text
           }),
         package = StationLoader.active_package(),
         {:ok, current_session} <- Conversation.fetch(session_id),
         context = format_context(current_session, package),
         {:ok, %{text: reply_text}} <- StationAI.next_reply(package, context),
         {:ok, _session} <- append_patient_reply(session_id, reply_text) do
      json(conn, %{
        reply_text: reply_text,
        reply_audio_url: nil,
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
         {:ok, session} <- Conversation.complete(session_id, reason_atom) do
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
    case Conversation.fetch(session_id) do
      {:ok, %{status: :completed} = session} ->
        render_completed_result(conn, session)

      {:ok, %{status: :active}} ->
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

  defp render_completed_result(conn, session) do
    package = StationLoader.active_package()
    evaluation = Evaluator.evaluate(package, session)

    criteria =
      Enum.map(evaluation.criteria, fn criterion ->
        %{
          id: criterion.id,
          status: to_string(criterion.status),
          evidence: serialize_evidence(criterion.evidence),
          recommendation: criterion.recommendation
        }
      end)

    json(conn, %{
      session_id: session.session_id,
      status: "completed",
      criteria: criteria
    })
  end

  defp parse_finish_reason("user"), do: {:ok, :user}
  defp parse_finish_reason("timer"), do: {:ok, :timer}
  defp parse_finish_reason(_), do: {:error, :invalid_reason}

  defp serialize_evidence(evidence) when is_list(evidence) do
    Enum.map(evidence, fn
      %{text: text} -> text
      %{"text" => text} -> text
      text when is_binary(text) -> text
      other -> to_string(other)
    end)
  end

  defp serialize_evidence(_), do: []

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

  defp append_patient_reply(session_id, reply_text) do
    case Conversation.append_message(session_id, %{
           role: :patient,
           modality: :text,
           text: reply_text
         }) do
      {:ok, session} -> {:ok, session}
      {:error, :completed} -> {:ok, :completed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp format_context(session, package) do
    conversation =
      Enum.map(session.messages, fn msg ->
        role =
          case msg.role do
            :learner -> :student
            "learner" -> :student
            :student -> :student
            "student" -> :student
            :patient -> :patient
            "patient" -> :patient
            _ -> :student
          end

        %{role: role, text: msg.text}
      end)

    %{
      conversation: conversation,
      language: package["language"] || "pt-BR"
    }
  end
end
