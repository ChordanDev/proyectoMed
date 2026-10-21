defmodule Backend.Stations.StationAI.SpeechDeltasTest do
  @moduledoc """
  Issue #313: the speakable text of a patient reply still being generated,
  handed to the voice provider word by word.
  """
  use ExUnit.Case, async: false

  alias Backend.Stations.StationAI.SpeechDeltas

  # Feeds `pieces` one at a time and returns the deltas, then the final one.
  defp deltas(pieces) do
    {deltas, spoken, raw} =
      Enum.reduce(pieces, {[], "", ""}, fn piece, {deltas, spoken, raw} ->
        raw = raw <> piece

        case SpeechDeltas.take(spoken, SpeechDeltas.settled(raw, false)) do
          {:delta, delta, spoken} -> {deltas ++ [delta], spoken, raw}
          :none -> {deltas, spoken, raw}
        end
      end)

    case SpeechDeltas.take(spoken, SpeechDeltas.settled(raw, true)) do
      {:delta, delta, _spoken} -> deltas ++ [{:final, delta}]
      :none -> deltas
    end
  end

  describe "settled/2" do
    test "holds back the unfinished last word until the reply ends" do
      assert SpeechDeltas.settled("Começou on", false) == "Começou "
      assert SpeechDeltas.settled("Começou on", true) == "Começou on"
      assert SpeechDeltas.settled("Começ", false) == ""
    end

    test "holds back an unclosed stage direction" do
      assert SpeechDeltas.settled("Dói. *(geme ", false) == "Dói. "

      assert SpeechDeltas.settled("Dói. (geme baixinho) Começou ", false) ==
               "Dói. (geme baixinho) Começou "
    end
  end

  describe "take/2" do
    test "hands the reply over word by word, adding up to the spoken reply" do
      pieces = ["Começou ", "on", "tem à noi", "te. Ainda ", "dói."]
      result = deltas(pieces)

      assert result == ["Começou", " ontem à", " noite. Ainda", {:final, " dói."}]

      assert Enum.map_join(result, fn
               {:final, d} -> d
               d -> d
             end) == "Começou ontem à noite. Ainda dói."
    end

    test "never hands over a stage direction" do
      result = deltas(["*(curvado)* Começou ", "ontem. (sus", "pira) Ainda dói. ", "(geme)"])

      text =
        Enum.map_join(result, fn
          {:final, d} -> d
          d -> d
        end)

      assert text == "Começou ontem. Ainda dói."
      refute text =~ "curvado"
      refute text =~ "suspira"
      refute text =~ "geme"
    end

    test "keeps a parenthesis inside a sentence" do
      result = deltas(["Tomei dipirona ", "(500 mg) ", "ontem."])

      assert Enum.map_join(result, fn
               {:final, d} -> d
               d -> d
             end) == "Tomei dipirona (500 mg) ontem."
    end

    test "hands nothing over for blank or unchanged text" do
      assert SpeechDeltas.take("", "   ") == :none
      assert SpeechDeltas.take("Começou", "Começou ") == :none
    end

    test "waits instead of rewriting what was already handed over" do
      assert SpeechDeltas.take("Começou ontem", "Começou hoje ") == :none
    end
  end

  describe "mode/0" do
    setup do
      previous = Application.fetch_env(:backend, :voice_tts_streaming)

      on_exit(fn ->
        case previous do
          {:ok, value} -> Application.put_env(:backend, :voice_tts_streaming, value)
          :error -> Application.delete_env(:backend, :voice_tts_streaming)
        end
      end)
    end

    test "defaults to sentence and accepts token" do
      Application.delete_env(:backend, :voice_tts_streaming)
      assert SpeechDeltas.mode() == :sentence
      Application.put_env(:backend, :voice_tts_streaming, :token)
      assert SpeechDeltas.mode() == :token
    end

    test "raises on an unknown mode" do
      Application.put_env(:backend, :voice_tts_streaming, :words)
      assert_raise ArgumentError, ~r/voice_tts_streaming/, fn -> SpeechDeltas.mode() end
    end
  end
end
