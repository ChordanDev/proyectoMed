defmodule Backend.Stations.TurnAddresseeTest do
  @moduledoc """
  Issue #274: each learner turn is classified as addressed to the patient or to
  the examiner before any patient reply is generated. An examiner-addressed turn
  is kept and acknowledged with no generation; an undecided or failed check is
  patient-addressed.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Backend.Stations

  @finding "Ao exame, abdome doloroso em fossa ilíaca direita, Blumberg positivo."
  @question "Quando a dor começou?"
  @reply "A dor começou ontem à noite."

  # Reports every generation to the test process.
  defmodule CountingAI do
    @behaviour Backend.Stations.StationAI

    @impl true
    def next_reply(_package, _context) do
      send(Application.fetch_env!(:backend, :addressee_test_pid), :patient_generation)
      {:ok, %{text: "A dor começou ontem à noite.", used_facts: []}}
    end

    @impl true
    def stream_reply(_package, _context, on_text) do
      send(Application.fetch_env!(:backend, :addressee_test_pid), :patient_generation)
      on_text.("A dor começou ontem à noite.")
      {:ok, %{text: "A dor começou ontem à noite."}}
    end
  end

  # Answers the addressee check from `:addressee_answer` and the patient
  # decision from `:addressee_patient_status`, reporting each call.
  defmodule ScriptedJev do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_addressee(request) do
      send(
        Application.fetch_env!(:backend, :addressee_test_pid),
        {:addressee_check, request.latest_learner_turn.text}
      )

      case Application.fetch_env!(:backend, :addressee_answer) do
        {:error, reason} -> {:error, reason}
        :slow -> Process.sleep(2_000) && {:ok, %{addressee: :examiner}}
        addressee -> {:ok, %{addressee: addressee}}
      end
    end

    @impl true
    def decide_patient(_request) do
      send(Application.fetch_env!(:backend, :addressee_test_pid), :patient_verification)
      {:ok, %{status: Application.get_env(:backend, :addressee_patient_status, :verified)}}
    end

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  setup do
    keys = [
      :station_ai_adapter,
      :jev_decision_adapter,
      :jev_addressee_deadline_ms,
      :addressee_test_pid,
      :addressee_answer,
      :addressee_patient_status
    ]

    previous = Map.new(keys, &{&1, Application.fetch_env(:backend, &1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:backend, key, value)
        {key, :error} -> Application.delete_env(:backend, key)
      end)
    end)

    Application.put_env(:backend, :station_ai_adapter, CountingAI)
    Application.put_env(:backend, :jev_decision_adapter, ScriptedJev)
    Application.put_env(:backend, :addressee_test_pid, self())
    :ok
  end

  defp answer(addressee), do: Application.put_env(:backend, :addressee_answer, addressee)

  defp send_text(session, text) do
    Stations.create_message(session.session_id, %{role: "learner", modality: "text", text: text})
  end

  describe "text turns" do
    test "an examiner-addressed turn is kept and acknowledged with no generation" do
      answer(:examiner)
      session = Stations.create_session(%{audio_consent: false})

      assert {:ok, %{outcome: :examiner_acknowledged, learner_turn: learner_turn}} =
               send_text(session, @finding)

      assert_received {:addressee_check, @finding}
      refute_received :patient_generation
      refute_received :patient_verification

      assert %{role: :learner, modality: :text, text: @finding} = learner_turn
      {:ok, after_turn} = Stations.get_session(session.session_id)
      assert after_turn.messages == [learner_turn]
    end

    for addressee <- [:patient, :undecided] do
      test "a #{addressee} classification generates and verifies the patient reply" do
        answer(unquote(addressee))
        session = Stations.create_session(%{audio_consent: false})

        assert {:ok, %{outcome: :patient_reply, reply_text: @reply}} =
                 send_text(session, @question)

        assert_received :patient_generation
        assert_received :patient_verification
      end
    end

    test "a failed or slow check is patient-addressed" do
      Application.put_env(:backend, :jev_addressee_deadline_ms, 50)

      for failure <- [{:error, :network_error}, :slow] do
        answer(failure)
        session = Stations.create_session(%{audio_consent: false})

        capture_log(fn ->
          assert {:ok, %{outcome: :patient_reply, reply_text: @reply}} =
                   send_text(session, @question)
        end)

        assert_received :patient_generation
      end
    end

    test "a refused patient-addressed reply still keeps the learner turn as a refusal" do
      answer(:patient)
      Application.put_env(:backend, :addressee_patient_status, :semantic_refusal)
      session = Stations.create_session(%{audio_consent: false})

      capture_log(fn ->
        assert {:error, {:refused, :semantic_refusal, %{text: @question}}} =
                 send_text(session, @question)
      end)
    end

    test "logs the decision, the channel and the latency without content" do
      answer(:examiner)
      session = Stations.create_session(%{audio_consent: false})
      level = Logger.level()
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: level) end)

      log = capture_log([level: :info], fn -> send_text(session, @finding) end)

      assert log =~ ~r/\[Stations\] turn_addressee decision=examiner channel=text latency_ms=\d+/
      refute log =~ "Blumberg"
    end
  end

  describe "voice turns" do
    test "an examiner-addressed voice turn is kept with no generation" do
      answer(:examiner)
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, {:kept, %{turn_id: 1, addressee: :examiner, refusal: :examiner_addressed}}} =
               Stations.process_voice_turn(session.session_id, 1, @finding)

      assert_received {:addressee_check, @finding}
      refute_received :patient_generation
      refute_received :patient_verification
      {:ok, stored} = Stations.get_session(session.session_id)
      assert [%{role: :learner, text: @finding}] = stored.messages
    end

    test "an examiner-addressed streamed turn is classified before the stream and hands nothing over" do
      answer(:examiner)
      session = Stations.create_session(%{audio_consent: true})
      sink = fn sentence, acc -> {:cont, [sentence | acc]} end

      assert {{:ok, {:kept, %{addressee: :examiner}}}, []} =
               Stations.stream_voice_turn(session.session_id, 1, @finding, [], sink)

      refute_received :patient_generation
    end

    test "an undecided voice turn streams the patient reply" do
      answer(:undecided)
      session = Stations.create_session(%{audio_consent: true})
      sink = fn {:sentence, %{text: text}}, acc -> {:cont, [text | acc]} end

      assert {{:ok, %{reply_text: @reply}}, [@reply]} =
               Stations.stream_voice_turn(session.session_id, 1, @question, [], sink)

      assert_received :patient_generation
    end

    test "a refused patient-addressed voice turn is kept with addressee patient" do
      answer(:patient)
      Application.put_env(:backend, :addressee_patient_status, :semantic_refusal)
      session = Stations.create_session(%{audio_consent: true})

      capture_log(fn ->
        assert {:ok, {:kept, %{addressee: :patient, refusal: :semantic_refusal}}} =
                 Stations.process_voice_turn(session.session_id, 1, @question)
      end)
    end
  end
end
