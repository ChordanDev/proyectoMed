defmodule Backend.Stations.StationAI.AnthropicAdapterTest do
  use ExUnit.Case, async: false

  alias Backend.Stations.StationAI
  alias Backend.Stations.StationAI.AnthropicAdapter

  @package %{
    "id" => "station-1",
    "language" => "pt-BR",
    "patient_profile" => %{
      "persona" => "Maria Silva",
      "age" => 52,
      "tone" => "ansiosa",
      "presenting_context" => "Dor no peito"
    },
    "revealable_facts" => [
      %{"id" => "f1", "topic" => "onset", "content" => "A dor começou durante uma caminhada."}
    ],
    "response_rules" => []
  }

  @context %{
    conversation: [
      %{role: :student, text: "Bom dia."},
      %{role: :patient, text: "Bom dia, doutor."},
      %{role: :student, text: "Quando começou a dor?"}
    ],
    language: "pt-BR"
  }

  defp message(content, stop_reason \\ "end_turn") do
    %{
      "id" => "msg_1",
      "type" => "message",
      "role" => "assistant",
      "model" => "claude-opus-5-5",
      "content" => content,
      "stop_reason" => stop_reason
    }
  end

  defp reply(name, opts \\ []) do
    AnthropicAdapter.next_reply(
      @package,
      Keyword.get(opts, :context, @context),
      Keyword.merge([api_key: "sk-ant-test-secret", plug: {Req.Test, name}], opts)
    )
  end

  describe "request" do
    test "posts a Sonnet 5.5 Messages request with the safety prompt, roles, low effort, thinking off and fallbacks" do
      test_pid = self()

      Req.Test.stub(PatientInspectStub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        send(test_pid, {
          :req,
          conn.method,
          conn.request_path,
          Map.new(conn.req_headers),
          Jason.decode!(body)
        })

        Req.Test.json(conn, message([%{"type" => "text", "text" => "Há duas horas."}]))
      end)

      assert {:ok, %{text: "Há duas horas."}} = reply(PatientInspectStub)

      assert_receive {:req, "POST", "/v1/messages", headers, payload}
      assert headers["x-api-key"] == "sk-ant-test-secret"
      assert headers["anthropic-version"] == "2023-06-01"
      assert headers["anthropic-beta"] == "server-side-fallback-2026-07-01"
      refute Map.has_key?(headers, "authorization")

      # Issue #256: the patient defaults to Sonnet 5.5, where `disabled`
      # thinking is a 400 and `between_tools` (alone) is the lowest setting.
      assert payload["model"] == "claude-sonnet-5-5"
      assert payload["thinking"] == %{"type" => "between_tools"}

      assert payload["system"] == [
               %{
                 "type" => "text",
                 "text" => StationAI.system_prompt(@package, @context),
                 "cache_control" => %{"type" => "ephemeral"}
               }
             ]

      assert payload["output_config"] == %{"effort" => "low"}
      assert payload["fallbacks"] == "default"
      assert is_integer(payload["max_tokens"]) and payload["max_tokens"] > 0

      for forbidden <- ["temperature", "top_p", "top_k", "response_format"] do
        refute Map.has_key?(payload, forbidden)
      end

      assert payload["messages"] == [
               %{"role" => "user", "content" => "Bom dia."},
               %{"role" => "assistant", "content" => "Bom dia, doutor."},
               %{"role" => "user", "content" => "Quando começou a dor?"}
             ]
    end

    test "carries withheld fact ids into the system prompt (issue #242)" do
      test_pid = self()

      Req.Test.stub(PatientWithheldStub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:system, Jason.decode!(body)["system"]})
        Req.Test.json(conn, message([%{"type" => "text", "text" => "Há duas horas."}]))
      end)

      context = Map.put(@context, :withheld_fact_ids, ["f1"])
      assert {:ok, _} = reply(PatientWithheldStub, context: context)
      assert_receive {:system, system}
      assert Enum.map_join(system, & &1["text"]) == StationAI.system_prompt(@package, context)

      # Issue #272: the withheld section is per-turn, so it follows the cached
      # base prompt as an unmarked block.
      assert [
               %{
                 "text" => stable,
                 "cache_control" => %{"type" => "ephemeral"}
               },
               %{"type" => "text", "text" => per_turn} = suffix
             ] = system

      assert stable == StationAI.system_prompt(@package)
      assert per_turn =~ "FATOS QUE VOCÊ AINDA NÃO PODE MENCIONAR"
      refute Map.has_key?(suffix, "cache_control")
    end

    test "keeps the cached prefix byte-identical across two turns of a session (issue #272)" do
      test_pid = self()

      Req.Test.stub(PatientCacheStub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:body, Jason.decode!(body)})
        Req.Test.json(conn, message([%{"type" => "text", "text" => "Há duas horas."}]))
      end)

      first_turn = %{@context | conversation: Enum.take(@context.conversation, 1)}
      assert {:ok, _} = reply(PatientCacheStub, context: first_turn)
      assert_receive {:body, first}

      assert {:ok, _} = reply(PatientCacheStub)
      assert_receive {:body, second}

      assert [%{"cache_control" => %{"type" => "ephemeral"}} = cached] = first["system"]
      assert Jason.encode!(second["system"]) == Jason.encode!(first["system"])
      assert cached["text"] == StationAI.system_prompt(@package)

      # Per-turn content lives only in `messages`, after the breakpoint, and the
      # earlier turn reappears unchanged as a prefix of the next request.
      assert List.starts_with?(second["messages"], first["messages"])
      refute cached["text"] =~ "Quando começou a dor?"

      for key <- ["model", "output_config", "thinking", "fallbacks", "max_tokens"] do
        assert second[key] == first[key]
      end
    end

    test "honours base url, model and effort overrides" do
      test_pid = self()

      Req.Test.stub(PatientOverrideStub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)
        send(test_pid, {:req, conn.host, payload["model"], payload["output_config"]})
        Req.Test.json(conn, message([%{"type" => "text", "text" => "Sim."}]))
      end)

      assert {:ok, %{text: "Sim."}} =
               reply(PatientOverrideStub,
                 base_url: "https://anthropic.example.test/",
                 model: "claude-sonnet-5-5",
                 effort: "medium"
               )

      assert_receive {:req, "anthropic.example.test", "claude-sonnet-5-5",
                      %{"effort" => "medium"}}
    end

    test "a patient model other than Sonnet 5.5 gets no thinking field" do
      test_pid = self()

      Req.Test.stub(PatientOpusStub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, message([%{"type" => "text", "text" => "Sim."}]))
      end)

      assert {:ok, _} = reply(PatientOpusStub, model: "claude-opus-5-5")
      assert_receive {:payload, payload}
      assert payload["model"] == "claude-opus-5-5"
      refute Map.has_key?(payload, "thinking")
      assert payload["output_config"] == %{"effort" => "low"}
    end

    test "reads key, base url and model from the application configuration" do
      previous = Application.fetch_env(:backend, Backend.Stations.StationAI.AnthropicClient)

      on_exit(fn ->
        case previous do
          {:ok, value} ->
            Application.put_env(:backend, Backend.Stations.StationAI.AnthropicClient, value)

          :error ->
            Application.delete_env(:backend, Backend.Stations.StationAI.AnthropicClient)
        end
      end)

      # `:model` serves the resolver and feedback; the patient reads `:patient_model`.
      Application.put_env(:backend, Backend.Stations.StationAI.AnthropicClient,
        api_key: "sk-ant-from-config",
        model: "claude-opus-5-5",
        patient_model: "claude-haiku-5-5"
      )

      test_pid = self()

      Req.Test.stub(PatientConfigStub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        send(
          test_pid,
          {:req, Plug.Conn.get_req_header(conn, "x-api-key"), Jason.decode!(body)["model"]}
        )

        Req.Test.json(conn, message([%{"type" => "text", "text" => "Sim."}]))
      end)

      assert {:ok, _} =
               AnthropicAdapter.next_reply(@package, @context,
                 plug: {Req.Test, PatientConfigStub}
               )

      assert_receive {:req, ["sk-ant-from-config"], "claude-haiku-5-5"}
    end

    test "the patient ignores the shared model setting and defaults to Sonnet 5.5" do
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
        api_key: "sk-ant-from-config",
        model: "claude-opus-5-5"
      )

      test_pid = self()

      Req.Test.stub(PatientDefaultModelStub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})
        Req.Test.json(conn, message([%{"type" => "text", "text" => "Sim."}]))
      end)

      assert {:ok, _} =
               AnthropicAdapter.next_reply(@package, @context,
                 plug: {Req.Test, PatientDefaultModelStub}
               )

      assert_receive {:payload, payload}
      assert payload["model"] == "claude-sonnet-5-5"
      assert payload["thinking"] == %{"type" => "between_tools"}
    end
  end

  describe "response" do
    test "reads text blocks by type, skipping thinking and fallback blocks" do
      Req.Test.stub(PatientBlocksStub, fn conn ->
        Req.Test.json(
          conn,
          message([
            %{
              "type" => "fallback",
              "from" => %{"model" => "claude-opus-5-5"},
              "to" => %{"model" => "claude-opus-5"}
            },
            %{"type" => "thinking", "thinking" => "", "signature" => "sig"},
            %{"type" => "text", "text" => "Começou "},
            %{"type" => "text", "text" => "há duas horas."}
          ])
        )
      end)

      assert reply(PatientBlocksStub) == {:ok, %{text: "Começou há duas horas."}}
    end

    test "a refusal is a technical failure and never returns provider text" do
      Req.Test.stub(PatientRefusalStub, fn conn ->
        Req.Test.json(
          conn,
          message([%{"type" => "text", "text" => "partial text"}], "refusal")
          |> Map.put("stop_details", %{"category" => "bio"})
        )
      end)

      assert reply(PatientRefusalStub) == {:error, :refused}
    end

    test "a truncated or unexpected stop is malformed, never a partial reply" do
      for {stop_reason, idx} <- Enum.with_index(["max_tokens", "pause_turn", "tool_use", nil]) do
        name = :"PatientStopStub#{idx}"

        Req.Test.stub(name, fn conn ->
          Req.Test.json(conn, message([%{"type" => "text", "text" => "Há duas"}], stop_reason))
        end)

        assert reply(name) == {:error, :malformed_response}, "stop_reason #{inspect(stop_reason)}"
      end
    end

    test "a body without usable text is malformed" do
      bodies = [
        %{"type" => "message"},
        message([]),
        message([%{"type" => "thinking", "thinking" => ""}]),
        message([%{"type" => "text", "text" => "   "}]),
        message(nil)
      ]

      for {body, idx} <- Enum.with_index(bodies) do
        name = :"PatientMalformedStub#{idx}"
        Req.Test.stub(name, fn conn -> Req.Test.json(conn, body) end)
        assert reply(name) == {:error, :malformed_response}, "body #{idx}"
      end
    end
  end

  describe "errors" do
    test "a missing or blank key sends nothing" do
      Req.Test.stub(PatientNoKeyStub, fn _conn -> flunk("no request expected") end)

      for key <- [nil, "", "   "] do
        assert AnthropicAdapter.next_reply(@package, @context,
                 api_key: key,
                 plug: {Req.Test, PatientNoKeyStub}
               ) == {:error, :missing_credentials}
      end
    end

    test "HTTP errors are upstream errors without leaking the body" do
      for {status, idx} <- Enum.with_index([400, 401, 429, 500, 529]) do
        name = :"PatientHttpStub#{idx}"

        Req.Test.stub(name, fn conn ->
          conn
          |> Plug.Conn.put_status(status)
          |> Req.Test.json(%{"type" => "error", "error" => %{"message" => "secret detail"}})
        end)

        assert reply(name) == {:error, :upstream_error}
      end
    end

    test "a timeout is a timeout" do
      Req.Test.stub(PatientTimeoutStub, &Req.Test.transport_error(&1, :timeout))
      assert reply(PatientTimeoutStub) == {:error, :timeout}
    end

    test "a connection failure is a network error" do
      Req.Test.stub(PatientRefusedConnStub, &Req.Test.transport_error(&1, :econnrefused))
      assert reply(PatientRefusedConnStub) == {:error, :network_error}
    end
  end

  describe "StationAI integration" do
    setup do
      keys = [:station_ai_adapter, Backend.Stations.StationAI.AnthropicClient]
      previous = Map.new(keys, &{&1, Application.fetch_env(:backend, &1)})

      on_exit(fn ->
        Enum.each(previous, fn
          {key, {:ok, value}} -> Application.put_env(:backend, key, value)
          {key, :error} -> Application.delete_env(:backend, key)
        end)
      end)

      Application.put_env(:backend, :station_ai_adapter, AnthropicAdapter)

      Application.put_env(:backend, Backend.Stations.StationAI.AnthropicClient,
        api_key: "sk-ant-test-secret",
        req_options: [plug: {Req.Test, PatientIntegrationStub}]
      )
    end

    test "a selected Anthropic adapter serves StationAI and its reply is bounded" do
      Req.Test.stub(PatientIntegrationStub, fn conn ->
        Req.Test.json(
          conn,
          message([%{"type" => "text", "text" => "A dor começou durante uma caminhada."}])
        )
      end)

      assert {:ok, %{text: "A dor começou durante uma caminhada.", used_facts: [_fact]}} =
               StationAI.next_reply(@package, @context)
    end

    test "a reply that breaks character is replaced by the canonical refusal" do
      Req.Test.stub(PatientIntegrationStub, fn conn ->
        Req.Test.json(
          conn,
          message([%{"type" => "text", "text" => "Sou uma inteligência artificial."}])
        )
      end)

      assert {:ok, %{text: text, used_facts: []}} = StationAI.next_reply(@package, @context)
      assert text == StationAI.refusal_text()
    end
  end

  describe "stream_reply/4 (issue #271)" do
    test "streams the same patient request and hands each text delta over" do
      test_pid = self()

      Req.Test.stub(PatientStreamStub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:payload, Jason.decode!(body)})

        events =
          [
            %{
              "type" => "content_block_delta",
              "index" => 0,
              "delta" => %{"type" => "text_delta", "text" => "Há duas "}
            },
            %{
              "type" => "content_block_delta",
              "index" => 0,
              "delta" => %{"type" => "text_delta", "text" => "horas."}
            },
            %{"type" => "message_delta", "delta" => %{"stop_reason" => "end_turn"}}
          ]
          |> Enum.map_join(&"event: #{&1["type"]}\ndata: #{Jason.encode!(&1)}\n\n")

        conn
        |> Plug.Conn.put_resp_content_type("text/event-stream")
        |> Plug.Conn.send_resp(200, events)
      end)

      assert {:ok, %{text: "Há duas horas."}} =
               AnthropicAdapter.stream_reply(
                 @package,
                 @context,
                 &send(test_pid, {:delta, &1}),
                 api_key: "sk-ant-test-secret",
                 plug: {Req.Test, PatientStreamStub}
               )

      assert_received {:delta, "Há duas "}
      assert_received {:delta, "horas."}
      assert_received {:payload, payload}
      assert payload["stream"] == true
      assert payload["model"] == "claude-sonnet-5-5"
      assert payload["thinking"] == %{"type" => "between_tools"}
      assert payload["output_config"] == %{"effort" => "low"}
      assert [%{"cache_control" => %{"type" => "ephemeral"}}] = payload["system"]

      assert List.last(payload["messages"]) == %{
               "role" => "user",
               "content" => "Quando começou a dor?"
             }
    end
  end
end
