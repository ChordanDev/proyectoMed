defmodule Backend.Stations.AddresseeMarkerTurnTest do
  @moduledoc """
  Issue #309: the patient generator decides the addressee in the same call, by
  starting its reply with `[PACIENTE]` or `[EXAMINADOR]`. The marker is parsed
  before any text reaches the learner, the client or TTS, and never shows.

  Issue #351: a dialogue turn never releases an impresso nor records an
  impresso request; only `request_impresso/2` does. An examiner-addressed turn
  carries a display-only `exam_request` flag instead.
  """
  use ExUnit.Case, async: false

  alias Backend.Stations

  import ExUnit.CaptureLog

  @question "Qual é o seu nome?"
  @reply "Meu nome é Ana."
  @finding "Ao exame, abdome doloroso em fossa ilíaca direita, Blumberg positivo."
  @lab_request "Solicito hemograma e PCR"
  @lab_impresso "laboratorio-sangue-enzimas"

  # Replies with `:marker_turn_reply`, whole or in `:marker_turn_pieces`,
  # reporting each generation to the test process.
  defmodule MarkedAI do
    @behaviour Backend.Stations.StationAI

    @impl true
    def next_reply(_package, context) do
      send(Application.fetch_env!(:backend, :marker_turn_test_pid), :patient_generation)
      send(Application.fetch_env!(:backend, :marker_turn_test_pid), {:context, context})
      {:ok, %{text: Application.fetch_env!(:backend, :marker_turn_reply), used_facts: []}}
    end

    @impl true
    def stream_reply(_package, _context, on_text) do
      send(Application.fetch_env!(:backend, :marker_turn_test_pid), :patient_generation)
      reply = Application.fetch_env!(:backend, :marker_turn_reply)
      Enum.each(Application.get_env(:backend, :marker_turn_pieces, [reply]), on_text)
      Application.get_env(:backend, :marker_turn_stream_result, {:ok, %{text: reply}})
    end
  end

  # Verifies every patient reply, and reports any addressee request: since
  # #309 none is ever made.
  defmodule ApprovingJev do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request) do
      send(Application.fetch_env!(:backend, :marker_turn_test_pid), :patient_verification)
      {:ok, %{status: :verified}}
    end

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}

    # No longer a Jev callback (#309); defined to catch any stray request.
    def decide_addressee(_request) do
      send(Application.fetch_env!(:backend, :marker_turn_test_pid), :addressee_check)
      {:ok, %{addressee: :patient}}
    end
  end

  defmodule RefusingJev do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request), do: {:ok, %{status: :semantic_refusal}}

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  setup do
    keys = [
      :station_ai_adapter,
      :jev_decision_adapter,
      :marker_turn_test_pid,
      :marker_turn_reply,
      :marker_turn_pieces,
      :marker_turn_stream_result
    ]

    previous = Map.new(keys, &{&1, Application.fetch_env(:backend, &1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:backend, key, value)
        {key, :error} -> Application.delete_env(:backend, key)
      end)
    end)

    Application.put_env(:backend, :station_ai_adapter, MarkedAI)
    Application.put_env(:backend, :jev_decision_adapter, ApprovingJev)
    Application.put_env(:backend, :marker_turn_test_pid, self())
    :ok
  end

  defp reply(text, pieces \\ nil) do
    Application.put_env(:backend, :marker_turn_reply, text)

    if pieces,
      do: Application.put_env(:backend, :marker_turn_pieces, pieces),
      else: Application.delete_env(:backend, :marker_turn_pieces)
  end

  defp send_text(session, text) do
    Stations.create_message(session.session_id, %{role: "learner", modality: "text", text: text})
  end

  defp collect_sink, do: fn {:sentence, %{text: text}}, acc -> {:cont, acc ++ [text]} end

  describe "a patient marker" do
    test "is stripped from a text reply before the client and the transcript" do
      reply("[PACIENTE] " <> @reply)
      session = Stations.create_session(%{audio_consent: false})

      assert {:ok, %{outcome: :patient_reply, reply_text: @reply}} = send_text(session, @question)

      {:ok, stored} = Stations.get_session(session.session_id)
      assert [%{role: :learner}, %{role: :patient, text: @reply}] = stored.messages
    end

    test "is shown on the earlier patient replies the next generation reads" do
      reply("[PACIENTE] " <> @reply)
      session = Stations.create_session(%{audio_consent: false})

      {:ok, %{outcome: :patient_reply}} = send_text(session, @question)
      {:ok, %{outcome: :patient_reply}} = send_text(session, "Quantos anos o senhor tem?")

      assert_received {:context, %{conversation: [%{role: :student, text: @question}]}}

      # The model keeps the marker when its own earlier replies show it (#309
      # live check: without it, Haiku dropped the marker from the third turn).
      assert_received {:context,
                       %{
                         conversation: [
                           %{role: :student, text: @question},
                           %{role: :patient, text: "[PACIENTE] " <> @reply},
                           %{role: :student, text: "Quantos anos o senhor tem?"}
                         ]
                       }}

      {:ok, stored} = Stations.get_session(session.session_id)
      refute Enum.any?(stored.messages, &(&1.text =~ "[PACIENTE]"))
    end

    test "is stripped from a voice reply before TTS" do
      reply("[PACIENTE] " <> @reply)
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, %{reply_text: @reply}} =
               Stations.process_voice_turn(session.session_id, 1, @question)
    end

    test "split across streamed pieces never reaches a spoken sentence" do
      reply("[PACIENTE] " <> @reply, ["[PACI", "ENTE]", " Meu nome", " é Ana."])
      session = Stations.create_session(%{audio_consent: true})

      assert {{:ok, %{reply_text: @reply}}, [@reply]} =
               Stations.stream_voice_turn(session.session_id, 1, @question, [], collect_sink())

      {:ok, stored} = Stations.get_session(session.session_id)
      assert [%{role: :learner}, %{role: :patient, text: @reply}] = stored.messages
    end
  end

  defp info_log(fun) do
    level = Logger.level()
    Logger.configure(level: :info)

    try do
      capture_log([level: :info], fun)
    after
      Logger.configure(level: level)
    end
  end

  describe "text turns" do
    test "an examiner marker keeps the learner turn with no patient text and no verification" do
      reply("[EXAMINADOR]")
      session = Stations.create_session(%{audio_consent: false})

      assert {:ok,
              %{
                outcome: :examiner_acknowledged,
                reply_text: nil,
                learner_turn: learner_turn,
                newly_released: [],
                exam_request: false
              }} = send_text(session, @finding)

      assert_received :patient_generation
      refute_received :patient_verification
      assert %{role: :learner, text: @finding} = learner_turn
      {:ok, stored} = Stations.get_session(session.session_id)
      assert stored.messages == [learner_turn]
      assert stored.impresso_requests == []
    end

    test "an authored impresso in the learner text is an exam request that releases nothing (#351)" do
      reply("[PACIENTE] " <> @reply)
      session = Stations.create_session(%{audio_consent: false})

      assert {:ok,
              %{
                outcome: :examiner_acknowledged,
                reply_text: nil,
                learner_turn: %{role: :learner, modality: :text, text: @lab_request},
                newly_released: [],
                exam_request: true
              }} = send_text(session, @lab_request)

      refute_received :patient_generation
      {:ok, stored} = Stations.get_session(session.session_id)
      assert stored.released_impressos == []
      assert stored.impresso_requests == []
    end

    test "an exam marker acknowledges an exam request and releases nothing (#351)" do
      reply("[EXAMINADOR:EXAME]")
      session = Stations.create_session(%{audio_consent: false})

      log =
        info_log(fn ->
          assert {:ok,
                  %{
                    outcome: :examiner_acknowledged,
                    reply_text: nil,
                    newly_released: [],
                    exam_request: true
                  }} = send_text(session, "Solicito uma tomografia de crânio")
        end)

      assert log =~ "turn_addressee decision=examiner source=exam_marker channel=text"
      assert_received :patient_generation
      refute_received :patient_verification
      {:ok, stored} = Stations.get_session(session.session_id)
      assert [%{role: :learner, text: "Solicito uma tomografia de crânio"}] = stored.messages
      refute Enum.any?(stored.messages, &(&1.text =~ "EXAMINADOR"))
      assert stored.released_impressos == []
      assert stored.impresso_requests == []
    end

    test "a patient reply never carries an exam request (#351)" do
      reply("[PACIENTE] " <> @reply)
      session = Stations.create_session(%{audio_consent: false})

      assert {:ok, %{outcome: :patient_reply} = result} =
               send_text(session, "O senhor já fez tomografia?")

      refute Map.get(result, :exam_request)
    end

    test "the impresso route still releases an exam the dialogue already named (#351)" do
      reply("[PACIENTE] " <> @reply)
      session = Stations.create_session(%{audio_consent: false})

      {:ok, %{outcome: :examiner_acknowledged, newly_released: []}} =
        send_text(session, @lab_request)

      assert {:ok, %{decision: "released", newly_released: [%{id: @lab_impresso}]}} =
               Stations.request_impresso(session.session_id, %{"text" => @lab_request})

      {:ok, stored} = Stations.get_session(session.session_id)
      assert stored.released_impressos == [@lab_impresso]
      assert [%{text: @lab_request, decision: :released}] = stored.impresso_requests
    end

    test "an exam named only to decline it goes to the model and releases nothing (#305)" do
      reply("[EXAMINADOR]")
      session = Stations.create_session(%{audio_consent: false})

      assert {:ok, %{outcome: :examiner_acknowledged, newly_released: [], exam_request: false}} =
               send_text(session, "Não preciso do ECG")

      assert_received :patient_generation
      {:ok, stored} = Stations.get_session(session.session_id)
      assert stored.impresso_requests == []
    end

    test "a missing marker is patient-addressed and logged without content" do
      reply(@reply)
      session = Stations.create_session(%{audio_consent: false})

      log =
        info_log(fn ->
          assert {:ok, %{outcome: :patient_reply, reply_text: @reply}} =
                   send_text(session, @question)
        end)

      assert log =~
               ~r/\[Stations\] turn_addressee decision=patient source=missing_marker channel=text latency_ms=\d+/

      refute log =~ "Ana"
    end

    test "each decision logs its source and channel" do
      session = Stations.create_session(%{audio_consent: false})

      log =
        info_log(fn ->
          reply("[EXAMINADOR]")
          send_text(session, @finding)
          reply("[PACIENTE] " <> @reply)
          send_text(session, @question)
          send_text(session, @lab_request)
        end)

      assert log =~ "turn_addressee decision=examiner source=marker channel=text"
      assert log =~ "turn_addressee decision=patient source=marker channel=text"
      assert log =~ "turn_addressee decision=examiner source=impresso channel=text"
      refute log =~ "Blumberg"
    end

    test "no Jev addressee request is made" do
      session = Stations.create_session(%{audio_consent: false})

      for marked <- ["[PACIENTE] " <> @reply, "[EXAMINADOR]", @reply] do
        reply(marked)
        send_text(session, @question)
      end

      refute_received :addressee_check
    end
  end

  describe "non-streamed voice turns" do
    test "an examiner marker keeps the turn with nothing verified or spoken" do
      reply("[EXAMINADOR]")
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok,
              {:kept,
               %{
                 turn_id: 1,
                 addressee: :examiner,
                 refusal: :examiner_addressed,
                 exam_request: false
               }}} = Stations.process_voice_turn(session.session_id, 1, @finding)

      refute_received :patient_verification
      refute_received :addressee_check
      {:ok, stored} = Stations.get_session(session.session_id)
      assert [%{role: :learner, text: @finding}] = stored.messages
    end

    test "an authored impresso is an exam request that releases nothing (#351)" do
      reply("[PACIENTE] " <> @reply)
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, {:kept, %{addressee: :examiner, exam_request: true}}} =
               Stations.process_voice_turn(session.session_id, 1, @lab_request)

      refute_received :patient_generation
      {:ok, stored} = Stations.get_session(session.session_id)
      assert [%{role: :learner, modality: :voice, text: @lab_request}] = stored.messages
      assert stored.released_impressos == []
      refute Enum.any?(stored.impresso_requests, &(&1.request_id == "voice-turn-1"))
      assert stored.impresso_requests == []
    end

    test "an exam marker flags the kept turn as an exam request (#351)" do
      reply("[EXAMINADOR:EXAME]")
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, {:kept, %{addressee: :examiner, exam_request: true}}} =
               Stations.process_voice_turn(session.session_id, 1, "Quero ver a tomografia")

      {:ok, stored} = Stations.get_session(session.session_id)
      assert stored.released_impressos == []
      assert stored.impresso_requests == []
    end

    test "a missing marker is patient-addressed" do
      reply(@reply)
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, %{reply_text: @reply}} =
               Stations.process_voice_turn(session.session_id, 1, @question)

      refute_received :addressee_check
    end
  end

  describe "streamed voice turns" do
    test "an examiner marker stops the reply with nothing verified, spoken or stored" do
      reply("[EXAMINADOR] Anotado.", ["[EXAMIN", "ADOR]", " Anotado."])
      session = Stations.create_session(%{audio_consent: true})

      log =
        info_log(fn ->
          assert {{:ok,
                   {:kept,
                    %{addressee: :examiner, refusal: :examiner_addressed, exam_request: false}}},
                  []} =
                   Stations.stream_voice_turn(session.session_id, 1, @finding, [], collect_sink())
        end)

      assert_received :patient_generation
      refute_received :patient_verification
      refute_received :addressee_check
      refute log =~ "voice_sentence"

      assert log =~
               ~r/turn_addressee decision=examiner source=marker channel=voice latency_ms=\d+/

      {:ok, stored} = Stations.get_session(session.session_id)
      assert [%{role: :learner, text: @finding} = learner] = stored.messages
      refute Map.get(learner, :verified_fact_ids)
    end

    test "an examiner marker wins over a generation that failed after it" do
      reply("[EXAMINADOR]")
      Application.put_env(:backend, :marker_turn_stream_result, {:error, :network_error})
      session = Stations.create_session(%{audio_consent: true})

      assert {{:ok, {:kept, %{addressee: :examiner}}}, []} =
               Stations.stream_voice_turn(session.session_id, 1, @finding, [], collect_sink())
    end

    test "an authored impresso is an exam request that releases nothing (#351)" do
      reply("[PACIENTE] " <> @reply)
      session = Stations.create_session(%{audio_consent: true})

      assert {{:ok, {:kept, %{addressee: :examiner, exam_request: true}}}, []} =
               Stations.stream_voice_turn(session.session_id, 1, @lab_request, [], collect_sink())

      refute_received :patient_generation

      assert {:ok, %{released_impressos: []}} = Stations.list_impressos(session.session_id)
      {:ok, stored} = Stations.get_session(session.session_id)
      assert stored.impresso_requests == []
    end

    test "a streamed exam marker flags the kept turn and speaks nothing (#351)" do
      reply("[EXAMINADOR:EXAME] Anotado.", ["[EXAMINADOR:", "EXAME]", " Anotado."])
      session = Stations.create_session(%{audio_consent: true})

      assert {{:ok, {:kept, %{addressee: :examiner, exam_request: true}}}, []} =
               Stations.stream_voice_turn(
                 session.session_id,
                 1,
                 "Quero ver a tomografia",
                 [],
                 collect_sink()
               )

      {:ok, stored} = Stations.get_session(session.session_id)
      assert [%{role: :learner, text: "Quero ver a tomografia"}] = stored.messages
      assert stored.impresso_requests == []
    end

    test "a missing marker streams the patient reply" do
      reply(@reply, ["Meu nome", " é Ana."])
      session = Stations.create_session(%{audio_consent: true})

      log =
        info_log(fn ->
          assert {{:ok, %{reply_text: @reply}}, [@reply]} =
                   Stations.stream_voice_turn(
                     session.session_id,
                     1,
                     @question,
                     [],
                     collect_sink()
                   )
        end)

      assert log =~ "turn_addressee decision=patient source=missing_marker channel=voice"
      refute_received :addressee_check
    end

    test "a refused patient reply is kept with addressee patient" do
      reply("[PACIENTE] " <> @reply)
      Application.put_env(:backend, :jev_decision_adapter, RefusingJev)
      session = Stations.create_session(%{audio_consent: true})

      capture_log(fn ->
        assert {{:ok, {:kept, %{addressee: :patient, refusal: :semantic_refusal}}}, []} =
                 Stations.stream_voice_turn(session.session_id, 1, @question, [], collect_sink())
      end)
    end
  end

  # Issue #351 (superseding the dialogue release of #302): only the impresso
  # route releases and records; #305's negation still holds there.
  describe "impressos requested from the examiner" do
    test "an examiner voice turn declining an exam releases, records and credits nothing" do
      reply("[EXAMINADOR]")
      session = Stations.create_session(%{audio_consent: true})

      assert {:ok, {:kept, %{addressee: :examiner}}} =
               Stations.process_voice_turn(session.session_id, 1, "Não preciso do ECG")

      {:ok, stored} = Stations.get_session(session.session_id)
      assert stored.released_impressos == []
      assert stored.impresso_requests == []

      package =
        Map.put(Stations.get_active_package(), "rubric", [
          %{
            "id" => "requests-ecg",
            "description" => "Requests the ECG.",
            "evidence_questions" => [],
            "practice_recommendation" => "Ask for the ECG.",
            "weight" => 1,
            "impresso_ids" => ["laudo-eletrocardiograma"]
          }
        ])

      [criterion] = Backend.Evaluator.evaluate(package, stored).criteria
      refute criterion.status == :met
      assert for(%{role: :impresso} = evidence <- criterion.evidence, do: evidence) == []
    end

    test "a modal request declining every exam it names is unavailable" do
      session = Stations.create_session(%{audio_consent: false})

      assert {:ok, %{decision: "unavailable", newly_released: []}} =
               Stations.request_impresso(session.session_id, %{"text" => "Sem ECG por enquanto"})
    end

    test "an exam asked only in the dialogue earns no credit until the impresso route is used" do
      reply("[EXAMINADOR]")
      spoken = Stations.create_session(%{audio_consent: true})
      modal = Stations.create_session(%{audio_consent: false})

      {:ok, _kept} = Stations.process_voice_turn(spoken.session_id, 1, @lab_request)
      {:ok, _released} = Stations.request_impresso(modal.session_id, %{"text" => @lab_request})

      package =
        Map.put(Stations.get_active_package(), "rubric", [
          %{
            "id" => "requests-labs",
            "description" => "Requests the laboratory exams.",
            "evidence_questions" => [],
            "practice_recommendation" => "Ask for the laboratory exams.",
            "weight" => 1,
            "impresso_ids" => [@lab_impresso]
          }
        ])

      [spoken_criterion, modal_criterion] =
        for session <- [spoken, modal] do
          {:ok, stored} = Stations.get_session(session.session_id)
          [criterion] = Backend.Evaluator.evaluate(package, stored).criteria
          criterion
        end

      refute spoken_criterion.status == :met
      assert modal_criterion.status == :met
      assert for(%{role: :impresso} = evidence <- spoken_criterion.evidence, do: evidence) == []

      # The same session meets it once the exam is requested through the route.
      {:ok, _released} = Stations.request_impresso(spoken.session_id, %{"text" => @lab_request})
      {:ok, stored} = Stations.get_session(spoken.session_id)
      [spoken_criterion] = Backend.Evaluator.evaluate(package, stored).criteria
      assert spoken_criterion.status == :met

      impresso_evidence = fn criterion ->
        for %{role: :impresso, text: text} <- criterion.evidence,
            do: String.replace(text, ~r/\(request .*\)/, "")
      end

      assert impresso_evidence.(spoken_criterion) == ["impresso:#{@lab_impresso} "]
      assert impresso_evidence.(spoken_criterion) == impresso_evidence.(modal_criterion)
    end
  end
end
