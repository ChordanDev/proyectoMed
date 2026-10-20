defmodule BackendWeb.VoiceSessionControllerTest do
  use BackendWeb.ConnCase, async: false

  alias Backend.Stations

  setup do
    Application.put_env(:backend, :livekit_url, "wss://revalida.livekit.cloud")
    Application.put_env(:backend, :livekit_api_key, "test-api-key")
    Application.put_env(:backend, :livekit_api_secret, "test-api-secret")

    on_exit(fn ->
      Application.delete_env(:backend, :livekit_url)
      Application.delete_env(:backend, :livekit_api_key)
      Application.delete_env(:backend, :livekit_api_secret)
      Application.delete_env(:backend, :livekit_rate_limit_max)
      Application.delete_env(:backend, :conversation_timeout_ms)
    end)

    :ok
  end

  defp post_voice(conn, session_id) do
    post(conn, ~p"/api/stations/active/sessions/#{session_id}/voice")
  end

  test "returns 201 with the token payload on success", %{conn: conn} do
    session = Stations.create_session(%{audio_consent: true})

    conn = post_voice(conn, session.session_id)

    assert %{
             "url" => "wss://revalida.livekit.cloud",
             "token" => token,
             "room" => room,
             "identity" => identity,
             "expires_at" => expires_at
           } = json_response(conn, 201)

    assert is_binary(token)
    assert String.split(token, ".") |> length() == 3
    assert room == "station-session-" <> session.session_id
    assert identity == "learner-" <> session.session_id
    assert {:ok, _, _} = DateTime.from_iso8601(expires_at)
  end

  test "returns 404 for an unknown session", %{conn: conn} do
    conn = post_voice(conn, "unknown-id")

    assert %{"error" => "session_not_found"} = json_response(conn, 404)
  end

  test "returns 410 for an expired session", %{conn: conn} do
    Application.put_env(:backend, :conversation_timeout_ms, 0)
    session = Stations.create_session(%{audio_consent: true})

    conn = post_voice(conn, session.session_id)

    assert %{"error" => "session_expired"} = json_response(conn, 410)
  end

  test "returns 422 for a completed session", %{conn: conn} do
    session = Stations.create_session(%{audio_consent: true})
    {:ok, _} = Stations.complete_session(session.session_id, :user)

    conn = post_voice(conn, session.session_id)

    assert %{"error" => "session_completed"} = json_response(conn, 422)
  end

  test "returns 403 without audio consent", %{conn: conn} do
    session = Stations.create_session(%{audio_consent: false})

    conn = post_voice(conn, session.session_id)

    assert %{"error" => "no_consent"} = json_response(conn, 403)
  end

  test "returns 429 after the rate limit is exceeded", %{conn: conn} do
    Application.put_env(:backend, :livekit_rate_limit_max, 1)
    session = Stations.create_session(%{audio_consent: true})

    conn1 = post_voice(conn, session.session_id)
    assert json_response(conn1, 201)

    conn2 = post_voice(conn, session.session_id)
    assert %{"error" => "rate_limited"} = json_response(conn2, 429)
  end

  test "returns 503 when LiveKit is not configured", %{conn: conn} do
    Application.delete_env(:backend, :livekit_url)
    session = Stations.create_session(%{audio_consent: true})

    conn = post_voice(conn, session.session_id)

    assert %{"error" => "voice_unavailable"} = json_response(conn, 503)
  end
end
