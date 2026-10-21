defmodule Backend.Stations.PatientAuditVerificationTest do
  @moduledoc """
  Issue #307: in `audit` mode the patient reply is delivered once the
  deterministic BoundedReply check passes, and Jev verifies it after delivery,
  for audit only. In `off` mode no patient-side Jev call is made.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Backend.Stations

  @reply "A dor começou ontem à noite, doutor."
  @question "Quando a dor começou?"

  # Answers every generation with the next text of `:audit_test_replies`
  # (the last one repeats) and reports each generation to the test.
  defmodule ScriptedAI do
    @behaviour Backend.Stations.StationAI

    @impl true
    def next_reply(_package, context) do
      send(Application.fetch_env!(:backend, :audit_test_pid), {:generation, context})

      Agent.get_and_update(:audit_test_replies, fn
        [last] -> {last, [last]}
        [next | rest] -> {next, rest}
      end)
      |> then(&{:ok, %{text: &1, used_facts: []}})
    end
  end

  # A Jev that answers `:audit_test_verdict` after `:audit_test_jev_delay_ms`,
  # reporting each request to the test. It never decides the addressee, so every
  # turn is patient-addressed.
  defmodule SlowJev do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(request) do
      test_pid = Application.fetch_env!(:backend, :audit_test_pid)
      send(test_pid, {:jev_patient, request.candidate_text})
      Process.sleep(Application.get_env(:backend, :audit_test_jev_delay_ms, 0))
      result = Application.fetch_env!(:backend, :audit_test_verdict)
      send(test_pid, {:jev_answered, request.candidate_text})
      result
    end

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  setup do
    keys = [
      :station_ai_adapter,
      :jev_decision_adapter,
      :patient_verification,
      :audit_test_pid,
      :audit_test_verdict,
      :audit_test_jev_delay_ms
    ]

    previous = Map.new(keys, &{&1, Application.fetch_env(:backend, &1)})

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, v} -> Application.put_env(:backend, key, v)
          :error -> Application.delete_env(:backend, key)
        end
      end
    end)

    Application.put_env(:backend, :station_ai_adapter, ScriptedAI)
    Application.put_env(:backend, :jev_decision_adapter, SlowJev)
    Application.put_env(:backend, :patient_verification, :audit)
    Application.put_env(:backend, :audit_test_pid, self())
    Application.put_env(:backend, :audit_test_verdict, {:ok, %{status: :verified}})
    Application.put_env(:backend, :audit_test_jev_delay_ms, 0)

    start_supervised!(%{
      id: :audit_test_replies,
      start: {Agent, :start_link, [fn -> [@reply] end, [name: :audit_test_replies]]}
    })

    session = Stations.create_session(%{})
    %{session_id: session.session_id}
  end

  defp replies(texts), do: Agent.update(:audit_test_replies, fn _ -> texts end)

  defp timed(fun) do
    started = System.monotonic_time(:millisecond)
    result = fun.()
    {result, System.monotonic_time(:millisecond) - started}
  end

  # Waits until the session holds `count` patient audits.
  defp await_audits(session_id, count, timeout_ms \\ 8_000) do
    {:ok, audits} = Stations.patient_audits(session_id)

    cond do
      length(audits) >= count ->
        audits

      timeout_ms <= 0 ->
        flunk("expected #{count} audits, got #{length(audits)}")

      true ->
        Process.sleep(20)
        await_audits(session_id, count, timeout_ms - 20)
    end
  end

  defp patient_messages(session_id) do
    {:ok, session} = Stations.get_session(session_id)
    for %{role: :patient} = message <- session.messages, do: message
  end

  describe "text turns in audit mode" do
    test "a slow Jev does not delay the delivered reply", %{session_id: id} do
      Application.put_env(:backend, :audit_test_jev_delay_ms, 5_000)

      {result, elapsed_ms} = timed(fn -> Stations.create_message(id, %{text: @question}) end)

      assert {:ok, %{outcome: :patient_reply, reply_text: @reply}} = result
      assert elapsed_ms < 2_000
      assert [%{text: @reply}] = patient_messages(id)

      # Jev still verifies the delivered reply, after delivery.
      assert_receive {:jev_patient, @reply}, 1_000
      assert [%{outcome: :verified, latency_ms: latency}] = await_audits(id, 1)
      assert latency >= 5_000
    end

    test "an undecided or refusing Jev never changes the delivered reply", %{session_id: id} do
      for {verdict, n} <-
            Enum.with_index(
              [
                %{
                  status: :low_confidence,
                  undecided_labels: [%{question: "fact_asked", score: 0.4}]
                },
                %{status: :semantic_refusal, unasked_fact_ids: ["onset"]}
              ],
              1
            ) do
        Application.put_env(:backend, :audit_test_verdict, {:ok, verdict})
        {:ok, %{reply_text: @reply}} = Stations.create_message(id, %{text: @question})
        await_audits(id, n)
      end

      assert [%{text: @reply}, %{text: @reply}] = patient_messages(id)
      # The only generations are the two first candidates: nothing regenerates.
      assert_received {:generation, _}
      assert_received {:generation, _}
      refute_received {:generation, _}

      audits = await_audits(id, 2)
      assert Enum.map(audits, & &1.outcome) == [:low_confidence, :semantic_refusal]
    end

    test "the audit verdict's facts become the message's verified facts", %{session_id: id} do
      Application.put_env(
        :backend,
        :audit_test_verdict,
        {:ok, %{status: :verified, used_fact_ids: ["onset"]}}
      )

      {:ok, _} = Stations.create_message(id, %{text: @question})
      await_audits(id, 1)

      assert [%{verified_fact_ids: ["onset"]}] = patient_messages(id)
      {:ok, session} = Stations.get_session(id)
      assert Backend.Stations.Conversation.disclosed_fact_ids(session) == ["onset"]
    end

    test "the audit logs outcome, unclear labels and latency but no text", %{session_id: id} do
      Application.put_env(
        :backend,
        :audit_test_verdict,
        {:ok,
         %{
           status: :low_confidence,
           undecided_labels: [
             %{question: "risk:speaks_out_of_role", score: 0.67},
             %{question: "fact_stated", fact_id: "onset", score: 0.5}
           ]
         }}
      )

      level = Logger.level()
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: level) end)

      log =
        capture_log([level: :info], fn ->
          {:ok, _} = Stations.create_message(id, %{text: @question})
          await_audits(id, 1)
        end)

      assert log =~ "[PatientVerification] audit outcome=low_confidence"
      assert log =~ "unclear=risk:speaks_out_of_role,fact_stated:onset"
      assert log =~ "latency_ms="
      refute log =~ @reply
      refute log =~ @question

      assert [%{unclear_labels: ["risk:speaks_out_of_role", "fact_stated:onset"]}] =
               await_audits(id, 1)
    end

    test "a Jev failure is audited as an error and the reply stands", %{session_id: id} do
      Application.put_env(:backend, :audit_test_verdict, {:error, :upstream_error})

      assert {:ok, %{reply_text: @reply}} = Stations.create_message(id, %{text: @question})
      assert [%{outcome: :error}] = await_audits(id, 1)
    end

    test "a BoundedReply rejection regenerates once and delivers the regeneration",
         %{session_id: id} do
      replies(["Como uma IA, não posso ajudar.", @reply])

      assert {:ok, %{reply_text: @reply}} = Stations.create_message(id, %{text: @question})
      assert_received {:generation, _}
      assert_received {:generation, _}
      refute_received {:generation, _}
      # Only the delivered regeneration is audited.
      assert_receive {:jev_patient, @reply}, 1_000
      refute_received {:jev_patient, "Como uma IA" <> _}
      await_audits(id, 1)
    end

    test "a regeneration BoundedReply also rejects keeps the learner turn", %{session_id: id} do
      replies(["Como uma IA, não posso ajudar."])

      assert {:error, {:refused, :bounded_reply, learner_turn}} =
               Stations.create_message(id, %{text: @question})

      assert learner_turn.text == @question
      assert patient_messages(id) == []
      refute_received {:jev_patient, _}
    end
  end

  describe "text turns in off mode" do
    setup do
      Application.put_env(:backend, :patient_verification, :off)
      :ok
    end

    test "the reply is delivered without any patient-side Jev call", %{session_id: id} do
      assert {:ok, %{reply_text: @reply}} = Stations.create_message(id, %{text: @question})
      Process.sleep(100)
      refute_received {:jev_patient, _}
      assert {:ok, []} = Stations.patient_audits(id)
    end
  end
end
