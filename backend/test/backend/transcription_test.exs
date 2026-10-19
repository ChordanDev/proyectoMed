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

  test "transcribe keeps the OpenAI path when the voice provider is :openai" do
    Application.put_env(:backend, :voice_provider, :openai)
    Application.put_env(:backend, :deepgram_api_key, "dg-test-secret-key")

    on_exit(fn ->
      Application.delete_env(:backend, :voice_provider)
      Application.delete_env(:backend, :deepgram_api_key)
    end)

    session = consented_session()
    test_pid = self()

    Req.Test.stub(OpenAIPathStub, fn conn ->
      send(test_pid, {:path, conn.request_path})
      Req.Test.json(conn, %{"text" => "ok", "duration" => 1.0})
    end)

    assert {:ok, %{text: "ok"}} =
             Transcription.transcribe(session.session_id, @audio, "webm",
               plug: {Req.Test, OpenAIPathStub}
             )

    assert_receive {:path, "/v1/audio/transcriptions"}
  end

  describe "with the Deepgram voice provider" do
    setup do
      Application.put_env(:backend, :voice_provider, :deepgram_elevenlabs)
      Application.put_env(:backend, :deepgram_api_key, "dg-test-secret-key")

      on_exit(fn ->
        Application.delete_env(:backend, :voice_provider)
        Application.delete_env(:backend, :deepgram_api_key)
        Application.delete_env(:backend, :deepgram_model)
      end)

      :ok
    end

    defp deepgram_body(transcript, duration \\ 2.5) do
      %{
        "metadata" => %{"duration" => duration},
        "results" => %{
          "channels" => [
            %{"alternatives" => [%{"transcript" => transcript, "confidence" => 0.98}]}
          ]
        }
      }
    end

    test "sends the raw audio to the pre-recorded listen endpoint in pt-BR" do
      session = consented_session()
      test_pid = self()

      Req.Test.stub(DeepgramInspectStub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        send(
          test_pid,
          {:req, conn.method, conn.request_path, URI.decode_query(conn.query_string),
           Plug.Conn.get_req_header(conn, "authorization"),
           Plug.Conn.get_req_header(conn, "content-type"), body}
        )

        Req.Test.json(conn, deepgram_body("Doutor, dói a barriga."))
      end)

      assert {:ok, _} =
               Transcription.transcribe(session.session_id, @audio, "webm",
                 plug: {Req.Test, DeepgramInspectStub}
               )

      assert_receive {:req, "POST", "/v1/listen", query, auth, content_type, body}
      assert query["language"] == "pt-BR"
      assert query["model"] == "nova-3"
      assert query["smart_format"] == "true"
      assert auth == ["Token dg-test-secret-key"]
      assert content_type == ["audio/webm"]
      assert body == @audio
    end

    test "uses the configured Deepgram model and the audio content type of each format" do
      Application.put_env(:backend, :deepgram_model, "nova-2")
      session = consented_session()
      test_pid = self()

      Req.Test.stub(DeepgramFormatStub, fn conn ->
        send(
          test_pid,
          {:req, URI.decode_query(conn.query_string)["model"],
           Plug.Conn.get_req_header(conn, "content-type")}
        )

        Req.Test.json(conn, deepgram_body("ok"))
      end)

      for {format, content_type} <- [{"m4a", "audio/mp4"}, {"wav", "audio/wav"}] do
        assert {:ok, _} =
                 Transcription.transcribe(session.session_id, @audio, format,
                   plug: {Req.Test, DeepgramFormatStub}
                 )

        assert_receive {:req, "nova-2", [^content_type]}
      end
    end

    test "maps a transcript to text, duration and timestamp" do
      session = consented_session()
      opts = stub_ok(DeepgramOkStub, deepgram_body("Doutor, dói a barriga.", 3.25))

      assert {:ok, result} = Transcription.transcribe(session.session_id, @audio, "webm", opts)
      assert result.text == "Doutor, dói a barriga."
      assert result.duration_seconds == 3.25
      assert %DateTime{} = result.transcribed_at
    end

    test "maps an empty result to empty text, as the OpenAI path does" do
      session = consented_session()
      opts = stub_ok(DeepgramEmptyStub, deepgram_body(""))

      assert {:ok, %{text: ""}} =
               Transcription.transcribe(session.session_id, @audio, "webm", opts)

      no_channels = %{"metadata" => %{"duration" => 0.4}, "results" => %{"channels" => []}}
      opts = stub_ok(DeepgramNoChannelsStub, no_channels)

      assert {:ok, %{text: ""}} =
               Transcription.transcribe(session.session_id, @audio, "webm", opts)
    end

    test "maps a malformed body to :openai_unavailable" do
      session = consented_session()
      opts = stub_ok(DeepgramMalformedStub, %{"unexpected" => true})

      assert {:error, :openai_unavailable} =
               Transcription.transcribe(session.session_id, @audio, "webm", opts)
    end

    test "maps a timeout to :openai_unavailable" do
      session = consented_session()
      Req.Test.stub(DeepgramTimeoutStub, fn conn -> Req.Test.transport_error(conn, :timeout) end)

      assert {:error, :openai_unavailable} =
               Transcription.transcribe(session.session_id, @audio, "webm",
                 plug: {Req.Test, DeepgramTimeoutStub}
               )
    end

    test "maps an HTTP error to :openai_unavailable" do
      session = consented_session()

      Req.Test.stub(DeepgramErrorStub, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"err_code" => "INVALID_AUTH"})
      end)

      assert {:error, :openai_unavailable} =
               Transcription.transcribe(session.session_id, @audio, "webm",
                 plug: {Req.Test, DeepgramErrorStub}
               )
    end

    test "is unavailable without a Deepgram key, even with an OpenAI key" do
      Application.delete_env(:backend, :deepgram_api_key)
      session = consented_session()
      opts = stub_ok(DeepgramUnusedStub, deepgram_body("never"))

      assert {:error, :openai_unavailable} =
               Transcription.transcribe(session.session_id, @audio, "webm", opts)
    end

    test "keeps the consent check before calling the provider" do
      session = Conversation.start()

      assert {:error, :no_consent} = Transcription.transcribe(session.session_id, @audio, "webm")
    end
  end
end
