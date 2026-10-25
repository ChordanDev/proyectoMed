defmodule Backend.Stations.LearnerFeedback.AnthropicAdapterTest do
  use ExUnit.Case, async: false

  alias Backend.Stations.LearnerFeedback.AnthropicAdapter

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

  defp message(text, stop_reason \\ "end_turn") do
    %{
      "type" => "message",
      "role" => "assistant",
      "content" => [%{"type" => "text", "text" => text}],
      "stop_reason" => stop_reason
    }
  end

  defp feedback_message(entries), do: message(Jason.encode!(%{"feedback" => entries}))

  defp write(name, opts \\ []) do
    AnthropicAdapter.write_feedback(
      @request,
      Keyword.merge([api_key: "sk-ant-test-secret", plug: {Req.Test, name}], opts)
    )
  end

  describe "request" do
    test "uses the shared model setting, never the patient or resolver model (issues #256, #343)" do
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
        patient_model: "claude-haiku-5-5",
        resolver_model: "claude-sonnet-5-5"
      )

      test_pid = self()

      Req.Test.stub(ClaudeFeedbackModelStub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})

        Req.Test.json(
          conn,
          feedback_message([%{"criterion_id" => "anamnese", "text" => "Bom inicio."}])
        )
      end)

      assert {:ok, _} = write(ClaudeFeedbackModelStub)
      assert_receive {:payload, payload}
      assert payload["model"] == "claude-opus-5-5"
      assert payload["output_config"]["effort"] == "medium"
      refute Map.has_key?(payload, "thinking")
    end

    test "posts the graded record with a JSON schema and medium effort, never a conversation" do
      test_pid = self()

      Req.Test.stub(ClaudeFeedbackInspectStub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        send(
          test_pid,
          {:req, conn.request_path, Plug.Conn.get_req_header(conn, "x-api-key"),
           Jason.decode!(body)}
        )

        Req.Test.json(
          conn,
          feedback_message([%{"criterion_id" => "anamnese", "text" => "Bom inicio."}])
        )
      end)

      assert {:ok, %{"anamnese" => "Bom inicio."}} = write(ClaudeFeedbackInspectStub)

      assert_receive {:req, "/v1/messages", ["sk-ant-test-secret"], payload}
      assert payload["model"] == "claude-opus-5-5"
      assert payload["fallbacks"] == "default"
      # Issue #272: the fixed system prompt is the cached prefix; the graded
      # record stays in the user message, after the breakpoint.
      assert [%{"type" => "text", "text" => system, "cache_control" => %{"type" => "ephemeral"}}] =
               payload["system"]

      assert system =~ "Never mention a global or total score"

      assert %{"effort" => "medium", "format" => %{"type" => "json_schema", "schema" => schema}} =
               payload["output_config"]

      assert schema == AnthropicAdapter.schema()

      assert [%{"role" => "user", "content" => content}] = payload["messages"]
      assert Jason.decode!(content) == Jason.decode!(Jason.encode!(@request))
      refute content =~ "conversation"

      for forbidden <- ["thinking", "temperature", "top_p", "response_format"] do
        refute Map.has_key?(payload, forbidden)
      end
    end

    test "the schema closes every object, as structured outputs require" do
      schema = AnthropicAdapter.schema()
      assert schema["additionalProperties"] == false
      assert schema["properties"]["feedback"]["items"]["additionalProperties"] == false
    end
  end

  describe "receive timeout" do
    setup do
      previous = Application.fetch_env(:backend, :learner_feedback_deadline_ms)

      on_exit(fn ->
        case previous do
          {:ok, value} -> Application.put_env(:backend, :learner_feedback_deadline_ms, value)
          :error -> Application.delete_env(:backend, :learner_feedback_deadline_ms)
        end
      end)
    end

    test "follows the learner feedback deadline" do
      test_pid = self()

      probe = fn request ->
        send(test_pid, {:receive_timeout, request.options[:receive_timeout]})
        {request, Req.Response.new(status: 200, body: feedback_message([]))}
      end

      Application.put_env(:backend, :learner_feedback_deadline_ms, 10_000)

      assert {:ok, %{}} =
               AnthropicAdapter.write_feedback(@request,
                 api_key: "k",
                 req_options: [adapter: probe]
               )

      assert_receive {:receive_timeout, 9_750}

      Application.delete_env(:backend, :learner_feedback_deadline_ms)

      assert {:ok, %{}} =
               AnthropicAdapter.write_feedback(@request,
                 api_key: "k",
                 req_options: [adapter: probe]
               )

      assert_receive {:receive_timeout, 59_750}
    end
  end

  describe "response" do
    test "maps the entries to a criterion id to text map, values unpoliced" do
      Req.Test.stub(ClaudeFeedbackMapStub, fn conn ->
        Req.Test.json(
          conn,
          feedback_message([
            %{"criterion_id" => "anamnese", "text" => "Pergunte a irradiacao."},
            %{"criterion_id" => "exame", "text" => "Voce passou."}
          ])
        )
      end)

      assert write(ClaudeFeedbackMapStub) ==
               {:ok, %{"anamnese" => "Pergunte a irradiacao.", "exame" => "Voce passou."}}
    end

    test "a refusal is a technical failure" do
      Req.Test.stub(ClaudeFeedbackRefusalStub, fn conn ->
        Req.Test.json(conn, message("{}", "refusal"))
      end)

      assert write(ClaudeFeedbackRefusalStub) == {:error, :refused}
    end

    test "invalid JSON, a shape mismatch or a truncated answer is malformed" do
      replies = [
        message("not json"),
        message(Jason.encode!(%{"feedback" => %{"anamnese" => "Ok."}})),
        message(Jason.encode!(%{"texts" => []})),
        feedback_message([%{"criterion_id" => "anamnese"}]),
        feedback_message([%{"criterion_id" => 1, "text" => "Ok."}]),
        feedback_message(["Ok."]),
        message(Jason.encode!(%{"feedback" => []}), "max_tokens"),
        %{"type" => "message", "content" => []}
      ]

      for reply <- replies do
        Req.Test.stub(ClaudeFeedbackMalformedStub, fn conn -> Req.Test.json(conn, reply) end)
        assert write(ClaudeFeedbackMalformedStub) == {:error, :malformed_response}
      end
    end
  end

  describe "errors" do
    test "a missing or blank key sends nothing" do
      for key <- [nil, ""] do
        assert AnthropicAdapter.write_feedback(@request, api_key: key) ==
                 {:error, :missing_credentials}
      end
    end

    test "an HTTP error is an upstream error" do
      Req.Test.stub(ClaudeFeedbackUpstreamStub, fn conn ->
        conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"type" => "error"})
      end)

      assert write(ClaudeFeedbackUpstreamStub) == {:error, :upstream_error}
    end

    test "a timeout is a timeout" do
      Req.Test.stub(ClaudeFeedbackTimeoutStub, &Req.Test.transport_error(&1, :timeout))
      assert write(ClaudeFeedbackTimeoutStub) == {:error, :timeout}
    end

    test "a connection failure is a network error" do
      Req.Test.stub(ClaudeFeedbackNetworkStub, &Req.Test.transport_error(&1, :econnrefused))
      assert write(ClaudeFeedbackNetworkStub) == {:error, :network_error}
    end
  end
end
