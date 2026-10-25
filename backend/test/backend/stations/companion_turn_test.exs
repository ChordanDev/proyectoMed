defmodule Backend.Stations.CompanionTurnTest do
  @moduledoc """
  Issue #341: a turn the generator marks `[ACOMPANHANTE]` is the companion's
  reply on every path (text, voice, streamed voice). It is stored with its
  speaker, shown to the next generation with its marker, checked against the
  companion's own profile and facts, and each streamed sentence names its
  speaker and voice. A single-actor station keeps today's messages and events.
  """
  use ExUnit.Case, async: false

  alias Backend.Stations
  alias Backend.Stations.RubricAssessment.Evidence

  @companion_case Path.expand("fixtures/case_format/companion.md", __DIR__)
  @question "Quando começou a febre?"
  @reply "A febre começou há dois dias."

  defmodule MarkedAI do
    @behaviour Backend.Stations.StationAI

    @impl true
    def next_reply(_package, context) do
      send(Application.fetch_env!(:backend, :companion_turn_test_pid), {:context, context})
      {:ok, %{text: Application.fetch_env!(:backend, :companion_turn_reply), used_facts: []}}
    end

    @impl true
    def stream_reply(_package, _context, on_text) do
      reply = Application.fetch_env!(:backend, :companion_turn_reply)
      on_text.(reply)
      {:ok, %{text: reply}}
    end
  end

  # Reports the package the verification judged the reply against.
  defmodule CapturingJev do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(request) do
      send(Application.fetch_env!(:backend, :companion_turn_test_pid), {:jev, request.package})
      {:ok, %{status: :verified}}
    end

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  setup do
    keys = [
      :station_ai_adapter,
      :jev_decision_adapter,
      :companion_turn_test_pid,
      :companion_turn_reply,
      :patient_verification
    ]

    previous = Map.new(keys, &{&1, Application.fetch_env(:backend, &1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:backend, key, value)
        {key, :error} -> Application.delete_env(:backend, key)
      end)
    end)

    Application.put_env(:backend, :station_ai_adapter, MarkedAI)
    Application.put_env(:backend, :jev_decision_adapter, CapturingJev)
    Application.put_env(:backend, :companion_turn_test_pid, self())
    Application.put_env(:backend, :patient_verification, :off)

    {:ok, package} = @companion_case |> File.read!() |> Stations.parse_case()
    %{package: package}
  end

  defp reply(text), do: Application.put_env(:backend, :companion_turn_reply, text)

  defp session(package, audio_consent \\ true),
    do: Stations.create_session(%{package: package, audio_consent: audio_consent})

  defp send_text(session, text) do
    Stations.create_message(session.session_id, %{role: "learner", modality: "text", text: text})
  end

  defp collect_sink, do: fn {:sentence, event}, acc -> {:cont, acc ++ [event]} end

  describe "a text turn to the companion" do
    test "is the companion's reply, stored with its speaker", %{package: package} do
      reply("[ACOMPANHANTE] " <> @reply)
      session = session(package, false)

      assert {:ok, %{outcome: :patient_reply, reply_text: @reply, speaker: :companion}} =
               send_text(session, @question)

      {:ok, stored} = Stations.get_session(session.session_id)

      assert [%{role: :learner}, %{role: :patient, speaker: :companion, text: @reply}] =
               stored.messages
    end

    test "shows the next generation the companion marker", %{package: package} do
      reply("[ACOMPANHANTE] " <> @reply)
      session = session(package, false)

      {:ok, _} = send_text(session, @question)
      {:ok, _} = send_text(session, "E a temperatura máxima?")

      assert_received {:context, %{conversation: [%{role: :student}]}}

      assert_received {:context,
                       %{
                         conversation: [
                           %{role: :student, text: @question},
                           %{role: :patient, text: "[ACOMPANHANTE] " <> @reply},
                           %{role: :student}
                         ]
                       }}
    end

    test "a patient reply in a companion station names the patient", %{package: package} do
      reply("[PACIENTE] Chora ao ser examinado.")
      session = session(package, false)

      assert {:ok, %{speaker: :patient}} = send_text(session, "Ele chora?")
      {:ok, stored} = Stations.get_session(session.session_id)
      assert [_learner, %{speaker: :patient}] = stored.messages
    end

    test "is verified against the companion's own profile and facts", %{package: package} do
      Application.put_env(:backend, :patient_verification, :blocking)
      reply("[ACOMPANHANTE] " <> @reply)
      session = session(package, false)

      assert {:ok, %{speaker: :companion}} = send_text(session, @question)
      assert_received {:jev, judged}

      assert judged["patient_profile"]["persona"] == "Mãe de Lucas, preocupada e colaborativa."
      fact_contents = Enum.map(judged["revealable_facts"], & &1["content"])
      assert @reply in fact_contents
      refute "Chora ao ser examinado." in fact_contents
    end
  end

  describe "a voice turn to the companion" do
    test "is spoken as the companion's reply", %{package: package} do
      reply("[ACOMPANHANTE] " <> @reply)
      session = session(package)

      assert {:ok, %{reply_text: @reply, speaker: :companion, voice: "feminina-adulta"}} =
               Stations.process_voice_turn(session.session_id, 1, @question)

      {:ok, stored} = Stations.get_session(session.session_id)
      assert [_learner, %{role: :patient, speaker: :companion}] = stored.messages
    end

    test "streams sentences labelled with the companion and its voice", %{package: package} do
      reply("[ACOMPANHANTE] " <> @reply)
      session = session(package)

      assert {{:ok, %{reply_text: @reply}}, [event]} =
               Stations.stream_voice_turn(session.session_id, 1, @question, [], collect_sink())

      assert %{text: @reply, speaker: "companion", voice: "feminina-adulta"} = event

      {:ok, stored} = Stations.get_session(session.session_id)
      assert [_learner, %{role: :patient, speaker: :companion}] = stored.messages
    end

    test "streams a patient reply labelled with the patient's voice", %{package: package} do
      reply("[PACIENTE] Chora ao ser examinado.")
      session = session(package)

      assert {{:ok, _}, [event]} =
               Stations.stream_voice_turn(session.session_id, 1, "Ele chora?", [], collect_sink())

      assert %{speaker: "patient", voice: "infantil"} = event
    end
  end

  describe "a single-actor station" do
    test "keeps its messages, results and sentence events as before #341" do
      reply("[PACIENTE] Meu nome é Ana.")
      text_session = Stations.create_session(%{audio_consent: false})

      assert {:ok, result} = send_text(text_session, "Qual é o seu nome?")
      refute Map.has_key?(result, :speaker)
      {:ok, stored} = Stations.get_session(text_session.session_id)
      refute Enum.any?(stored.messages, &Map.has_key?(&1, :speaker))

      # Unknown without a companion: the text is kept whole, as before.
      reply("[ACOMPANHANTE] Oi.")
      assert {:ok, %{reply_text: "[ACOMPANHANTE] Oi."}} = send_text(text_session, "Oi")

      reply("[PACIENTE] Meu nome é Ana.")
      voice_session = Stations.create_session(%{audio_consent: true})

      assert {{:ok, _}, [event]} =
               Stations.stream_voice_turn(
                 voice_session.session_id,
                 1,
                 "Qual é o seu nome?",
                 [],
                 collect_sink()
               )

      assert Map.keys(event) |> Enum.sort() == [:generation_id, :index, :text, :turn_id]

      assert {:ok, voice_result} =
               Stations.process_voice_turn(voice_session.session_id, 2, "E a sua idade?")

      refute Map.has_key?(voice_result, :speaker)
    end
  end

  describe "grading" do
    test "a question to the companion is the same evidence as one to the patient",
         %{package: package} do
      pool = fn marker ->
        reply(marker <> " " <> @reply)
        session = session(package, false)
        {:ok, _} = send_text(session, @question)
        {:ok, stored} = Stations.get_session(session.session_id)

        stored
        |> Evidence.build(package)
        |> Enum.filter(&(&1.role == :learner))
        |> Enum.map(&Map.delete(&1, :at))
      end

      companion_pool = pool.("[ACOMPANHANTE]")
      assert [%{text: @question}] = companion_pool
      assert companion_pool == pool.("[PACIENTE]")
    end
  end
end
