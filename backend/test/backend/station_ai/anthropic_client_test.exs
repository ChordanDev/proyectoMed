defmodule Backend.Stations.StationAI.AnthropicClientTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Backend.Stations.StationAI.AnthropicClient

  @cache_control %{"type" => "ephemeral"}

  defp config(opts \\ []) do
    AnthropicClient.config(Keyword.merge([api_key: "sk-ant-test-secret"], opts))
  end

  describe "body/2 prompt caching (issue #272)" do
    test "renders the stable system prompt as one cached block, before the messages" do
      body =
        AnthropicClient.body(config(), %{
          system: "Stable rules.",
          messages: [%{"role" => "user", "content" => "Per-turn question."}],
          max_tokens: 16
        })

      assert body["system"] == [
               %{"type" => "text", "text" => "Stable rules.", "cache_control" => @cache_control}
             ]

      assert body["messages"] == [%{"role" => "user", "content" => "Per-turn question."}]
      refute Map.has_key?(body, "cache_control")
    end

    test "puts a per-turn system suffix after the breakpoint, without a marker" do
      body =
        AnthropicClient.body(config(), %{
          system: "Stable rules.",
          system_suffix: "Per-turn note.",
          messages: [%{"role" => "user", "content" => "Hi."}],
          max_tokens: 16
        })

      assert body["system"] == [
               %{"type" => "text", "text" => "Stable rules.", "cache_control" => @cache_control},
               %{"type" => "text", "text" => "Per-turn note."}
             ]
    end

    test "drops a blank suffix so the system stays one cached block" do
      body =
        AnthropicClient.body(config(), %{
          system: "Stable rules.",
          system_suffix: "",
          messages: [%{"role" => "user", "content" => "Hi."}],
          max_tokens: 16
        })

      assert [%{"cache_control" => @cache_control}] = body["system"]
    end
  end

  describe "Claude Haiku 5.5 (issue #290)" do
    defp haiku_request do
      %{
        system: "Stable rules.",
        messages: [%{"role" => "user", "content" => "Q."}],
        max_tokens: 16
      }
    end

    test "the adjudicator model key defaults to Claude Haiku 5.5" do
      config = AnthropicClient.config([api_key: "k"], model_key: :adjudicator_model)
      assert config.model == "claude-haiku-5-5"
    end

    test "sends no server-side fallback and turns thinking off at the lowest setting" do
      config =
        AnthropicClient.config([api_key: "k", model: "claude-haiku-5-5"],
          effort: "low",
          thinking: :lowest
        )

      body = AnthropicClient.body(config, haiku_request())

      refute Map.has_key?(body, "fallbacks")
      assert body["thinking"] == %{"type" => "disabled"}
      assert body["output_config"] == %{"effort" => "low"}
    end

    test "sends no fallback beta header" do
      test_pid = self()

      Req.Test.stub(HaikuHeaderStub, fn conn ->
        send(test_pid, {:beta, Plug.Conn.get_req_header(conn, "anthropic-beta")})

        Req.Test.json(conn, %{
          "content" => [%{"type" => "text", "text" => "ok"}],
          "stop_reason" => "end_turn"
        })
      end)

      config =
        AnthropicClient.config(
          [api_key: "k", model: "claude-haiku-5-5", plug: {Req.Test, HaikuHeaderStub}],
          []
        )

      assert {:ok, "ok"} = AnthropicClient.create_message(config, haiku_request())
      assert_received {:beta, []}
    end
  end

  describe "create_message/2 usage log (issue #272)" do
    setup do
      previous = Logger.level()
      Logger.configure(level: :debug)
      on_exit(fn -> Logger.configure(level: previous) end)
    end

    test "logs cache usage and latency at debug level, without content" do
      Req.Test.stub(ClientUsageStub, fn conn ->
        Req.Test.json(conn, %{
          "content" => [%{"type" => "text", "text" => "SECRET-OUTPUT"}],
          "stop_reason" => "end_turn",
          "usage" => %{
            "input_tokens" => 12,
            "cache_read_input_tokens" => 900,
            "cache_creation_input_tokens" => 0,
            "output_tokens" => 5
          }
        })
      end)

      log =
        capture_log([level: :debug], fn ->
          assert {:ok, "SECRET-OUTPUT"} =
                   AnthropicClient.create_message(config(plug: {Req.Test, ClientUsageStub}), %{
                     system: "SECRET-PROMPT",
                     messages: [%{"role" => "user", "content" => "SECRET-QUESTION"}],
                     max_tokens: 16
                   })
        end)

      assert log =~ "[debug]"
      assert log =~ "cache_read_input_tokens=900"
      assert log =~ "cache_creation_input_tokens=0"
      assert log =~ "input_tokens=12"
      assert log =~ ~r/latency_ms=\d+/
      refute log =~ "SECRET"
      refute log =~ "sk-ant-test-secret"
    end

    test "logs zero cache tokens when the response has no usage" do
      Req.Test.stub(ClientNoUsageStub, fn conn ->
        Req.Test.json(conn, %{
          "content" => [%{"type" => "text", "text" => "ok"}],
          "stop_reason" => "end_turn"
        })
      end)

      log =
        capture_log([level: :debug], fn ->
          assert {:ok, "ok"} =
                   AnthropicClient.create_message(config(plug: {Req.Test, ClientNoUsageStub}), %{
                     system: "s",
                     messages: [%{"role" => "user", "content" => "q"}],
                     max_tokens: 16
                   })
        end)

      assert log =~ "cache_read_input_tokens=0"
      assert log =~ "cache_creation_input_tokens=0"
    end
  end

  describe "stream_message/3 (issue #271)" do
    defp sse(events) do
      Enum.map_join(events, fn {event, data} ->
        "event: #{event}\ndata: #{Jason.encode!(data)}\n\n"
      end)
    end

    defp text_events(texts, stop_reason) do
      [
        {"message_start",
         %{
           "type" => "message_start",
           "message" => %{"usage" => %{"input_tokens" => 7, "cache_read_input_tokens" => 600}}
         }},
        {"content_block_start",
         %{
           "type" => "content_block_start",
           "index" => 0,
           "content_block" => %{"type" => "text", "text" => ""}
         }},
        {"ping", %{"type" => "ping"}}
      ] ++
        Enum.map(texts, fn text ->
          {"content_block_delta",
           %{
             "type" => "content_block_delta",
             "index" => 0,
             "delta" => %{"type" => "text_delta", "text" => text}
           }}
        end) ++
        [
          {"content_block_stop", %{"type" => "content_block_stop", "index" => 0}},
          {"message_delta",
           %{"type" => "message_delta", "delta" => %{"stop_reason" => stop_reason}}},
          {"message_stop", %{"type" => "message_stop"}}
        ]
    end

    # Sends the SSE body in small chunks that cut events in half, as a network would.
    defp stream_stub(name, body, status \\ 200) do
      test_pid = self()

      Req.Test.stub(name, fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:request_body, Jason.decode!(raw)})

        conn =
          conn
          |> Plug.Conn.put_resp_content_type("text/event-stream")
          |> Plug.Conn.send_chunked(status)

        body
        |> String.codepoints()
        |> Enum.chunk_every(17)
        |> Enum.reduce(conn, fn piece, conn ->
          {:ok, conn} = Plug.Conn.chunk(conn, Enum.join(piece))
          conn
        end)
      end)
    end

    defp request do
      %{
        system: "Stable rules.",
        system_suffix: "Per-turn note.",
        messages: [%{"role" => "user", "content" => "Quando começou?"}],
        max_tokens: 64
      }
    end

    test "hands each text delta over in order and returns the whole text" do
      stream_stub(StreamOkStub, sse(text_events(["Começou ", "ontem. ", "Dói."], "end_turn")))
      test_pid = self()

      assert {:ok, "Começou ontem. Dói."} =
               AnthropicClient.stream_message(
                 config(plug: {Req.Test, StreamOkStub}),
                 request(),
                 &send(test_pid, {:delta, &1})
               )

      assert_received {:delta, "Começou "}
      assert_received {:delta, "ontem. "}
      assert_received {:delta, "Dói."}
    end

    test "sends stream: true with the cached system prefix and the patient thinking" do
      stream_stub(StreamBodyStub, sse(text_events(["Ok."], "end_turn")))

      config =
        AnthropicClient.config([api_key: "k", plug: {Req.Test, StreamBodyStub}],
          model_key: :patient_model,
          effort: "low",
          thinking: :lowest
        )

      assert {:ok, "Ok."} = AnthropicClient.stream_message(config, request(), fn _ -> :ok end)
      assert_received {:request_body, body}

      assert body["stream"] == true
      # Issue #308: the patient model defaults to Haiku 5.5.
      assert body["model"] == "claude-haiku-5-5"
      assert body["thinking"] == %{"type" => "disabled"}
      assert body["output_config"] == %{"effort" => "low"}
      refute Map.has_key?(body, "fallbacks")

      assert body["system"] == [
               %{"type" => "text", "text" => "Stable rules.", "cache_control" => @cache_control},
               %{"type" => "text", "text" => "Per-turn note."}
             ]
    end

    test "a refusal stop is an error after the deltas already handed over" do
      stream_stub(StreamRefusalStub, sse(text_events(["Começou. "], "refusal")))

      assert {:error, :refused} =
               AnthropicClient.stream_message(
                 config(plug: {Req.Test, StreamRefusalStub}),
                 request(),
                 fn _ -> :ok end
               )
    end

    test "any other stop is malformed" do
      stream_stub(StreamMaxTokensStub, sse(text_events(["Começou"], "max_tokens")))

      assert {:error, :malformed_response} =
               AnthropicClient.stream_message(
                 config(plug: {Req.Test, StreamMaxTokensStub}),
                 request(),
                 fn _ -> :ok end
               )
    end

    test "an error event is an upstream error" do
      body =
        sse([
          {"error",
           %{"type" => "error", "error" => %{"type" => "overloaded_error", "message" => "x"}}}
        ])

      stream_stub(StreamErrorEventStub, body)

      assert {:error, :upstream_error} =
               AnthropicClient.stream_message(
                 config(plug: {Req.Test, StreamErrorEventStub}),
                 request(),
                 fn _ -> :ok end
               )
    end

    test "a non-2xx response hands nothing over" do
      stream_stub(StreamStatusStub, ~s({"type":"error","error":{"message":"bad"}}), 529)
      test_pid = self()

      assert {:error, :upstream_error} =
               AnthropicClient.stream_message(
                 config(plug: {Req.Test, StreamStatusStub}),
                 request(),
                 &send(test_pid, {:delta, &1})
               )

      refute_received {:delta, _}
    end

    test "missing credentials never send a request" do
      assert {:error, :missing_credentials} =
               AnthropicClient.stream_message(
                 AnthropicClient.config(api_key: ""),
                 request(),
                 fn _ -> :ok end
               )
    end

    test "logs usage and latency without content" do
      stream_stub(StreamLogStub, sse(text_events(["SECRET-OUTPUT."], "end_turn")))
      previous = Logger.level()
      Logger.configure(level: :debug)
      on_exit(fn -> Logger.configure(level: previous) end)

      log =
        capture_log([level: :debug], fn ->
          assert {:ok, _} =
                   AnthropicClient.stream_message(
                     config(plug: {Req.Test, StreamLogStub}),
                     request(),
                     fn _ -> :ok end
                   )
        end)

      assert log =~ "cache_read_input_tokens=600"
      assert log =~ ~r/latency_ms=\d+/
      refute log =~ "SECRET"
    end
  end
end
