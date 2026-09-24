defmodule BackendWeb.TTSControllerTest do
  use BackendWeb.ConnCase, async: false

  alias Backend.Stations

  @text "Bom dia, o que o senhor está sentindo?"
  @audio "fake-mp3-bytes"

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

  defp stub_audio(stub) do
    stub_openai(stub, fn conn -> Plug.Conn.send_resp(conn, 200, @audio) end)
  end

  defp post_text(conn, session_id, params) do
    post(conn, ~p"/api/stations/active/sessions/#{session_id}/synthesize", params)
  end

  test "returns the audio blob on success", %{conn: conn} do
    stub_audio(OkVoiceStub)
    session = Stations.create_session(audio_consent: true)

    conn = post_text(conn, session.session_id, %{"text" => @text})

    assert response(conn, 200) == @audio
    assert ["audio/mpeg"] = get_resp_header(conn, "content-type")
  end

  test "forwards the requested voice to OpenAI", %{conn: conn} do
    test_pid = self()

    stub_openai(EchoVoiceStub, fn c ->
      {:ok, body, c} = Plug.Conn.read_body(c)
      send(test_pid, {:voice, Jason.decode!(body)["voice"]})
      Plug.Conn.send_resp(c, 200, @audio)
    end)

    session = Stations.create_session(audio_consent: true)
    conn = post_text(conn, session.session_id, %{"text" => @text, "voice" => "echo"})

    assert response(conn, 200) == @audio
    assert_receive {:voice, "echo"}
  end

  test "returns 502 when OpenAI fails", %{conn: conn} do
    stub_openai(BoomVoiceStub, fn c -> Plug.Conn.send_resp(c, 503, "down") end)
    session = Stations.create_session(audio_consent: true)

    conn = post_text(conn, session.session_id, %{"text" => @text})

    assert %{"error" => "openai_unavailable", "message" => message} = json_response(conn, 502)
    assert is_binary(message)
  end

  test "returns 410 for an expired session", %{conn: conn} do
    stub_audio(ExpiredVoiceStub)
    Application.put_env(:backend, :conversation_timeout_ms, 0)
    on_exit(fn -> Application.delete_env(:backend, :conversation_timeout_ms) end)

    session = Stations.create_session(audio_consent: true)
    conn = post_text(conn, session.session_id, %{"text" => @text})

    assert %{"error" => "expired"} = json_response(conn, 410)
  end

  test "returns 404 for an unknown session", %{conn: conn} do
    stub_audio(MissingVoiceStub)

    conn = post_text(conn, "nope", %{"text" => @text})

    assert %{"error" => "not_found"} = json_response(conn, 404)
  end

  test "returns 400 when the text is missing or invalid", %{conn: conn} do
    stub_audio(NoTextStub)
    session = Stations.create_session(audio_consent: true)

    assert %{"error" => "invalid_text"} =
             conn |> post_text(session.session_id, %{}) |> json_response(400)

    assert %{"error" => "invalid_text"} =
             conn |> post_text(session.session_id, %{"text" => "  "}) |> json_response(400)

    assert %{"error" => "invalid_text"} =
             conn
             |> post_text(session.session_id, %{"text" => @text, "voice" => "bogus"})
             |> json_response(400)
  end

  test "returns 403 when the session has no audio consent", %{conn: conn} do
    stub_audio(NoConsentVoiceStub)
    session = Stations.create_session(audio_consent: false)

    conn = post_text(conn, session.session_id, %{"text" => @text})

    assert %{"error" => "no_consent"} = json_response(conn, 403)
  end
end
