defmodule Backend.Stations.VoiceTurnTimingTest do
  @moduledoc """
  Issue #313: every streamed voice turn logs one content-free timing line with
  the per-stage marks (turn start, first model token, addressee marker, first
  text handed to the worker), so sentence and token modes can be compared.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Backend.Stations

  @question "Quando a dor começou?"

  defmodule StreamAI do
    @behaviour Backend.Stations.StationAI

    @impl true
    def next_reply(_package, _context),
      do: {:ok, %{text: "[PACIENTE] Começou ontem à noite.", used_facts: []}}

    @impl true
    def stream_reply(_package, _context, on_text) do
      pieces = Application.fetch_env!(:backend, :voice_timing_script)
      Enum.each(pieces, on_text)
      {:ok, %{text: Enum.join(pieces)}}
    end
  end

  setup do
    keys = [:station_ai_adapter, :patient_verification, :voice_timing_script]
    previous = Map.new(keys, &{&1, Application.fetch_env(:backend, &1)})
    level = Logger.level()

    on_exit(fn ->
      Logger.configure(level: level)

      for {key, value} <- previous do
        case value do
          {:ok, v} -> Application.put_env(:backend, key, v)
          :error -> Application.delete_env(:backend, key)
        end
      end
    end)

    Logger.configure(level: :info)
    Application.put_env(:backend, :station_ai_adapter, StreamAI)
    Application.put_env(:backend, :patient_verification, :off)

    session = Stations.create_session(%{audio_consent: true})
    %{session_id: session.session_id}
  end

  defp stream_turn(session_id) do
    Stations.stream_voice_turn(session_id, 1, @question, [], fn {:sentence, event}, acc ->
      {:cont, acc ++ [event.text]}
    end)
  end

  test "a patient turn logs every stage mark and no text", %{session_id: id} do
    Application.put_env(:backend, :voice_timing_script, [
      "[PACIENTE] ",
      "Começou ontem. ",
      "Ainda dói."
    ])

    log =
      capture_log([level: :info], fn ->
        assert {{:ok, %{reply_text: "Começou ontem. Ainda dói."}}, _spoken} = stream_turn(id)
      end)

    assert log =~
             ~r/\[Stations\] voice_turn_timing mode=sentence first_token_ms=\d+ marker_ms=\d+ first_text_ms=\d+ total_ms=\d+ outcome=committed/

    refute log =~ "Começou"
    refute log =~ "Quando"
  end

  test "an examiner turn logs the marker and no first text", %{session_id: id} do
    Application.put_env(:backend, :voice_timing_script, ["[EXAMINADOR]"])

    log =
      capture_log([level: :info], fn ->
        assert {{:ok, {:kept, %{addressee: :examiner}}}, []} = stream_turn(id)
      end)

    assert log =~
             ~r/voice_turn_timing mode=sentence first_token_ms=\d+ marker_ms=\d+ first_text_ms=none total_ms=\d+ outcome=examiner/
  end
end
