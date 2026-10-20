defmodule Backend.Stations.AddresseeMarkerTurnTest do
  @moduledoc """
  Issue #309: the patient generator decides the addressee in the same call, by
  starting its reply with `[PACIENTE]` or `[EXAMINADOR]`. The marker is parsed
  before any text reaches the learner, the client or TTS, and never shows.
  """
  use ExUnit.Case, async: false

  alias Backend.Stations

  @question "Qual é o seu nome?"
  @reply "Meu nome é Ana."

  # Replies with `:marker_turn_reply`, whole or in `:marker_turn_pieces`,
  # reporting each generation to the test process.
  defmodule MarkedAI do
    @behaviour Backend.Stations.StationAI

    @impl true
    def next_reply(_package, _context) do
      send(Application.fetch_env!(:backend, :marker_turn_test_pid), :patient_generation)
      {:ok, %{text: Application.fetch_env!(:backend, :marker_turn_reply), used_facts: []}}
    end

    @impl true
    def stream_reply(_package, _context, on_text) do
      send(Application.fetch_env!(:backend, :marker_turn_test_pid), :patient_generation)
      reply = Application.fetch_env!(:backend, :marker_turn_reply)
      Enum.each(Application.get_env(:backend, :marker_turn_pieces, [reply]), on_text)
      {:ok, %{text: reply}}
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

    @impl true
    def decide_addressee(_request) do
      send(Application.fetch_env!(:backend, :marker_turn_test_pid), :addressee_check)
      {:ok, %{addressee: :patient}}
    end
  end

  setup do
    keys = [
      :station_ai_adapter,
      :jev_decision_adapter,
      :marker_turn_test_pid,
      :marker_turn_reply,
      :marker_turn_pieces
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
end
