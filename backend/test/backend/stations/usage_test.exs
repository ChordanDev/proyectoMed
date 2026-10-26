defmodule Backend.Stations.UsageTest do
  # async: false: the counters live in one named ETS table shared by the app.
  use ExUnit.Case, async: false

  alias Backend.Stations.JevDecision.TypesafeAdapter
  alias Backend.Stations.StationAI.AnthropicClient
  alias Backend.Stations.Usage

  defp session_id, do: "usage-test-" <> Integer.to_string(System.unique_integer([:positive]))

  defp claude_config(stub, model \\ "claude-haiku-5-5") do
    AnthropicClient.config(api_key: "sk-ant-test", model: model, plug: {Req.Test, stub})
  end

  defp claude_request do
    %{
      system: "Stable rules.",
      messages: [%{"role" => "user", "content" => "Q."}],
      max_tokens: 16
    }
  end

  defp claude_stub(name, usage) do
    Req.Test.stub(name, fn conn ->
      Req.Test.json(conn, %{
        "stop_reason" => "end_turn",
        "content" => [%{"type" => "text", "text" => "ok"}],
        "usage" => usage
      })
    end)
  end

  defp sse_stub(name, events) do
    body =
      Enum.map_join(events, fn data ->
        "event: #{data["type"]}\ndata: #{Jason.encode!(data)}\n\n"
      end)

    Req.Test.stub(name, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.send_resp(200, body)
    end)
  end

  @usage %{
    "input_tokens" => 10,
    "output_tokens" => 5,
    "cache_read_input_tokens" => 600,
    "cache_creation_input_tokens" => 20
  }

  describe "Claude usage (issue #342)" do
    test "a non-streamed request adds its four token counts to the tracked session, per model" do
      id = session_id()
      claude_stub(UsageCreateStub, @usage)

      Usage.track(id, fn ->
        assert {:ok, "ok"} =
                 AnthropicClient.create_message(claude_config(UsageCreateStub), claude_request())

        assert {:ok, "ok"} =
                 AnthropicClient.create_message(claude_config(UsageCreateStub), claude_request())

        assert {:ok, "ok"} =
                 AnthropicClient.create_message(
                   claude_config(UsageCreateStub, "claude-opus-5-5"),
                   claude_request()
                 )
      end)

      assert Usage.snapshot(id).claude == %{
               "claude-haiku-5-5" => %{
                 input_tokens: 20,
                 output_tokens: 10,
                 cache_read_input_tokens: 1200,
                 cache_creation_input_tokens: 40
               },
               "claude-opus-5-5" => %{
                 input_tokens: 10,
                 output_tokens: 5,
                 cache_read_input_tokens: 600,
                 cache_creation_input_tokens: 20
               }
             }
    end

    test "a streamed request counts message_start input and message_delta output tokens" do
      id = session_id()

      sse_stub(UsageStreamStub, [
        %{
          "type" => "message_start",
          "message" => %{
            "usage" => %{
              "input_tokens" => 7,
              "cache_read_input_tokens" => 600,
              "cache_creation_input_tokens" => 3,
              "output_tokens" => 1
            }
          }
        },
        %{
          "type" => "content_block_delta",
          "index" => 0,
          "delta" => %{"type" => "text_delta", "text" => "Dói."}
        },
        %{
          "type" => "message_delta",
          "delta" => %{"stop_reason" => "end_turn"},
          "usage" => %{"output_tokens" => 42}
        },
        %{"type" => "message_stop"}
      ])

      Usage.track(id, fn ->
        assert {:ok, "Dói."} =
                 AnthropicClient.stream_message(
                   claude_config(UsageStreamStub),
                   claude_request(),
                   fn _ -> :ok end
                 )
      end)

      assert Usage.snapshot(id).claude == %{
               "claude-haiku-5-5" => %{
                 input_tokens: 7,
                 output_tokens: 42,
                 cache_read_input_tokens: 600,
                 cache_creation_input_tokens: 3
               }
             }
    end

    test "a call made in a Task.async child is attributed to the caller's session" do
      id = session_id()
      claude_stub(UsageTaskStub, @usage)

      Usage.track(id, fn ->
        [fn -> AnthropicClient.create_message(claude_config(UsageTaskStub), claude_request()) end]
        |> Enum.map(&Task.async/1)
        |> Enum.each(&Task.await/1)
      end)

      assert %{"claude-haiku-5-5" => %{input_tokens: 10}} = Usage.snapshot(id).claude
    end

    test "a non-2xx response records nothing, and an untracked call records nothing" do
      id = session_id()

      Req.Test.stub(UsageErrorStub, fn conn ->
        conn |> Plug.Conn.put_status(529) |> Req.Test.json(%{"usage" => @usage})
      end)

      Usage.track(id, fn ->
        assert {:error, :upstream_error} =
                 AnthropicClient.create_message(claude_config(UsageErrorStub), claude_request())
      end)

      claude_stub(UsageUntrackedStub, @usage)

      assert {:ok, "ok"} =
               AnthropicClient.create_message(claude_config(UsageUntrackedStub), claude_request())

      assert Usage.snapshot(id) == Usage.snapshot("never-tracked")
      assert Usage.snapshot(id).claude == %{}
    end

    test "track/2 restores the previous attribution and returns the function's result" do
      id = session_id()
      assert Usage.current_session() == nil
      assert :result == Usage.track(id, fn -> Usage.current_session() == id && :result end)
      assert Usage.current_session() == nil
    end
  end

  describe "Jev usage (issue #342)" do
    test "every TypeSafe request that gets an HTTP response is one Jev call of the session" do
      id = session_id()

      Req.Test.stub(UsageJevStub, fn conn ->
        conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{})
      end)

      request = %{
        candidate_text: "A dor começou ontem.",
        package_id: "station-1",
        package_version: "2.0.0",
        package: %{
          "station_id" => "station-1",
          "version" => "2.0.0",
          "patient_profile" => %{"persona" => "Maria"},
          "revealable_facts" => [],
          "response_rules" => [],
          "language" => "pt-BR"
        },
        conversation: [%{seq: 1, role: :student, text: "Quando começou?", trust: :untrusted}],
        latest_learner_turn: %{seq: 1, role: :student, text: "Quando começou?", trust: :untrusted},
        deadline_ms: 3_000,
        deadline_at_monotonic_ms: System.monotonic_time(:millisecond) + 3_000
      }

      Usage.track(id, fn ->
        TypesafeAdapter.decide_patient(request, api_key: "ts-key", plug: {Req.Test, UsageJevStub})
      end)

      assert Usage.snapshot(id).jev_calls >= 1
    end
  end

  describe "forget/1" do
    test "drops a session's counters" do
      id = session_id()
      claude_stub(UsageForgetStub, @usage)

      Usage.track(id, fn ->
        AnthropicClient.create_message(claude_config(UsageForgetStub), claude_request())
      end)

      refute Usage.snapshot(id).claude == %{}
      :ok = Usage.forget(id)
      assert Usage.snapshot(id).claude == %{}
    end
  end
end
