defmodule Backend.TranscriptionTest do
  use ExUnit.Case, async: false

  alias Backend.Conversation
  alias Backend.Transcription

  @audio "fake-audio-bytes"

  setup do
    Application.put_env(:backend, :openai_api_key, "sk-test-secret-key")
    on_exit(fn -> Application.delete_env(:backend, :openai_api_key) end)
    :ok
  end

  defp consented_session do
    Conversation.start(audio_consent: true)
  end

  defp stub_ok(stub, body) do
    Req.Test.stub(stub, fn conn -> Req.Test.json(conn, body) end)
    [plug: {Req.Test, stub}]
  end

  test "transcribe returns text, duration and timestamp on success" do
    session = consented_session()
    opts = stub_ok(OkStub, %{"text" => "Doutor, dói o peito.", "duration" => 3.5})

    assert {:ok, result} = Transcription.transcribe(session.session_id, @audio, "m4a", opts)
    assert result.text == "Doutor, dói o peito."
    assert result.duration_seconds == 3.5
    assert %DateTime{} = result.transcribed_at
  end

  test "transcribe sends a multipart request to the audio transcriptions endpoint" do
    session = consented_session()
    test_pid = self()

    Req.Test.stub(InspectStub, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(
        test_pid,
        {:req, conn.request_path, Plug.Conn.get_req_header(conn, "authorization"), body}
      )

      Req.Test.json(conn, %{"text" => "ok", "duration" => 1.0})
    end)

    assert {:ok, _} =
             Transcription.transcribe(session.session_id, @audio, "wav",
               plug: {Req.Test, InspectStub}
             )

    assert_receive {:req, path, auth, body}
    assert path == "/v1/audio/transcriptions"
    assert auth == ["Bearer sk-test-secret-key"]
    assert body =~ "audio.wav"
    assert body =~ @audio
    refute body =~ "sk-test-secret-key"
  end

  test "transcribe returns :no_consent when the session never granted audio consent" do
    session = Conversation.start()

    assert {:error, :no_consent} = Transcription.transcribe(session.session_id, @audio, "m4a")
  end

  test "transcribe returns :not_found for an unknown session" do
    assert {:error, :not_found} = Transcription.transcribe("nope", @audio, "m4a")
  end

  test "transcribe returns :expired for an expired session" do
    Application.put_env(:backend, :conversation_timeout_ms, 0)
    on_exit(fn -> Application.delete_env(:backend, :conversation_timeout_ms) end)

    session = consented_session()

    assert {:error, :expired} = Transcription.transcribe(session.session_id, @audio, "m4a")
  end

  test "transcribe rejects empty audio and unsupported formats" do
    session = consented_session()

    assert {:error, :invalid_audio} = Transcription.transcribe(session.session_id, "", "m4a")
    assert {:error, :invalid_audio} = Transcription.transcribe(session.session_id, @audio, "mp3")
  end

  test "transcribe returns :openai_unavailable on a 5xx response" do
    session = consented_session()

    Req.Test.stub(BoomStub, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

    assert {:error, :openai_unavailable} =
             Transcription.transcribe(session.session_id, @audio, "m4a",
               plug: {Req.Test, BoomStub}
             )
  end

  test "transcribe returns :openai_unavailable on a transport failure" do
    session = consented_session()

    Req.Test.stub(DownStub, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

    assert {:error, :openai_unavailable} =
             Transcription.transcribe(session.session_id, @audio, "m4a",
               plug: {Req.Test, DownStub}
             )
  end

  test "transcribe returns :openai_unavailable when credentials are missing" do
    Application.delete_env(:backend, :openai_api_key)
    session = consented_session()

    assert {:error, :openai_unavailable} =
             Transcription.transcribe(session.session_id, @audio, "m4a", api_key: nil)
  end
end
