defmodule BackendWeb.TranscriptionControllerTest do
  use BackendWeb.ConnCase, async: false

  alias Backend.Stations

  @audio "fake-audio-bytes"

  setup do
    Application.put_env(:backend, :openai_api_key, "sk-test-secret-key")

    on_exit(fn ->
      Application.delete_env(:backend, :openai_api_key)
      Application.delete_env(:backend, :openai_req_options)
    end)

    :ok
  end

  defp stub_openai(stub, fun) do
    Req.Test.stub(stub, fun)
    Application.put_env(:backend, :openai_req_options, plug: {Req.Test, stub})
  end

  defp upload(binary, filename \\ "clip.m4a", content_type \\ "audio/m4a") do
    path = Path.join(System.tmp_dir!(), "#{System.unique_integer([:positive])}-#{filename}")
    File.write!(path, binary)
    on_exit(fn -> File.rm_rf(path) end)
    %Plug.Upload{path: path, filename: filename, content_type: content_type}
  end

  defp post_audio(conn, session_id, params) do
    post(conn, ~p"/api/stations/active/sessions/#{session_id}/transcribe", params)
  end

  test "returns the transcription payload on success", %{conn: conn} do
    stub_openai(OkStub, fn c ->
      Req.Test.json(c, %{"text" => "Dói o peito.", "duration" => 2.0})
    end)

    session = Stations.create_session(audio_consent: true)
    conn = post_audio(conn, session.session_id, %{"audio" => upload(@audio)})

    assert %{"text" => "Dói o peito.", "duration_seconds" => 2.0, "transcribed_at" => at} =
             json_response(conn, 200)

    assert {:ok, _, _} = DateTime.from_iso8601(at)
  end

  test "returns 502 when OpenAI fails", %{conn: conn} do
    stub_openai(BoomStub, fn c -> Plug.Conn.send_resp(c, 503, "down") end)

    session = Stations.create_session(audio_consent: true)
    conn = post_audio(conn, session.session_id, %{"audio" => upload(@audio)})

    assert %{"error" => "openai_unavailable", "message" => message} = json_response(conn, 502)
    assert is_binary(message)
  end

  test "returns 410 for an expired session", %{conn: conn} do
    Application.put_env(:backend, :conversation_timeout_ms, 0)
    on_exit(fn -> Application.delete_env(:backend, :conversation_timeout_ms) end)

    session = Stations.create_session(audio_consent: true)
    conn = post_audio(conn, session.session_id, %{"audio" => upload(@audio)})

    assert %{"error" => "expired"} = json_response(conn, 410)
  end

  test "returns 404 for an unknown session", %{conn: conn} do
    conn = post_audio(conn, "unknown-session", %{"audio" => upload(@audio)})

    assert %{"error" => "not_found"} = json_response(conn, 404)
  end

  test "returns 403 when the session has no audio consent", %{conn: conn} do
    session = Stations.create_session(audio_consent: false)
    conn = post_audio(conn, session.session_id, %{"audio" => upload(@audio)})

    assert %{"error" => "no_consent"} = json_response(conn, 403)
  end

  test "returns 400 when the audio part is missing", %{conn: conn} do
    session = Stations.create_session(audio_consent: true)
    conn = post_audio(conn, session.session_id, %{})

    assert %{"error" => "invalid_audio"} = json_response(conn, 400)
  end

  test "returns 400 for an unsupported audio format", %{conn: conn} do
    session = Stations.create_session(audio_consent: true)

    conn =
      post_audio(conn, session.session_id, %{
        "audio" => upload(@audio, "clip.mp3", "audio/mpeg")
      })

    assert %{"error" => "invalid_audio"} = json_response(conn, 400)
  end

  test "returns 413 for audio over the 10 MB limit", %{conn: conn} do
    session = Stations.create_session(audio_consent: true)
    oversized = :binary.copy("a", 10 * 1024 * 1024 + 1)

    conn = post_audio(conn, session.session_id, %{"audio" => upload(oversized)})

    assert %{"error" => "audio_too_large"} = json_response(conn, 413)
  end
end
