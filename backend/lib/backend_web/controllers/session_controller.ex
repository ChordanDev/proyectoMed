defmodule BackendWeb.SessionController do
  @moduledoc """
  Starts a session on a published station (issue #334, ADR-013 amendment on
  #209): `POST /sessions` with `station_id` (the catalog id, the case number)
  or `random: true` and an optional `area`, plus the boolean `audio_consent`.
  Every later operation is addressed by the session under `/sessions/:id`.
  The session belongs to the learner of the device access token (#337), who
  needs an active subscription: without one it answers `402
  subscription_required` (#339). Past the plan's daily quota it answers `429
  daily_quota_exhausted` with `resets_at` and a `Retry-After` header (#340).
  A node draining for a deploy answers `503 draining` with a `Retry-After`
  header (#344).
  """

  use BackendWeb, :controller

  alias Backend.Stations

  # A draining node (#344) is replaced within minutes by `fly deploy`; the new
  # machine takes new sessions.
  @drain_retry_after_seconds 30

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

      {:error, :draining} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(@drain_retry_after_seconds))
        |> error(
          :service_unavailable,
          "draining",
          "O simulador está sendo atualizado. Tente iniciar a estação novamente em instantes."
        )

      {:error, :subscription_required} ->
        error(
          conn,
          :payment_required,
          "subscription_required",
          "Assine um plano para usar o simulador."
        )

      {:error, {:daily_quota_exhausted, resets_at}} ->
        retry_after = max(DateTime.diff(resets_at, DateTime.utc_now(), :second), 1)

        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> put_status(:too_many_requests)
        |> json(%{
          error: "daily_quota_exhausted",
          message:
            "Você usou todas as simulações de hoje. A cota renova à meia-noite (horário de Brasília).",
          daily_quota: Backend.Billing.daily_quota(conn.assigns.current_scope.user.id),
          resets_at: DateTime.to_iso8601(resets_at)
        })

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

  @doc """
  `POST /sessions/:id/exam-mode` (#364): the learner pressed the exam button
  and will say the request aloud. The next utterance goes to the impresso
  request instead of the patient. `200` with `status: "armed"`, `expires_at`
  and `server_now`.
  """
  def arm_exam_mode(conn, %{"id" => session_id}) do
    case Stations.arm_exam_mode(session_id) do
      {:ok, %{expires_at: expires_at}} ->
        json(conn, %{
          status: "armed",
          expires_at: DateTime.to_iso8601(expires_at),
          server_now: DateTime.to_iso8601(DateTime.utc_now())
        })

      {:error, reason} ->
        session_error(conn, reason)
    end
  end

  @doc "`DELETE /sessions/:id/exam-mode` (#364): disarms it. `200` with `status: \"disarmed\"`."
  def cancel_exam_mode(conn, %{"id" => session_id}) do
    case Stations.cancel_exam_mode(session_id) do
      :ok -> json(conn, %{status: "disarmed"})
      {:error, reason} -> session_error(conn, reason)
    end
  end

  defp session_error(conn, :not_found),
    do: error(conn, :not_found, "session_not_found", "Sessão não encontrada.")

  defp session_error(conn, :expired),
    do: error(conn, :gone, "session_expired", "A sessão expirou.")

  defp session_error(conn, :completed),
    do: error(conn, :conflict, "session_completed", "A sessão já foi concluída.")

  defp session_error(conn, :no_consent),
    do:
      error(
        conn,
        :forbidden,
        "no_consent",
        "A solicitação falada exige o consentimento de áudio."
      )

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
