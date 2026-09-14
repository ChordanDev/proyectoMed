defmodule Backend.StationAI.OpenAIAdapterTest do
  use ExUnit.Case, async: false

  alias Backend.StationAI
  alias Backend.StationAI.OpenAIAdapter

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
      %{"topic" => "onset", "content" => "A dor começou durante uma caminhada."}
    ],
    "response_rules" => []
  }

  describe "outgoing request formatting" do
    test "sends Bearer auth, path, default model, and exact role/content messages" do
      test_pid = self()

      Req.Test.stub(InspectStub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        send(
          test_pid,
          {:req, conn.request_path, Plug.Conn.get_req_header(conn, "authorization"),
           Jason.decode!(body)}
        )

        Req.Test.json(conn, %{
          "choices" => [
            %{
              "message" => %{
                "role" => "assistant",
                "content" => "A dor começou durante uma caminhada."
              }
            }
          ]
        })
      end)

      context = %{
        conversation: [
          %{role: :student, text: "Quando começou a dor?"},
          %{role: :patient, text: "Há duas horas."}
        ],
        language: "pt-BR"
      }

      assert {:ok, %{text: "A dor começou durante uma caminhada."}} =
               OpenAIAdapter.next_reply(@package, context,
                 api_key: "sk-test-secret-key",
                 plug: {Req.Test, InspectStub}
               )

      assert_receive {:req, path, auth_headers, payload}
      assert path == "/v1/chat/completions"
      assert auth_headers == ["Bearer sk-test-secret-key"]
      assert payload["model"] == "gpt-4o-mini"

      assert [sys, student, patient] = payload["messages"]
      assert sys == %{"role" => "system", "content" => StationAI.system_prompt(@package)}
      assert student == %{"role" => "user", "content" => "Quando começou a dor?"}
      assert patient == %{"role" => "assistant", "content" => "Há duas horas."}
    end

    test "allows custom base_url and custom model overrides" do
      test_pid = self()

      Req.Test.stub(CustomStub, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:custom, conn.host, conn.port, Jason.decode!(body)["model"]})
        Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "ok"}}]})
      end)

      assert {:ok, %{text: "ok"}} =
               OpenAIAdapter.next_reply(@package, %{conversation: []},
                 api_key: "test-key",
                 base_url: "http://custom-ai.internal:9000/api",
                 model: "gpt-4.1-turbo",
                 plug: {Req.Test, CustomStub}
               )

      assert_receive {:custom, "custom-ai.internal", 9000, "gpt-4.1-turbo"}
    end
  end

  describe "response parsing and metadata encapsulation" do
    test "returns only %{text: text} and never exposes OpenAI metadata" do
      Req.Test.stub(MetadataStub, fn conn ->
        Req.Test.json(conn, %{
          "id" => "chatcmpl-secret",
          "model" => "gpt-4o-mini",
          "usage" => %{"total_tokens" => 42},
          "choices" => [%{"index" => 0, "message" => %{"content" => "Estou com dor."}}]
        })
      end)

      assert {:ok, reply} =
               OpenAIAdapter.next_reply(@package, %{conversation: []},
                 api_key: "test-key",
                 plug: {Req.Test, MetadataStub}
               )

      assert reply == %{text: "Estou com dor."}
    end
  end

  describe "error normalization" do
    test "normalizes missing or empty API key into :missing_credentials" do
      context = %{conversation: []}

      assert OpenAIAdapter.next_reply(@package, context, api_key: nil) ==
               {:error, :missing_credentials}

      assert OpenAIAdapter.next_reply(@package, context, api_key: "") ==
               {:error, :missing_credentials}

      assert OpenAIAdapter.next_reply(@package, context, api_key: "   ") ==
               {:error, :missing_credentials}
    end

    test "normalizes non-2xx responses into :upstream_error without leaking status or body" do
      Req.Test.stub(ErrorResponseStub, fn conn ->
        conn
        |> Plug.Conn.put_status(401)
        |> Req.Test.json(%{"error" => %{"message" => "secret-key-leak"}})
      end)

      assert OpenAIAdapter.next_reply(@package, %{conversation: []},
               api_key: "sk-bad",
               plug: {Req.Test, ErrorResponseStub}
             ) == {:error, :upstream_error}
    end

    test "normalizes timeout into :timeout" do
      Req.Test.stub(TimeoutStub, fn conn -> Req.Test.transport_error(conn, :timeout) end)

      assert OpenAIAdapter.next_reply(@package, %{conversation: []},
               api_key: "key",
               plug: {Req.Test, TimeoutStub}
             ) == {:error, :timeout}
    end

    test "normalizes transport connection failure into :network_error" do
      Req.Test.stub(TransportFailStub, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert OpenAIAdapter.next_reply(@package, %{conversation: []},
               api_key: "key",
               plug: {Req.Test, TransportFailStub}
             ) == {:error, :network_error}
    end

    test "normalizes malformed response bodies into :malformed_response" do
      malformed_bodies = [
        %{"id" => "chatcmpl-1"},
        %{"choices" => []},
        %{"choices" => [%{"message" => %{"content" => nil}}]}
      ]

      for {body, idx} <- Enum.with_index(malformed_bodies) do
        stub = Module.concat(__MODULE__, "MalformedStub#{idx}")
        Req.Test.stub(stub, fn conn -> Req.Test.json(conn, body) end)

        assert OpenAIAdapter.next_reply(@package, %{conversation: []},
                 api_key: "key",
                 plug: {Req.Test, stub}
               ) == {:error, :malformed_response}
      end

      Req.Test.stub(HtmlStub, fn conn -> Req.Test.text(conn, "<html>502</html>") end)

      assert OpenAIAdapter.next_reply(@package, %{conversation: []},
               api_key: "key",
               plug: {Req.Test, HtmlStub}
             ) == {:error, :malformed_response}
    end
  end

  describe "StationAI integration and BoundedReply preservation" do
    setup do
      prev_adapter = Application.get_env(:backend, :station_ai_adapter)
      prev_config = Application.get_env(:backend, OpenAIAdapter)

      on_exit(fn ->
        if is_nil(prev_adapter),
          do: Application.delete_env(:backend, :station_ai_adapter),
          else: Application.put_env(:backend, :station_ai_adapter, prev_adapter)

        if is_nil(prev_config),
          do: Application.delete_env(:backend, OpenAIAdapter),
          else: Application.put_env(:backend, OpenAIAdapter, prev_config)
      end)

      :ok
    end

    test "StationAI defaults to OpenAIAdapter and bounds replies through BoundedReply" do
      Application.delete_env(:backend, :station_ai_adapter)

      Req.Test.stub(StationAIBoundedStub, fn conn ->
        Req.Test.json(conn, %{
          "choices" => [
            %{
              "message" => %{
                "role" => "assistant",
                "content" => "A dor começou durante uma caminhada."
              }
            }
          ]
        })
      end)

      Application.put_env(:backend, OpenAIAdapter,
        api_key: "integration-key",
        req_options: [plug: {Req.Test, StationAIBoundedStub}]
      )

      assert {:ok, reply} = StationAI.next_reply(@package, %{conversation: []})
      assert reply.text == "A dor começou durante uma caminhada."
      assert [%{"topic" => "onset"}] = reply.used_facts
    end

    test "StationAI enforces refusal when OpenAI reply breaks character" do
      Application.delete_env(:backend, :station_ai_adapter)

      Req.Test.stub(RoleplayLeakStub, fn conn ->
        Req.Test.json(conn, %{
          "choices" => [
            %{
              "message" => %{
                "role" => "assistant",
                "content" => "Sou uma inteligência artificial."
              }
            }
          ]
        })
      end)

      Application.put_env(:backend, OpenAIAdapter,
        api_key: "integration-key",
        req_options: [plug: {Req.Test, RoleplayLeakStub}]
      )

      assert {:ok, reply} = StationAI.next_reply(@package, %{conversation: []})
      assert reply.text == StationAI.refusal_text()
      assert reply.used_facts == []
    end
  end
end
