defmodule BackendWeb.StationController do
  use BackendWeb, :controller

  alias Backend.Conversation
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
end
