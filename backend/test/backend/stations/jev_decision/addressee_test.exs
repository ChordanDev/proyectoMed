defmodule Backend.Stations.JevDecision.AddresseeTest do
  @moduledoc """
  Issue #274: one TypeSafe question decides whether a learner turn is addressed
  to the examiner or to the patient, before any patient reply is generated.
  """
  # async: false because one test raises the global log level to :debug.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  require Logger

  alias Backend.Stations.JevDecision
  alias Backend.Stations.JevDecision.TypesafeAdapter

  @finding "Ao exame, abdome doloroso em fossa ilíaca direita, Blumberg positivo."
  @question_id "addressee:examiner"

  defp conversation do
    [
      %{role: :learner, text: "Bom dia, sou o estudante."},
      %{role: :patient, text: "Bom dia, doutor."},
      %{role: :learner, text: @finding}
    ]
  end

  defp request(overrides \\ %{}) do
    Map.merge(%{conversation: conversation(), deadline_ms: 1_000}, overrides)
  end

  # A TypeSafe stub answering the single question with `noul`; every payload is
  # sent to the test process.
  defp answering(name, noul) do
    test_pid = self()

    Req.Test.stub(name, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:payload, Jason.decode!(raw)})
      Req.Test.json(conn, %{"answers" => %{@question_id => %{"type" => "noul", "noul" => noul}}})
    end)

    [api_key: "ts-test-key", plug: {Req.Test, name}]
  end

  defp adapter_request(opts \\ []) do
    %{
      conversation: [
        %{seq: 1, role: :student, text: "Bom dia, sou o estudante.", trust: :untrusted},
        %{seq: 2, role: :patient, text: "Bom dia, doutor.", trust: :trusted},
        %{seq: 3, role: :student, text: @finding, trust: :untrusted}
      ],
      latest_learner_turn: %{seq: 3, role: :student, text: @finding, trust: :untrusted},
      deadline_ms: Keyword.get(opts, :deadline_ms, 1_000),
      deadline_at_monotonic_ms:
        System.monotonic_time(:millisecond) + Keyword.get(opts, :deadline_ms, 1_000)
    }
  end

  describe "TypesafeAdapter.decide_addressee/2" do
    test "asks one noul question over the learner message and the conversation only" do
      opts = answering(AddresseeExaminerStub, 0.93)

      assert {:ok, %{addressee: :examiner}} =
               TypesafeAdapter.decide_addressee(adapter_request(), opts)

      assert_received {:payload, payload}
      assert Map.keys(payload["questions"]) == [@question_id]

      assert %{"type" => "noul", "instructions" => instructions} =
               payload["questions"][@question_id]

      assert instructions["question"] =~ "examiner"
      assert payload["state"]["latest_learner_message"] == @finding

      assert payload["state"]["conversation"] == [
               %{"speaker" => "learner", "text" => "Bom dia, sou o estudante."},
               %{"speaker" => "patient", "text" => "Bom dia, doutor."},
               %{"speaker" => "learner", "text" => @finding}
             ]

      assert Map.keys(payload["state"]) |> Enum.sort() == [
               "conversation",
               "latest_learner_message"
             ]
    end

    test "a no answer is patient-addressed" do
      opts = answering(AddresseePatientStub, 0.05)

      assert {:ok, %{addressee: :patient}} =
               TypesafeAdapter.decide_addressee(adapter_request(), opts)
    end

    test "an answer between the thresholds is undecided" do
      opts = answering(AddresseeUndecidedStub, 0.5)

      assert {:ok, %{addressee: :undecided}} =
               TypesafeAdapter.decide_addressee(adapter_request(), opts)
    end

    test "the thresholds are inclusive (0.8 yes, 0.2 no)" do
      assert {:ok, %{addressee: :examiner}} =
               TypesafeAdapter.decide_addressee(adapter_request(), answering(AtYesStub, 0.8))

      assert {:ok, %{addressee: :patient}} =
               TypesafeAdapter.decide_addressee(adapter_request(), answering(AtNoStub, 0.2))
    end

    test "a missing key or a malformed answer is a technical failure" do
      Req.Test.stub(AddresseeNoKeyStub, fn _conn -> flunk("provider must not be called") end)

      assert {:error, {:technical_failure, :missing_credentials}} =
               TypesafeAdapter.decide_addressee(adapter_request(),
                 plug: {Req.Test, AddresseeNoKeyStub}
               )

      Req.Test.stub(AddresseeMalformedStub, fn conn ->
        Req.Test.json(conn, %{"answers" => %{}})
      end)

      assert {:error, {:invalid_response, :missing_answer}} =
               TypesafeAdapter.decide_addressee(adapter_request(),
                 api_key: "ts-test-key",
                 plug: {Req.Test, AddresseeMalformedStub}
               )
    end

    test "logs the decision and the noul without any text" do
      opts = answering(AddresseeLogStub, 0.93)
      level = Logger.level()
      Logger.configure(level: :debug)
      on_exit(fn -> Logger.configure(level: level) end)

      log =
        capture_log([level: :debug], fn ->
          TypesafeAdapter.decide_addressee(adapter_request(), opts)
        end)

      assert log =~ "[TypesafeAdapter] addressee=examiner addressee:examiner=0.930:yes"
      refute log =~ "Blumberg"
    end
  end

  defmodule ScriptedAdapter do
    @behaviour Backend.Stations.JevDecision.Adapter
    @impl true
    def decide_patient(_request), do: {:error, :not_used}
    @impl true
    def decide_rubric(_request), do: {:error, :not_used}
    @impl true
    def decide_addressee(%{latest_learner_turn: %{text: text}}) do
      case text do
        "examiner" -> {:ok, %{addressee: :examiner}}
        "string" -> {:ok, %{"addressee" => "patient"}}
        "undecided" -> {:ok, %{addressee: :undecided}}
        "bogus" -> {:ok, %{addressee: :nobody}}
        "slow" -> Process.sleep(500) && {:ok, %{addressee: :examiner}}
        "crash" -> raise "boom"
      end
    end
  end

  defmodule PatientOnlyAdapter do
    @behaviour Backend.Stations.JevDecision.Adapter
    @impl true
    def decide_patient(_request), do: {:ok, %{status: :verified}}
    @impl true
    def decide_rubric(_request), do: {:error, :not_used}
  end

  defp learner(text), do: %{conversation: [%{role: :learner, text: text}], deadline_ms: 1_000}

  describe "JevDecision.decide_addressee/2" do
    test "returns the adapter's addressee" do
      assert {:ok, :examiner} =
               JevDecision.decide_addressee(learner("examiner"), adapter: ScriptedAdapter)

      assert {:ok, :patient} =
               JevDecision.decide_addressee(learner("string"), adapter: ScriptedAdapter)

      assert {:ok, :undecided} =
               JevDecision.decide_addressee(learner("undecided"), adapter: ScriptedAdapter)
    end

    test "hands the adapter the minimized, trust-labelled request" do
      test_pid = self()

      defmodule CapturingAdapter do
        def decide_addressee(request) do
          send(:persistent_term.get({__MODULE__, :pid}), {:addressee_request, request})
          {:ok, %{addressee: :patient}}
        end
      end

      :persistent_term.put({CapturingAdapter, :pid}, test_pid)
      assert {:ok, :patient} = JevDecision.decide_addressee(request(), adapter: CapturingAdapter)
      assert_received {:addressee_request, adapter_request}

      assert %{seq: 3, role: :student, text: @finding, trust: :untrusted} =
               adapter_request.latest_learner_turn

      assert Enum.map(adapter_request.conversation, & &1.trust) == [
               :untrusted,
               :trusted,
               :untrusted
             ]

      assert is_integer(adapter_request.deadline_at_monotonic_ms)
      refute Map.has_key?(adapter_request, :package)
    end

    test "an unknown addressee is malformed output" do
      assert {:error, :malformed_output} =
               JevDecision.decide_addressee(learner("bogus"), adapter: ScriptedAdapter)
    end

    test "a slow adapter times out and a crash is a technical failure" do
      assert {:error, :timeout} =
               JevDecision.decide_addressee(
                 %{conversation: [%{role: :learner, text: "slow"}], deadline_ms: 50},
                 adapter: ScriptedAdapter
               )

      assert {:error, {:technical_failure, :adapter_crashed}} =
               JevDecision.decide_addressee(learner("crash"), adapter: ScriptedAdapter)
    end

    test "an adapter without the check is unsupported, and the default adapter is disabled" do
      assert {:error, {:technical_failure, :addressee_unsupported}} =
               JevDecision.decide_addressee(learner("x"), adapter: PatientOnlyAdapter)

      assert {:error, {:adapter_disabled, _}} = JevDecision.decide_addressee(learner("x"))
    end

    test "a conversation without a learner turn is an invalid request" do
      assert {:error, {:invalid_request, :missing_learner_turn}} =
               JevDecision.decide_addressee(
                 %{conversation: [%{role: :patient, text: "Oi"}]},
                 adapter: ScriptedAdapter
               )
    end

    test "the default budget is the addressee deadline" do
      assert JevDecision.addressee_deadline_ms() == 1_000
    end
  end
end
