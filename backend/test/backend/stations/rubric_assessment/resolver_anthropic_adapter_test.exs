defmodule Backend.Stations.RubricAssessment.Resolver.AnthropicAdapterTest do
  use ExUnit.Case, async: false

  alias Backend.Stations.RubricAssessment.Resolver.AnthropicAdapter
  alias Backend.Stations.RubricAssessment.Resolver.OpenAIAdapter

  @request %{
    criteria: [
      %{
        id: "history-taking",
        description: "Investigates the history items.",
        actions: [
          %{id: "ask-onset", description: "Ask about onset.", classification: "performed"},
          %{id: "ask-intensity", description: "Ask about intensity.", classification: "uncertain"}
        ],
        decidable_action_ids: ["ask-intensity"]
      }
    ],
    evidence_pool: [%{id: "turn-1", text: "A dor é forte?"}]
  }

  @decision %{
    "criterion_id" => "history-taking",
    "id" => "ask-intensity",
    "classification" => "performed",
    "evidence_ids" => ["turn-1"]
  }

  defp message(text, stop_reason \\ "end_turn") do
    %{
      "type" => "message",
      "role" => "assistant",
      "content" => [%{"type" => "text", "text" => text}],
      "stop_reason" => stop_reason
    }
  end

  defp json_message(term), do: message(Jason.encode!(term))

  defp resolve(name, opts \\ []) do
    AnthropicAdapter.resolve(@request, [api_key: "sk-ant-test", plug: {Req.Test, name}] ++ opts)
  end

  describe "request" do
    test "asks for the decisions with the resolver prompt, a JSON schema and medium effort" do
      test_pid = self()

      Req.Test.stub(ClaudeResolverInspectStub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        send(
          test_pid,
          {:req, conn.request_path, Plug.Conn.get_req_header(conn, "x-api-key"),
           Jason.decode!(body)}
        )

        Req.Test.json(conn, json_message(%{"actions" => [@decision]}))
      end)

      assert {:ok, %{actions: [decision]}} = resolve(ClaudeResolverInspectStub)

      assert decision == %{
               criterion_id: "history-taking",
               id: "ask-intensity",
               classification: "performed",
               evidence_ids: ["turn-1"]
             }

      assert_receive {:req, "/v1/messages", ["sk-ant-test"], payload}
      assert payload["model"] == "claude-opus-5-5"
      # Issue #272: the fixed system prompt is the cached prefix; the
      # per-request user content stays after the breakpoint.
      assert payload["system"] == [
               %{
                 "type" => "text",
                 "text" => OpenAIAdapter.system_prompt(),
                 "cache_control" => %{"type" => "ephemeral"}
               }
             ]

      assert payload["fallbacks"] == "default"

      assert payload["output_config"] == %{
               "effort" => "medium",
               "format" => %{"type" => "json_schema", "schema" => OpenAIAdapter.schema()}
             }

      assert [%{"role" => "user", "content" => user_content}] = payload["messages"]
      assert Jason.decode!(user_content) == OpenAIAdapter.user_content(@request)

      for forbidden <- ["thinking", "temperature", "top_p", "response_format"] do
        refute Map.has_key?(payload, forbidden)
      end
    end

    test "uses the shared model setting, never the patient model (issue #256)" do
      previous = Application.fetch_env(:backend, Backend.Stations.StationAI.AnthropicClient)

      on_exit(fn ->
        case previous do
          {:ok, value} ->
            Application.put_env(:backend, Backend.Stations.StationAI.AnthropicClient, value)

          :error ->
            Application.delete_env(:backend, Backend.Stations.StationAI.AnthropicClient)
        end
      end)

      Application.put_env(:backend, Backend.Stations.StationAI.AnthropicClient,
        model: "claude-opus-5-5",
        patient_model: "claude-sonnet-5-5"
      )

      test_pid = self()

      Req.Test.stub(ClaudeResolverModelStub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, json_message(%{"actions" => [@decision]}))
      end)

      assert {:ok, _} = resolve(ClaudeResolverModelStub)
      assert_receive {:payload, payload}
      assert payload["model"] == "claude-opus-5-5"
      assert payload["output_config"]["effort"] == "medium"
      refute Map.has_key?(payload, "thinking")
    end

    test "the receive timeout follows the resolver deadline" do
      previous = Application.fetch_env(:backend, :rubric_resolver_deadline_ms)

      on_exit(fn ->
        case previous do
          {:ok, value} -> Application.put_env(:backend, :rubric_resolver_deadline_ms, value)
          :error -> Application.delete_env(:backend, :rubric_resolver_deadline_ms)
        end
      end)

      test_pid = self()

      probe = fn request ->
        send(test_pid, {:receive_timeout, request.options[:receive_timeout]})
        {request, Req.Response.new(status: 200, body: json_message(%{"actions" => []}))}
      end

      Application.put_env(:backend, :rubric_resolver_deadline_ms, 8_000)

      assert {:ok, %{actions: []}} =
               AnthropicAdapter.resolve(@request, api_key: "k", req_options: [adapter: probe])

      assert_receive {:receive_timeout, 7_750}

      Application.delete_env(:backend, :rubric_resolver_deadline_ms)

      assert {:ok, _} =
               AnthropicAdapter.resolve(@request, api_key: "k", req_options: [adapter: probe])

      assert_receive {:receive_timeout, 9_750}
    end
  end

  describe "errors" do
    test "a blank key is missing credentials and sends nothing" do
      assert AnthropicAdapter.resolve(@request, api_key: " ") == {:error, :missing_credentials}
    end

    test "a refusal is typed, whatever text came with it" do
      Req.Test.stub(ClaudeResolverRefusalStub, fn conn ->
        Req.Test.json(conn, message(Jason.encode!(%{"actions" => [@decision]}), "refusal"))
      end)

      assert resolve(ClaudeResolverRefusalStub) == {:error, :refused}
    end

    test "invalid JSON, a schema mismatch or a truncated answer is malformed" do
      replies = [
        message("not json"),
        json_message(%{"decisions" => []}),
        json_message(%{"actions" => [Map.delete(@decision, "evidence_ids")]}),
        json_message(%{"actions" => [Map.put(@decision, "classification", "maybe")]}),
        json_message(%{"actions" => [Map.put(@decision, "confidence", 0.9)]}),
        message(Jason.encode!(%{"actions" => [@decision]}), "max_tokens"),
        %{"type" => "message", "content" => []}
      ]

      for reply <- replies do
        Req.Test.stub(ClaudeResolverMalformedStub, fn conn -> Req.Test.json(conn, reply) end)
        assert resolve(ClaudeResolverMalformedStub) == {:error, :malformed_response}
      end
    end

    test "an HTTP error is an upstream error" do
      Req.Test.stub(ClaudeResolverUpstreamStub, fn conn ->
        conn |> Plug.Conn.put_status(529) |> Req.Test.json(%{"type" => "error"})
      end)

      assert resolve(ClaudeResolverUpstreamStub) == {:error, :upstream_error}
    end

    test "a transport timeout is a timeout" do
      Req.Test.stub(ClaudeResolverTimeoutStub, &Req.Test.transport_error(&1, :timeout))
      assert resolve(ClaudeResolverTimeoutStub) == {:error, :timeout}
    end

    test "a connection failure is a network error" do
      Req.Test.stub(ClaudeResolverNetworkStub, &Req.Test.transport_error(&1, :econnrefused))
      assert resolve(ClaudeResolverNetworkStub) == {:error, :network_error}
    end
  end
end
