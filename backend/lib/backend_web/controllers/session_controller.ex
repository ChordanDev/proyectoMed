defmodule BackendWeb.SessionController do
  @moduledoc """
  Starts a session on a published station (issue #334, ADR-013 amendment on
  #209): `POST /sessions` with `station_id` (the catalog id, the case number)
  or `random: true` and an optional `area`, plus the boolean `audio_consent`.
  Every later operation is addressed by the session under `/sessions/:id`.
  The session belongs to the learner of the device access token (#337), who
  needs an active subscription: without one it answers `402
  subscription_required` (#339).
  """

  use BackendWeb, :controller

  alias Backend.Stations

  # The largest value of the bigint `cases.number` column.
  @max_case_number 9_223_372_036_854_775_807

  @doc """
  The Pre-Station Notice with every active provider (ADR-003 #36), shown
  before the learner gives or declines audio consent.
  """
  def notice(conn, _params) do
    json(conn, Stations.pre_station_notice())
  end

  def create(conn, params) do
    with {:ok, selection} <- selection(params),
         {:ok, audio_consent} <- audio_consent(params),
         {:ok, session} <-
           Stations.start_station_session(selection, %{
             audio_consent: audio_consent,
             user_id: conn.assigns.current_scope.user.id
           }) do
      conn
      |> put_status(:created)
      |> json(session_json(session))
    else
      {:error, :invalid_parameters} ->
        error(
          conn,
          :bad_request,
          "invalid_parameters",
          "Parâmetros inválidos: informe 'station_id' (número da estação) ou 'random': true " <>
            "com 'area' opcional, e 'audio_consent' booleano."
        )

      {:error, :subscription_required} ->
        error(
          conn,
          :payment_required,
          "subscription_required",
          "Assine um plano para usar o simulador."
        )

      {:error, :station_not_found} ->
        error(conn, :not_found, "station_not_found", "Estação não encontrada.")

      {:error, :no_published_station} ->
        error(
          conn,
          :not_found,
          "no_published_station",
          "Nenhuma estação publicada para esta área."
        )

      {:error, :invalid_station_package} ->
        error(
          conn,
          :service_unavailable,
          "station_unavailable",
          "A estação está temporariamente indisponível."
        )
    end
  end

  defp selection(%{"station_id" => _id, "random" => _random}), do: {:error, :invalid_parameters}

  defp selection(%{"station_id" => id}) when is_integer(id) and id > 0, do: station(id)

  defp selection(%{"station_id" => id}) when is_binary(id) do
    case Integer.parse(id) do
      {number, ""} when number > 0 -> station(number)
      _other -> {:error, :invalid_parameters}
    end
  end

  defp selection(%{"random" => true} = params) do
    case Map.get(params, "area") do
      nil -> {:ok, {:random, nil}}
      area when is_binary(area) -> {:ok, {:random, blank_to_nil(String.trim(area))}}
      _other -> {:error, :invalid_parameters}
    end
  end

  defp selection(_params), do: {:error, :invalid_parameters}

  # Case numbers are a bigint column: a number beyond its range names no case,
  # so it is station_not_found rather than a query the database cannot encode.
  defp station(number) when number <= @max_case_number, do: {:ok, {:station, number}}
  defp station(_number), do: {:error, :station_not_found}

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(area), do: area

  defp audio_consent(%{"audio_consent" => consent}) when is_boolean(consent), do: {:ok, consent}
  defp audio_consent(_params), do: {:error, :invalid_parameters}

  defp session_json(session) do
    %{
      session_id: session.session_id,
      station_id: session.station_id,
      station_version: session.station_version,
      station: Stations.session_station(session),
      audio_consent: session.audio_consent,
      status: to_string(session.status),
      voice_mode: Application.get_env(:backend, :voice_mode, "turn"),
      started_at: DateTime.to_iso8601(session.started_at),
      expires_at: DateTime.to_iso8601(session.expires_at),
      deadline_at: DateTime.to_iso8601(session.deadline_at),
      server_now: DateTime.to_iso8601(DateTime.utc_now())
    }
  end

  defp error(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{error: code, message: message})
  end
end
