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
end
