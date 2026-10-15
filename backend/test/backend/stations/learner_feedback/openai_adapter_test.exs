defmodule Backend.Stations.LearnerFeedback.OpenAIAdapterTest do
  use ExUnit.Case, async: false

  alias Backend.Stations.LearnerFeedback.OpenAIAdapter

  @request %{
    language: "pt-BR",
    criteria: [
      %{
        id: "anamnese",
        description: "Investiga a dor abdominal",
        level: %{label: "parcial", description: "Investiga parte das caracteristicas"},
        next_level: %{label: "completo", description: "Investiga todas as caracteristicas"},
        points: "1.0",
        max_points: "2.0",
        performed_actions: ["Pergunta o inicio da dor"],
        missing_actions: ["Pergunta a irradiacao da dor"],
        evidence: ["Quando comecou a dor?"]
      }
    ]
  }

  defp completion(content) do
    %{"choices" => [%{"message" => %{"role" => "assistant", "content" => content}}]}
  end

  defp stub(name, fun), do: Req.Test.stub(name, fun)

  defp write(name, opts \\ []) do
    OpenAIAdapter.write_feedback(
      @request,
      Keyword.merge([api_key: "sk-test-secret-key", plug: {Req.Test, name}], opts)
    )
  end

  describe "request" do
    test "posts the graded record with model, JSON output and language, never a conversation" do
      test_pid = self()

      stub(FeedbackInspectStub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        send(
          test_pid,
          {:req, conn.method, conn.request_path, Plug.Conn.get_req_header(conn, "authorization"),
           Jason.decode!(body)}
        )

        Req.Test.json(conn, completion(~s({"feedback": {"anamnese": "Bom inicio."}})))
      end)

      assert {:ok, %{"anamnese" => "Bom inicio."}} = write(FeedbackInspectStub)

      assert_receive {:req, "POST", "/v1/chat/completions", ["Bearer sk-test-secret-key"],
                      payload}

      assert payload["model"] == "gpt-4o-mini"
      assert payload["response_format"] == %{"type" => "json_object"}

      assert [%{"role" => "system", "content" => system}, %{"role" => "user", "content" => user}] =
               payload["messages"]

      assert system =~ "400 characters"
      assert system =~ "language"
      assert system =~ ~s("feedback")

      user = Jason.decode!(user)
      assert user["language"] == "pt-BR"

      assert [%{"id" => "anamnese", "missing_actions" => ["Pergunta a irradiacao da dor"]}] =
               user["criteria"]

      refute Map.has_key?(user, "conversation")
      refute Map.has_key?(payload, "conversation")
    end

    test "honours custom base url and model" do
      test_pid = self()

      stub(FeedbackCustomStub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:custom, conn.host, conn.port, Jason.decode!(body)["model"]})
        Req.Test.json(conn, completion(~s({"feedback": {}})))
      end)

      assert {:ok, %{}} =
               write(FeedbackCustomStub,
                 base_url: "http://custom-ai.internal:9000/",
                 model: "gpt-4.1-mini"
               )

      assert_receive {:custom, "custom-ai.internal", 9000, "gpt-4.1-mini"}
    end
  end

  describe "response parsing" do
    test "returns the feedback object as a criterion id to text map" do
      stub(FeedbackSuccessStub, fn conn ->
        Req.Test.json(
          conn,
          completion(~s({"feedback": {"anamnese": "Pergunte a irradiacao.", "exame": "Ok."}}))
        )
      end)

      assert write(FeedbackSuccessStub) ==
               {:ok, %{"anamnese" => "Pergunte a irradiacao.", "exame" => "Ok."}}
    end

    test "passes non-string values through for the feedback step to police" do
      stub(FeedbackNonStringStub, fn conn ->
        Req.Test.json(conn, completion(~s({"feedback": {"anamnese": 3}})))
      end)

      assert write(FeedbackNonStringStub) == {:ok, %{"anamnese" => 3}}
    end

    test "rejects content that is not JSON" do
      stub(FeedbackNotJsonStub, fn conn -> Req.Test.json(conn, completion("not json")) end)
      assert write(FeedbackNotJsonStub) == {:error, :malformed_response}
    end

    test "rejects JSON without a feedback object" do
      stub(FeedbackMissingKeyStub, fn conn ->
        Req.Test.json(conn, completion(~s({"anamnese": "texto"})))
      end)

      assert write(FeedbackMissingKeyStub) == {:error, :malformed_response}

      stub(FeedbackListStub, fn conn ->
        Req.Test.json(conn, completion(~s({"feedback": ["texto"]})))
      end)

      assert write(FeedbackListStub) == {:error, :malformed_response}
    end

    test "rejects a completion payload without message content" do
      stub(FeedbackNoChoicesStub, fn conn -> Req.Test.json(conn, %{"choices" => []}) end)
      assert write(FeedbackNoChoicesStub) == {:error, :malformed_response}
    end
  end

  describe "error normalization" do
    test "missing or blank API key returns :missing_credentials without a request" do
      assert OpenAIAdapter.write_feedback(@request, api_key: "") == {:error, :missing_credentials}

      assert OpenAIAdapter.write_feedback(@request, api_key: "   ") ==
               {:error, :missing_credentials}
    end

    test "HTTP 5xx returns :upstream_error" do
      stub(FeedbackUpstreamStub, fn conn ->
        conn
        |> Plug.Conn.put_status(503)
        |> Req.Test.json(%{"error" => %{"message" => "overloaded"}})
      end)

      assert write(FeedbackUpstreamStub) == {:error, :upstream_error}
    end

    test "timeout returns :timeout" do
      stub(FeedbackTimeoutStub, fn conn -> Req.Test.transport_error(conn, :timeout) end)
      assert write(FeedbackTimeoutStub) == {:error, :timeout}
    end

    test "transport failure returns :network_error" do
      stub(FeedbackNetworkStub, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)
      assert write(FeedbackNetworkStub) == {:error, :network_error}
    end
  end
end
