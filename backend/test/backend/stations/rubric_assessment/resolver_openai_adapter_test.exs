defmodule Backend.Stations.RubricAssessment.Resolver.OpenAIAdapterTest do
  use ExUnit.Case, async: false

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

  defp completion(message), do: %{"choices" => [%{"message" => message}]}

  defp content(term), do: completion(%{"role" => "assistant", "content" => Jason.encode!(term)})

  defp stub(name, fun), do: Req.Test.stub(name, fun)

  defp resolve(name, opts \\ []) do
    OpenAIAdapter.resolve(@request, [api_key: "sk-test", plug: {Req.Test, name}] ++ opts)
  end

  describe "request" do
    test "sends the request as JSON with the system prompt and a strict schema" do
      test_pid = self()

      stub(ResolverInspectStub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        send(
          test_pid,
          {:req, conn.request_path, Plug.Conn.get_req_header(conn, "authorization"),
           Jason.decode!(body)}
        )

        Req.Test.json(conn, content(%{"actions" => [@decision]}))
      end)

      assert {:ok, %{actions: [decision]}} = resolve(ResolverInspectStub)

      assert decision == %{
               criterion_id: "history-taking",
               id: "ask-intensity",
               classification: "performed",
               evidence_ids: ["turn-1"]
             }

      assert_receive {:req, "/v1/chat/completions", ["Bearer sk-test"], payload}
      assert payload["model"] == "gpt-4o-mini"

      assert [system, user] = payload["messages"]
      assert system == %{"role" => "system", "content" => OpenAIAdapter.system_prompt()}
      assert Jason.decode!(user["content"]) == Jason.decode!(Jason.encode!(@request))

      assert payload["response_format"] == %{
               "type" => "json_schema",
               "json_schema" => %{
                 "name" => "rubric_action_decisions",
                 "strict" => true,
                 "schema" => OpenAIAdapter.schema()
               }
             }
    end

    test "uses the resolver model before the station OpenAI model" do
      test_pid = self()

      stub(ResolverModelStub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:model, Jason.decode!(body)["model"]})
        Req.Test.json(conn, content(%{"actions" => []}))
      end)

      previous_station = Application.get_env(:backend, Backend.StationAI.OpenAIAdapter)
      previous_own = Application.get_env(:backend, OpenAIAdapter)

      on_exit(fn ->
        restore(Backend.StationAI.OpenAIAdapter, previous_station)
        restore(OpenAIAdapter, previous_own)
      end)

      Application.put_env(:backend, Backend.StationAI.OpenAIAdapter, model: "station-model")
      assert {:ok, %{actions: []}} = resolve(ResolverModelStub)
      assert_receive {:model, "station-model"}

      Application.put_env(:backend, OpenAIAdapter, model: "resolver-model")
      assert {:ok, %{actions: []}} = resolve(ResolverModelStub)
      assert_receive {:model, "resolver-model"}
    end
  end

  describe "errors" do
    test "a blank key is missing credentials and sends nothing" do
      assert OpenAIAdapter.resolve(@request, api_key: " ") == {:error, :missing_credentials}
    end

    test "a refusal is typed" do
      stub(ResolverRefusalStub, fn conn ->
        Req.Test.json(
          conn,
          completion(%{"role" => "assistant", "content" => nil, "refusal" => "I can't."})
        )
      end)

      assert resolve(ResolverRefusalStub) == {:error, :refused}
    end

    test "invalid JSON, a schema mismatch or a missing message is malformed" do
      replies = [
        completion(%{"role" => "assistant", "content" => "not json"}),
        content(%{"decisions" => []}),
        content(%{"actions" => [Map.delete(@decision, "evidence_ids")]}),
        content(%{"actions" => [Map.put(@decision, "classification", "maybe")]}),
        content(%{"actions" => [Map.put(@decision, "evidence_ids", [1])]}),
        content(%{"actions" => [Map.put(@decision, "confidence", 0.9)]}),
        %{"choices" => []}
      ]

      for reply <- replies do
        stub(ResolverMalformedStub, fn conn -> Req.Test.json(conn, reply) end)
        assert resolve(ResolverMalformedStub) == {:error, :malformed_response}
      end
    end

    test "a 500 is an upstream error" do
      stub(ResolverUpstreamStub, fn conn ->
        conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"error" => "boom"})
      end)

      assert resolve(ResolverUpstreamStub) == {:error, :upstream_error}
    end

    test "a transport timeout is a timeout" do
      stub(ResolverTimeoutStub, fn conn -> Req.Test.transport_error(conn, :timeout) end)

      assert resolve(ResolverTimeoutStub) == {:error, :timeout}
    end

    test "a connection failure is a network error" do
      stub(ResolverNetworkStub, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert resolve(ResolverNetworkStub) == {:error, :network_error}
    end
  end

  defp restore(key, nil), do: Application.delete_env(:backend, key)
  defp restore(key, value), do: Application.put_env(:backend, key, value)
end
