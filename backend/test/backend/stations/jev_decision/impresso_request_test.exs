defmodule Backend.Stations.JevDecision.ImpressoRequestTest do
  # Issue #357: Jev classifies an unavailable impresso request as plausible or
  # not plausible for the case. async: false because one test changes the
  # application environment.
  use ExUnit.Case, async: false

  alias Backend.Stations.JevDecision
  alias Backend.Stations.JevDecision.TypesafeAdapter

  @question "plausible"

  @package %{
    "id" => "acute-appendicitis",
    "candidate_brief" => %{
      "scenario" => "Pronto-socorro: Rafael, 27 anos, dor abdominal.",
      "tasks" => ["Solicitar os exames pertinentes."]
    },
    "patient_profile" => %{"age" => 27, "presenting_context" => "Dor abdominal há 18 horas."},
    "impressos" => [%{"id" => "hemograma", "content" => "authored content must not travel"}],
    "facts" => [%{"id" => "fact-1", "content" => "hidden fact must not travel"}]
  }

  defmodule SlowAdapter do
    @moduledoc false
    def decide_impresso_request(_request) do
      Process.sleep(500)
      {:ok, %{classification: "plausible"}}
    end
  end

  defmodule NoCallbackAdapter do
    @moduledoc false
    def decide_patient(_request), do: {:error, :adapter_disabled}
  end

  defp request(overrides \\ %{}) do
    Map.merge(%{text: "Solicito uma tomografia de abdome.", package: @package}, overrides)
  end

  defp reply_adapter(reply) do
    name = :"impresso_reply_#{System.unique_integer([:positive])}"
    module = Module.concat(__MODULE__, name)

    Module.create(
      module,
      quote do
        def decide_impresso_request(_request), do: unquote(Macro.escape(reply))
      end,
      Macro.Env.location(__ENV__)
    )

    module
  end

  describe "decide_impresso_request/2 seam" do
    test "maps the adapter labels to classifications" do
      for {label, expected} <- [
            {"plausible", :plausible},
            {"not_plausible", :not_plausible},
            {"undecided", :undecided},
            {:plausible, :plausible}
          ] do
        adapter = reply_adapter({:ok, %{classification: label}})

        assert JevDecision.decide_impresso_request(request(), adapter: adapter) ==
                 {:ok, %{classification: expected}}
      end
    end

    test "defaults to the disabled adapter, a typed technical failure" do
      assert {:error, {:adapter_disabled, _message}} =
               JevDecision.decide_impresso_request(request())
    end

    test "a label outside the closed set is rejected" do
      adapter = reply_adapter({:ok, %{classification: "Considere solicitado."}})

      assert JevDecision.decide_impresso_request(request(), adapter: adapter) ==
               {:error, {:invalid_response, :invalid_classification}}

      adapter = reply_adapter({:ok, %{}})

      assert JevDecision.decide_impresso_request(request(), adapter: adapter) ==
               {:error, {:invalid_response, :invalid_classification}}
    end

    test "an adapter error is sanitized" do
      adapter = reply_adapter({:error, {:upstream_error, 503}})

      assert JevDecision.decide_impresso_request(request(), adapter: adapter) ==
               {:error, {:upstream_5xx, 503}}
    end

    test "an adapter without the callback is a typed failure" do
      assert JevDecision.decide_impresso_request(request(), adapter: NoCallbackAdapter) ==
               {:error, {:technical_failure, :unsupported_adapter}}
    end

    test "a slow adapter times out at the impresso deadline" do
      started = System.monotonic_time(:millisecond)

      assert JevDecision.decide_impresso_request(request(), adapter: SlowAdapter, deadline_ms: 50) ==
               {:error, :timeout}

      assert System.monotonic_time(:millisecond) - started < 400
    end

    test "the default deadline is the impresso deadline, configurable" do
      assert JevDecision.impresso_deadline_ms() == 2_000

      previous = Application.get_env(:backend, :jev_decision_impresso_deadline_ms)
      Application.put_env(:backend, :jev_decision_impresso_deadline_ms, 40)

      try do
        assert JevDecision.decide_impresso_request(request(), adapter: SlowAdapter) ==
                 {:error, :timeout}
      after
        if previous,
          do: Application.put_env(:backend, :jev_decision_impresso_deadline_ms, previous),
          else: Application.delete_env(:backend, :jev_decision_impresso_deadline_ms)
      end
    end

    test "blank or overlong request text is rejected before the adapter" do
      adapter = reply_adapter({:ok, %{classification: "plausible"}})

      assert JevDecision.decide_impresso_request(request(%{text: "  "}), adapter: adapter) ==
               {:error, {:invalid_request, :invalid_text}}

      long = String.duplicate("a", JevDecision.max_characters() + 1)

      assert JevDecision.decide_impresso_request(request(%{text: long}), adapter: adapter) ==
               {:error, {:invalid_request, :context_limit_exceeded}}
    end

    test "the adapter receives only the request text and the case context" do
      test_pid = self()
      name = :"impresso_capture_#{System.unique_integer([:positive])}"
      module = Module.concat(__MODULE__, name)

      Module.create(
        module,
        quote do
          def decide_impresso_request(request) do
            send(unquote(test_pid), {:adapter_request, request})
            {:ok, %{classification: "not_plausible"}}
          end
        end,
        Macro.Env.location(__ENV__)
      )

      assert {:ok, %{classification: :not_plausible}} =
               JevDecision.decide_impresso_request(request(), adapter: module)

      assert_received {:adapter_request, sent}

      assert sent.text == "Solicito uma tomografia de abdome."

      assert sent.case == %{
               "candidate_brief" => @package["candidate_brief"],
               "patient_profile" => @package["patient_profile"]
             }

      assert is_integer(sent.deadline_ms)
      assert is_integer(sent.deadline_at_monotonic_ms)
      refute inspect(sent) =~ "must not travel"
    end
  end

  describe "TypesafeAdapter.decide_impresso_request/2" do
    defp stub(name, answers, status \\ 200) do
      test_pid = self()

      Req.Test.stub(name, fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:typesafe_request, Jason.decode!(raw)})

        conn
        |> Plug.Conn.put_status(status)
        |> Req.Test.json(%{"model" => "jev-1.13.0", "answers" => answers})
      end)

      [api_key: "ts-test-key", plug: {Req.Test, name}]
    end

    defp noul(value), do: %{@question => %{"type" => "noul", "noul" => value}}

    defp adapter_request do
      %{
        text: "Solicito uma tomografia de abdome.",
        case: Map.take(@package, ["candidate_brief", "patient_profile"]),
        deadline_ms: 1_000
      }
    end

    test "a yes is plausible, a no is not plausible, in between is undecided" do
      for {value, expected} <- [{0.93, "plausible"}, {0.05, "not_plausible"}, {0.5, "undecided"}] do
        opts = stub(ImpressoThresholdStub, noul(value))

        assert TypesafeAdapter.decide_impresso_request(adapter_request(), opts) ==
                 {:ok, %{classification: expected}}
      end
    end

    test "sends one noul question with the request text and case in state" do
      opts = stub(ImpressoPayloadStub, noul(0.9))

      assert {:ok, _} = TypesafeAdapter.decide_impresso_request(adapter_request(), opts)
      assert_received {:typesafe_request, payload}

      assert payload["model"] == "jev-1.13.0"
      assert payload["state"]["exam_request"] == "Solicito uma tomografia de abdome."
      assert payload["state"]["case"]["candidate_brief"]["scenario"] =~ "Rafael"
      assert Map.keys(payload["questions"]) == [@question]
      assert payload["questions"][@question]["type"] == "noul"
      refute payload["questions"][@question]["instructions"] =~ "tomografia"
    end

    test "a missing answer or an upstream error is a technical failure" do
      opts = stub(ImpressoMissingStub, %{})

      assert TypesafeAdapter.decide_impresso_request(adapter_request(), opts) ==
               {:error, {:invalid_response, :missing_answer}}

      opts = stub(ImpressoUpstreamStub, noul(0.9), 503)

      assert TypesafeAdapter.decide_impresso_request(adapter_request(), opts) ==
               {:error, {:upstream_error, 503}}
    end

    test "no credentials fails before any call" do
      Req.Test.stub(ImpressoNoKeyStub, fn _conn -> flunk("provider must not be called") end)

      assert TypesafeAdapter.decide_impresso_request(adapter_request(),
               api_key: "",
               plug: {Req.Test, ImpressoNoKeyStub}
             ) == {:error, {:technical_failure, :missing_credentials}}
    end

    test "every HTTP response is metered as one Jev call of the tracked session" do
      opts = stub(ImpressoUsageStub, noul(0.9))
      session_id = "usage-#{System.unique_integer([:positive])}"

      Backend.Stations.Usage.track(session_id, fn ->
        assert {:ok, _} = TypesafeAdapter.decide_impresso_request(adapter_request(), opts)
      end)

      assert Backend.Stations.Usage.snapshot(session_id).jev_calls == 1
    end
  end
end
