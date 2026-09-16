defmodule BackendWeb.StationController do
  use BackendWeb, :controller

  alias Backend.Conversation
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
         {:ok, %{text: reply_text}} <- StationAI.next_reply(package, context) do
      {:ok, _} =
        Conversation.append_message(session_id, %{
          role: :patient,
          modality: :text,
          text: reply_text
        })

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
