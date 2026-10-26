defmodule Backend.Stations.VoiceExamModeTest do
  @moduledoc """
  Issue #364: the learner presses the exam button and says the request aloud.
  `arm_exam_mode/1` arms an exam mode for the learner's next utterance; while
  it is armed, the next voice turn goes to `request_impresso/2` (the deterministic
  matcher, request id `voice-exam-<turn_id>`) instead of the patient, and the
  mode disarms after that one utterance, on expiry or on `cancel_exam_mode/1`.
  """
  use Backend.DataCase, async: false

  alias Backend.Stations

  @question "Qual é o seu nome?"
  @lab_request "Solicito hemograma e PCR"
  @lab_impresso "laboratorio-sangue-enzimas"
  @unauthored_request "Solicito uma tomografia de crânio"

  defmodule PatientAI do
    @behaviour Backend.Stations.StationAI

    @impl true
    def next_reply(_package, context) do
      send(Application.fetch_env!(:backend, :exam_mode_test_pid), {:patient_generation, context})
      {:ok, %{text: "[PACIENTE] Meu nome é Ana.", used_facts: []}}
    end

    @impl true
    def stream_reply(_package, context, on_text) do
      send(Application.fetch_env!(:backend, :exam_mode_test_pid), {:patient_generation, context})
      on_text.("[PACIENTE] Meu nome é Ana.")
      {:ok, %{text: "[PACIENTE] Meu nome é Ana."}}
    end
  end

  defmodule ApprovingJev do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request), do: {:ok, %{status: :verified}}

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  setup do
    keys = [:station_ai_adapter, :jev_decision_adapter, :exam_mode_test_pid, :exam_mode_ttl_ms]
    previous = for key <- keys, do: {key, Application.fetch_env(:backend, key)}

    Application.put_env(:backend, :station_ai_adapter, PatientAI)
    Application.put_env(:backend, :jev_decision_adapter, ApprovingJev)
    Application.put_env(:backend, :exam_mode_test_pid, self())

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, value} -> Application.put_env(:backend, key, value)
          :error -> Application.delete_env(:backend, key)
        end
      end
    end)

    %{session: Stations.create_session(%{audio_consent: true})}
  end

  defp collect_sink, do: fn sentence, acc -> {:cont, [sentence | acc]} end

  describe "an armed exam mode" do
    test "routes the next voice turn to the impresso request, never to the patient",
         %{session: %{session_id: id}} do
      assert {:ok, %{expires_at: %DateTime{}}} = Stations.arm_exam_mode(id)

      assert {:ok,
              {:impresso,
               %{
                 turn_id: 1,
                 request_id: "voice-exam-1",
                 decision: "released",
                 newly_released: [%{id: @lab_impresso}],
                 feedback_message: "Impresso liberado: " <> _
               }}} = Stations.process_voice_turn(id, 1, @lab_request)

      refute_received {:patient_generation, _}

      {:ok, stored} = Stations.get_session(id)
      assert stored.messages == []
      assert stored.released_impressos == [@lab_impresso]

      assert [%{request_id: "voice-exam-1", text: @lab_request, decision: :released}] =
               stored.impresso_requests
    end

    test "a streamed voice turn hands no sentence over", %{session: %{session_id: id}} do
      {:ok, _} = Stations.arm_exam_mode(id)

      assert {{:ok, {:impresso, %{turn_id: 1, request_id: "voice-exam-1"}}}, []} =
               Stations.stream_voice_turn(id, 1, @lab_request, [], collect_sink())

      refute_received {:patient_generation, _}
      assert {:ok, %{messages: []}} = Stations.get_session(id)
    end

    test "an exam the station does not author is unavailable, as a typed request",
         %{session: %{session_id: id}} do
      {:ok, _} = Stations.arm_exam_mode(id)

      assert {:ok, {:impresso, %{decision: "unavailable", newly_released: []}}} =
               Stations.process_voice_turn(id, 1, @unauthored_request)

      {:ok, stored} = Stations.get_session(id)
      assert [%{request_id: "voice-exam-1", decision: :unavailable}] = stored.impresso_requests
    end

    test "disarms after one utterance: the next turn goes to the patient",
         %{session: %{session_id: id}} do
      {:ok, _} = Stations.arm_exam_mode(id)
      assert {:ok, {:impresso, _}} = Stations.process_voice_turn(id, 1, @lab_request)

      assert {:ok, %{reply_text: "Meu nome é Ana.", turn_id: 2}} =
               Stations.process_voice_turn(id, 2, @question)

      # The exam request never reaches the patient's context.
      assert_received {:patient_generation, %{conversation: conversation}}
      refute Enum.any?(conversation, &(&1.text == @lab_request))
    end

    test "a retry of the exam turn replays the same result and records one event",
         %{session: %{session_id: id}} do
      {:ok, _} = Stations.arm_exam_mode(id)
      assert {:ok, {:impresso, first}} = Stations.process_voice_turn(id, 1, @lab_request)
      assert {:ok, {:impresso, ^first}} = Stations.process_voice_turn(id, 1, @lab_request)

      {:ok, stored} = Stations.get_session(id)
      assert [%{request_id: "voice-exam-1"}] = stored.impresso_requests
    end

    test "fences the exam turn id, so a fresh worker allocates above it",
         %{session: %{session_id: id}} do
      {:ok, _} = Stations.arm_exam_mode(id)
      assert {:ok, {:impresso, _}} = Stations.process_voice_turn(id, 3, @lab_request)

      assert {:ok, %{last_turn_id: 0, turn_id_floor: 3}} = Stations.voice_worker_context(id)
    end

    test "a stale turn id does not consume the mode", %{session: %{session_id: id}} do
      assert {:ok, %{turn_id: 1}} = Stations.process_voice_turn(id, 1, @question)
      {:ok, _} = Stations.arm_exam_mode(id)

      assert {:ok, :duplicate} = Stations.process_voice_turn(id, 1, @question)

      assert {:ok, {:impresso, %{request_id: "voice-exam-2"}}} =
               Stations.process_voice_turn(id, 2, @lab_request)
    end
  end

  describe "a disarmed exam mode" do
    test "without arming, a spoken exam request releases nothing (#351)",
         %{session: %{session_id: id}} do
      assert {:ok, {:kept, %{addressee: :examiner, exam_request: true}}} =
               Stations.process_voice_turn(id, 1, @lab_request)

      {:ok, stored} = Stations.get_session(id)
      assert stored.released_impressos == []
      assert stored.impresso_requests == []
    end

    test "cancel disarms the mode", %{session: %{session_id: id}} do
      {:ok, _} = Stations.arm_exam_mode(id)
      assert :ok = Stations.cancel_exam_mode(id)

      assert {:ok, {:kept, %{addressee: :examiner, exam_request: true}}} =
               Stations.process_voice_turn(id, 1, @lab_request)

      assert {:ok, %{impresso_requests: []}} = Stations.get_session(id)
    end

    test "an expired mode is disarmed", %{session: %{session_id: id}} do
      Application.put_env(:backend, :exam_mode_ttl_ms, 0)
      {:ok, _} = Stations.arm_exam_mode(id)

      assert {:ok, {:kept, %{addressee: :examiner, exam_request: true}}} =
               Stations.process_voice_turn(id, 1, @lab_request)

      assert {:ok, %{impresso_requests: []}} = Stations.get_session(id)
    end

    test "typed impresso requests are unchanged while armed", %{session: %{session_id: id}} do
      {:ok, _} = Stations.arm_exam_mode(id)

      assert {:ok, %{decision: "released"}} =
               Stations.request_impresso(id, %{"text" => @lab_request, "request_id" => "typed-1"})

      assert {:ok, {:impresso, %{decision: "already_released"}}} =
               Stations.process_voice_turn(id, 1, @lab_request)
    end
  end

  describe "arm_exam_mode/1" do
    test "needs an active session with audio consent" do
      assert {:error, :not_found} = Stations.arm_exam_mode("nope")

      no_consent = Stations.create_session(%{audio_consent: false})
      assert {:error, :no_consent} = Stations.arm_exam_mode(no_consent.session_id)

      completed = Stations.create_session(%{audio_consent: true})
      {:ok, _} = Stations.finish_session(completed.session_id)
      assert {:error, :completed} = Stations.arm_exam_mode(completed.session_id)
    end

    test "expires after :exam_mode_ttl_ms", %{session: %{session_id: id}} do
      Application.put_env(:backend, :exam_mode_ttl_ms, 20_000)
      before = DateTime.utc_now()
      {:ok, %{expires_at: expires_at}} = Stations.arm_exam_mode(id)
      assert DateTime.diff(expires_at, before, :millisecond) in 19_000..21_000
    end
  end
end
