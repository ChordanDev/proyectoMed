defmodule Backend.TTSTest do
  use ExUnit.Case, async: false

  alias Backend.Conversation
  alias Backend.TTS

  @text "Bom dia, o que o senhor está sentindo?"
  @audio "fake-mp3-bytes"

  setup do
    Application.put_env(:backend, :openai_api_key, "sk-test-secret-key")
    on_exit(fn -> Application.delete_env(:backend, :openai_api_key) end)
    :ok
  end

  defp consented_session do
    Conversation.start(audio_consent: true)
  end

  defp stub_audio(stub, binary \\ @audio) do
    Req.Test.stub(stub, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("audio/mpeg")
      |> Plug.Conn.send_resp(200, binary)
    end)

    [plug: {Req.Test, stub}]
  end

  test "synthesize returns the audio binary, format and timestamp on success" do
    session = consented_session()

    assert {:ok, result} = TTS.synthesize(session.session_id, @text, "alloy", stub_audio(OkStub))
    assert result.audio_binary == @audio
    assert result.format == "mp3"
    assert %DateTime{} = result.synthesized_at
  end

  test "synthesize posts the text, voice and model to the speech endpoint" do
    session = consented_session()
    test_pid = self()

    Req.Test.stub(InspectStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(
        test_pid,
        {:req, conn.request_path, Plug.Conn.get_req_header(conn, "authorization"), body}
      )

      Plug.Conn.send_resp(conn, 200, @audio)
    end)

    assert {:ok, _} =
             TTS.synthesize(session.session_id, @text, "nova", plug: {Req.Test, InspectStub})

    assert_receive {:req, path, auth, body}
    assert path == "/v1/audio/speech"
    assert auth == ["Bearer sk-test-secret-key"]

    assert %{"input" => @text, "voice" => "nova", "response_format" => "mp3"} =
             Jason.decode!(body)
  end

  test "synthesize falls back to the configured default voice" do
    session = consented_session()
    Application.put_env(:backend, :openai_tts_voice, "shimmer")
    on_exit(fn -> Application.delete_env(:backend, :openai_tts_voice) end)
    test_pid = self()

    Req.Test.stub(VoiceStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:voice, Jason.decode!(body)["voice"]})
      Plug.Conn.send_resp(conn, 200, @audio)
    end)

    assert {:ok, _} = TTS.synthesize(session.session_id, @text, nil, plug: {Req.Test, VoiceStub})
    assert_receive {:voice, "shimmer"}
  end

  test "synthesize returns :openai_unavailable on a 5xx" do
    session = consented_session()
    Req.Test.stub(BoomStub, fn conn -> Plug.Conn.send_resp(conn, 503, "down") end)

    assert {:error, :openai_unavailable} =
             TTS.synthesize(session.session_id, @text, "alloy", plug: {Req.Test, BoomStub})
  end

  test "synthesize returns :openai_unavailable on a transport failure" do
    session = consented_session()
    Req.Test.stub(DeadStub, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

    assert {:error, :openai_unavailable} =
             TTS.synthesize(session.session_id, @text, "alloy",
               plug: {Req.Test, DeadStub},
               retry: false
             )
  end

  test "synthesize returns :openai_unavailable when the api key is missing" do
    Application.delete_env(:backend, :openai_api_key)
    session = consented_session()

    assert {:error, :openai_unavailable} =
             TTS.synthesize(session.session_id, @text, "alloy", stub_audio(UnusedStub))
  end

  test "synthesize returns :not_found for an unknown session" do
    assert {:error, :not_found} =
             TTS.synthesize("nope", @text, "alloy", stub_audio(UnusedStub2))
  end

  test "synthesize returns :expired for an expired session" do
    Application.put_env(:backend, :conversation_timeout_ms, 0)
    on_exit(fn -> Application.delete_env(:backend, :conversation_timeout_ms) end)

    session = consented_session()

    assert {:error, :expired} =
             TTS.synthesize(session.session_id, @text, "alloy", stub_audio(UnusedStub3))
  end

  test "synthesize returns :no_consent when the session has no audio consent" do
    session = Conversation.start(audio_consent: false)

    assert {:error, :no_consent} =
             TTS.synthesize(session.session_id, @text, "alloy", stub_audio(UnusedStub4))
  end

  test "synthesize rejects empty, oversized and non-binary text" do
    session = consented_session()
    opts = stub_audio(UnusedStub5)

    assert {:error, :invalid_text} = TTS.synthesize(session.session_id, "", "alloy", opts)
    assert {:error, :invalid_text} = TTS.synthesize(session.session_id, "   ", "alloy", opts)
    assert {:error, :invalid_text} = TTS.synthesize(session.session_id, nil, "alloy", opts)

    assert {:error, :invalid_text} =
             TTS.synthesize(session.session_id, String.duplicate("a", 4097), "alloy", opts)
  end

  test "synthesize rejects an unsupported voice" do
    session = consented_session()

    assert {:error, :invalid_text} =
             TTS.synthesize(session.session_id, @text, "morgan-freeman", stub_audio(UnusedStub6))
  end

  test "allowed_voices lists the six OpenAI voices" do
    assert TTS.allowed_voices() == ~w(alloy echo fable onyx nova shimmer)
  end
end
