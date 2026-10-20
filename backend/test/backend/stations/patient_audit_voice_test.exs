defmodule Backend.Stations.PatientAuditVoiceTest do
  @moduledoc """
  Issue #307 on voice turns: in `audit` mode the reply (streamed sentence by
  sentence or whole) is spoken once BoundedReply passes, and Jev verifies the
  stored reply after delivery, for audit only. `off` makes no Jev call.
  """
  use ExUnit.Case, async: false

  alias Backend.Stations

  @question "Quando a dor começou?"

  # Streams `:voice_audit_script` piece by piece; `next_reply/2` (the
  # regeneration and the non-streamed path) answers `:voice_audit_whole`.
  defmodule StreamAI do
    @behaviour Backend.Stations.StationAI

    @impl true
    def next_reply(_package, _context) do
      send(Application.fetch_env!(:backend, :voice_audit_pid), :whole_generation)
      {:ok, %{text: Application.fetch_env!(:backend, :voice_audit_whole), used_facts: []}}
    end

    @impl true
    def stream_reply(_package, _context, on_text) do
      pieces = Application.fetch_env!(:backend, :voice_audit_script)
      Enum.each(pieces, on_text)
      {:ok, %{text: Enum.join(pieces)}}
    end
  end

  defmodule SlowJev do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(request) do
      send(
        Application.fetch_env!(:backend, :voice_audit_pid),
        {:jev_patient, request.candidate_text}
      )

      Process.sleep(Application.get_env(:backend, :voice_audit_jev_delay_ms, 0))
      Application.fetch_env!(:backend, :voice_audit_verdict)
    end

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  setup do
    keys = [
      :station_ai_adapter,
      :jev_decision_adapter,
      :patient_verification,
      :voice_audit_pid,
      :voice_audit_script,
      :voice_audit_whole,
      :voice_audit_verdict,
      :voice_audit_jev_delay_ms
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

    Application.put_env(:backend, :station_ai_adapter, StreamAI)
    Application.put_env(:backend, :jev_decision_adapter, SlowJev)
    Application.put_env(:backend, :patient_verification, :audit)
    Application.put_env(:backend, :voice_audit_pid, self())
    Application.put_env(:backend, :voice_audit_script, ["Começou ontem. ", "Ainda dói."])
    Application.put_env(:backend, :voice_audit_whole, "Começou ontem à noite.")
    Application.put_env(:backend, :voice_audit_verdict, {:ok, %{status: :verified}})
    Application.put_env(:backend, :voice_audit_jev_delay_ms, 0)

    session = Stations.create_session(%{audio_consent: true})
    %{session_id: session.session_id}
  end

  defp stream_turn(session_id, turn_id \\ 1) do
    Stations.stream_voice_turn(session_id, turn_id, @question, [], fn {:sentence, event}, acc ->
      {:cont, acc ++ [event.text]}
    end)
  end

  defp timed(fun) do
    started = System.monotonic_time(:millisecond)
    result = fun.()
    {result, System.monotonic_time(:millisecond) - started}
  end

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

  defp patient_texts(session_id) do
    {:ok, session} = Stations.get_session(session_id)
    for %{role: :patient, text: text} <- session.messages, do: text
  end

  describe "streamed voice turns in audit mode" do
    test "a slow Jev does not delay any spoken sentence", %{session_id: id} do
      Application.put_env(:backend, :voice_audit_jev_delay_ms, 5_000)

      {{result, spoken}, elapsed_ms} = timed(fn -> stream_turn(id) end)

      assert {:ok, %{reply_text: "Começou ontem. Ainda dói."}} = result
      assert spoken == ["Começou ontem.", "Ainda dói."]
      assert elapsed_ms < 2_000
      assert patient_texts(id) == ["Começou ontem. Ainda dói."]

      # Jev audits the whole stored reply once, after delivery.
      assert_receive {:jev_patient, "Começou ontem. Ainda dói."}, 1_000
      refute_received {:jev_patient, _}
      assert [%{outcome: :verified, latency_ms: latency}] = await_audits(id, 1)
      assert latency >= 5_000
    end

    test "an undecided Jev never changes the spoken reply", %{session_id: id} do
      Application.put_env(
        :backend,
        :voice_audit_verdict,
        {:ok,
         %{status: :low_confidence, undecided_labels: [%{question: "fact_asked", score: 0.4}]}}
      )

      assert {{:ok, %{reply_text: "Começou ontem. Ainda dói."}}, _spoken} = stream_turn(id)
      refute_received :whole_generation
      assert [%{outcome: :low_confidence}] = await_audits(id, 1)
      assert patient_texts(id) == ["Começou ontem. Ainda dói."]
    end

    test "a BoundedReply rejection of the first sentence regenerates once", %{session_id: id} do
      Application.put_env(:backend, :voice_audit_script, ["Como uma IA, não sei. ", "Fim."])

      assert {{:ok, %{reply_text: "Começou ontem à noite."}}, ["Começou ontem à noite."]} =
               stream_turn(id)

      assert_received :whole_generation
      refute_received :whole_generation
      assert patient_texts(id) == ["Começou ontem à noite."]
      await_audits(id, 1)
    end

    test "a rejection after a spoken sentence keeps only what was spoken", %{session_id: id} do
      Application.put_env(:backend, :voice_audit_script, [
        "Começou ontem. ",
        "Como uma IA, não sei."
      ])

      assert {{:ok, %{reply_text: "Começou ontem."}}, ["Começou ontem."]} = stream_turn(id)
      refute_received :whole_generation
      assert patient_texts(id) == ["Começou ontem."]
      await_audits(id, 1)
    end
  end

  describe "whole voice turns in audit mode" do
    test "a slow Jev does not delay the reply", %{session_id: id} do
      Application.put_env(:backend, :voice_audit_jev_delay_ms, 5_000)

      {result, elapsed_ms} = timed(fn -> Stations.process_voice_turn(id, 1, @question) end)

      assert {:ok, %{reply_text: "Começou ontem à noite."}} = result
      assert elapsed_ms < 2_000
      assert [%{outcome: :verified}] = await_audits(id, 1)
    end
  end

  describe "voice turns in off mode" do
    test "no patient-side Jev call is made", %{session_id: id} do
      Application.put_env(:backend, :patient_verification, :off)

      assert {{:ok, %{reply_text: "Começou ontem. Ainda dói."}}, _spoken} = stream_turn(id)

      assert {:ok, %{reply_text: "Começou ontem à noite."}} =
               Stations.process_voice_turn(id, 2, @question)

      Process.sleep(100)
      refute_received {:jev_patient, _}
      assert {:ok, []} = Stations.patient_audits(id)
    end
  end
end
