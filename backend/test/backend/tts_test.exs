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

  test "synthesize keeps the OpenAI path when the voice provider is :openai" do
    Application.put_env(:backend, :voice_provider, :openai)
    Application.put_env(:backend, :cartesia_api_key, "car-test-secret-key")
    Application.put_env(:backend, :cartesia_voice_id, "voice-123")

    on_exit(fn ->
      Application.delete_env(:backend, :voice_provider)
      Application.delete_env(:backend, :cartesia_api_key)
      Application.delete_env(:backend, :cartesia_voice_id)
    end)

    session = consented_session()
    test_pid = self()

    Req.Test.stub(OpenAIPathStub, fn conn ->
      send(test_pid, {:path, conn.request_path})
      Plug.Conn.send_resp(conn, 200, @audio)
    end)

    assert {:ok, %{format: "mp3"}} =
             TTS.synthesize(session.session_id, @text, nil, plug: {Req.Test, OpenAIPathStub})

    assert_receive {:path, "/v1/audio/speech"}
  end

  describe "stage directions" do
    defp inspect_input(stub) do
      test_pid = self()

      Req.Test.stub(stub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        send(test_pid, {:spoken, decoded["input"] || decoded["transcript"]})
        Plug.Conn.send_resp(conn, 200, @audio)
      end)

      [plug: {Req.Test, stub}]
    end

    defp refuse_calls(stub) do
      test_pid = self()

      Req.Test.stub(stub, fn conn ->
        send(test_pid, :provider_called)
        Plug.Conn.send_resp(conn, 200, @audio)
      end)

      [plug: {Req.Test, stub}]
    end

    test "a leading *(…)* action is not sent to the provider" do
      session = consented_session()

      assert {:ok, _} =
               TTS.synthesize(
                 session.session_id,
                 "*(curvado, com a mão na barriga)* Vim por causa de uma dor na barriga.",
                 "alloy",
                 inspect_input(StageLeadingStub)
               )

      assert_receive {:spoken, "Vim por causa de uma dor na barriga."}
    end

    test "*…* spans anywhere and a leading or closing parenthesized action are removed" do
      session = consented_session()
      opts = inspect_input(StageSpansStub)

      assert {:ok, _} =
               TTS.synthesize(
                 session.session_id,
                 "Dói aqui *(aponta para o lado direito)*, doutor. *suspira*",
                 "alloy",
                 opts
               )

      assert_receive {:spoken, "Dói aqui, doutor."}

      assert {:ok, _} =
               TTS.synthesize(
                 session.session_id,
                 "(evitando mexer o tronco) Começou ontem. (geme baixinho)",
                 "alloy",
                 opts
               )

      assert_receive {:spoken, "Começou ontem."}
    end

    test "text without stage directions is unchanged, including in-sentence parentheses" do
      session = consented_session()
      opts = inspect_input(StagePlainStub)

      for text <- [
            @text,
            "Tomei dipirona (500 mg) ontem à noite.",
            "Começou há dois dias (talvez três) e piorou.",
            "Tomo um remédio para pressão (losartana)"
          ] do
        assert {:ok, _} = TTS.synthesize(session.session_id, text, "alloy", opts)
        assert_receive {:spoken, ^text}
      end
    end

    test "a reply made only of a stage direction makes no provider call" do
      session = consented_session()
      opts = refuse_calls(StageOnlyStub)

      for text <- ["*(curvado, com a mão na barriga)*", "(fica em silêncio)", " *suspira* "] do
        assert {:error, :invalid_text} = TTS.synthesize(session.session_id, text, "alloy", opts)
      end

      refute_received :provider_called
    end

    test "Cartesia receives the text without stage directions" do
      Application.put_env(:backend, :voice_provider, :deepgram_cartesia)
      Application.put_env(:backend, :cartesia_api_key, "car-test-secret-key")
      Application.put_env(:backend, :cartesia_voice_id, "voice-123")

      on_exit(fn ->
        Application.delete_env(:backend, :voice_provider)
        Application.delete_env(:backend, :cartesia_api_key)
        Application.delete_env(:backend, :cartesia_voice_id)
      end)

      session = consented_session()

      assert {:ok, _} =
               TTS.synthesize(
                 session.session_id,
                 "*(curvado, com a mão na barriga)* Vim por causa de uma dor na barriga.",
                 nil,
                 inspect_input(StageCartesiaStub)
               )

      assert_receive {:spoken, "Vim por causa de uma dor na barriga."}

      assert {:error, :invalid_text} =
               TTS.synthesize(
                 session.session_id,
                 "*(evitando mexer o tronco)*",
                 nil,
                 refuse_calls(StageCartesiaOnlyStub)
               )

      refute_received :provider_called
    end
  end

  describe "with the Cartesia voice provider" do
    setup do
      Application.put_env(:backend, :voice_provider, :deepgram_cartesia)
      Application.put_env(:backend, :cartesia_api_key, "car-test-secret-key")
      Application.put_env(:backend, :cartesia_voice_id, "voice-123")

      on_exit(fn ->
        Application.delete_env(:backend, :voice_provider)
        Application.delete_env(:backend, :cartesia_api_key)
        Application.delete_env(:backend, :cartesia_voice_id)
        Application.delete_env(:backend, :cartesia_model)
      end)

      :ok
    end

    test "posts the text to the configured voice and asks for mp3" do
      session = consented_session()
      test_pid = self()

      Req.Test.stub(CartesiaInspectStub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        send(
          test_pid,
          {:req, conn.method, conn.request_path, Plug.Conn.get_req_header(conn, "authorization"),
           Plug.Conn.get_req_header(conn, "cartesia-version"), body}
        )

        conn
        |> Plug.Conn.put_resp_content_type("audio/mpeg")
        |> Plug.Conn.send_resp(200, @audio)
      end)

      assert {:ok, result} =
               TTS.synthesize(session.session_id, @text, nil,
                 plug: {Req.Test, CartesiaInspectStub}
               )

      assert result.audio_binary == @audio
      assert result.format == "mp3"
      assert %DateTime{} = result.synthesized_at

      assert_receive {:req, "POST", "/tts/bytes", auth, version, body}
      assert auth == ["Bearer car-test-secret-key"]
      assert version == ["2026-08-14"]

      assert Jason.decode!(body) == %{
               "model_id" => "sonic-3",
               "transcript" => @text,
               "voice" => %{"mode" => "id", "id" => "voice-123"},
               "language" => "pt",
               "output_format" => %{
                 "container" => "mp3",
                 "sample_rate" => 44_100,
                 "bit_rate" => 128_000
               }
             }
    end

    test "uses the configured model and the configured voice for any accepted voice name" do
      Application.put_env(:backend, :cartesia_model, "sonic-3.6")
      session = consented_session()
      test_pid = self()

      Req.Test.stub(CartesiaModelStub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        send(test_pid, {:req, conn.request_path, decoded["model_id"], decoded["voice"]["id"]})
        Plug.Conn.send_resp(conn, 200, @audio)
      end)

      assert {:ok, _} =
               TTS.synthesize(session.session_id, @text, "nova",
                 plug: {Req.Test, CartesiaModelStub}
               )

      assert_receive {:req, "/tts/bytes", "sonic-3.6", "voice-123"}
    end

    test "maps an HTTP error to :openai_unavailable" do
      session = consented_session()

      Req.Test.stub(CartesiaErrorStub, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"detail" => "invalid_api_key"})
      end)

      assert {:error, :openai_unavailable} =
               TTS.synthesize(session.session_id, @text, nil, plug: {Req.Test, CartesiaErrorStub})
    end

    test "maps a timeout and an empty body to :openai_unavailable" do
      session = consented_session()
      Req.Test.stub(CartesiaTimeoutStub, fn conn -> Req.Test.transport_error(conn, :timeout) end)
      Req.Test.stub(CartesiaEmptyStub, fn conn -> Plug.Conn.send_resp(conn, 200, "") end)

      assert {:error, :openai_unavailable} =
               TTS.synthesize(session.session_id, @text, nil,
                 plug: {Req.Test, CartesiaTimeoutStub}
               )

      assert {:error, :openai_unavailable} =
               TTS.synthesize(session.session_id, @text, nil, plug: {Req.Test, CartesiaEmptyStub})
    end

    test "is unavailable without a Cartesia key or voice id, even with an OpenAI key" do
      session = consented_session()
      opts = stub_audio(CartesiaUnusedStub)

      Application.delete_env(:backend, :cartesia_voice_id)
      assert {:error, :openai_unavailable} = TTS.synthesize(session.session_id, @text, nil, opts)

      Application.put_env(:backend, :cartesia_voice_id, "voice-123")
      Application.delete_env(:backend, :cartesia_api_key)
      assert {:error, :openai_unavailable} = TTS.synthesize(session.session_id, @text, nil, opts)
    end

    test "keeps the text limits" do
      session = consented_session()
      opts = stub_audio(CartesiaUnusedStub2)

      assert {:error, :invalid_text} = TTS.synthesize(session.session_id, "  ", nil, opts)

      assert {:error, :invalid_text} =
               TTS.synthesize(session.session_id, String.duplicate("a", 4097), nil, opts)
    end
  end
end
