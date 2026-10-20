defmodule Backend.Stations.StationAI.SentencesTest do
  use ExUnit.Case, async: true

  alias Backend.Stations.StationAI.Sentences

  defp roundtrip(text) do
    {sentences, rest} = Sentences.split(text)
    assert Enum.join(sentences) <> rest == text
    {sentences, rest}
  end

  test "splits complete sentences and keeps the unfinished tail" do
    assert {["Começou ontem.", " Dói muito!", " Sério?"], " E agora"} =
             roundtrip("Começou ontem. Dói muito! Sério? E agora")
  end

  test "a sentence is complete only once whitespace follows its punctuation" do
    assert {[], "Começou ontem."} = roundtrip("Começou ontem.")
    assert {["Começou ontem."], " "} = roundtrip("Começou ontem. ")
  end

  test "keeps numbers whole and a punctuation run with its sentence" do
    assert {["Tomei 1.5 comprimido...", " acho.", " Foi?!"], " "} =
             roundtrip("Tomei 1.5 comprimido... acho. Foi?! ")
  end

  test "does not split after common pt-BR abbreviations" do
    assert {["O Dr. Silva me atendeu.", " A Sra. Ana também."], ""} =
             roundtrip("O Dr. Silva me atendeu. A Sra. Ana também.\n")
             |> then(fn {sentences, rest} -> {sentences, String.trim(rest)} end)
  end

  test "never splits inside a stage direction" do
    assert {["*(geme. Coloca a mão na barriga.)* Dói aqui."], " (suspira. Olha) Foi"} =
             roundtrip("*(geme. Coloca a mão na barriga.)* Dói aqui. (suspira. Olha) Foi")
  end

  test "a newline ends a sentence without punctuation" do
    assert {["Sim", "\nFoi ontem."], " "} = roundtrip("Sim\nFoi ontem. ")
  end

  test "a closing quote after the punctuation stays with its sentence" do
    assert {["Ele disse \"calma.\""], " Depois"} = roundtrip("Ele disse \"calma.\" Depois")
  end
end
