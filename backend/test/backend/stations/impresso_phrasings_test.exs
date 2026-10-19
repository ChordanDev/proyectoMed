defmodule Backend.Stations.ImpressoPhrasingsTest do
  @moduledoc """
  Common clinical phrasings a candidate uses to request an impresso, matched
  against the authored station packages (issue #241).
  """
  use ExUnit.Case, async: true

  alias Backend.Stations.Impressos

  @stations_dir Path.expand("../../../priv/stations", __DIR__)

  defp impressos(station_id) do
    Path.join([@stations_dir, station_id, "package.json"])
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("impressos")
  end

  defp matched(station_id, text),
    do: Impressos.match(impressos(station_id), Impressos.normalize(text))

  @renal ["impresso-2-ureia", "impresso-2-creatinina"]

  @appendicitis_phrasings [
    {"Solicito o exame físico.", ["impresso-1-exame-fisico"]},
    {"Vou fazer o exame do abdome.", ["impresso-1-exame-fisico"]},
    {"Gostaria de ver o exame abdominal.", ["impresso-1-exame-fisico"]},
    {"Vou examinar o abdome do senhor.", ["impresso-1-exame-fisico"]},
    {"Faço a palpação abdominal.", ["impresso-1-exame-fisico"]},
    {"Palpação do abdome, por favor.", ["impresso-1-exame-fisico"]},
    {"Quero os sinais vitais.", ["impresso-1-exame-fisico"]},
    {"Peço um hemograma completo.", ["impresso-2-hemograma"]},
    {"Solicito proteína C reativa.", ["impresso-2-pcr"]},
    {"Solicito proteína C-reativa.", ["impresso-2-pcr"]},
    {"Solicito PCR.", ["impresso-2-pcr"]},
    {"Peço sódio e potássio.", ["impresso-2-eletrolitos"]},
    {"Solicito eletrólitos.", ["impresso-2-eletrolitos"]},
    {"Solicito função renal.", @renal},
    {"Peço ureia e creatinina.", @renal},
    {"Solicito glicemia.", ["impresso-2-glicemia"]},
    {"Solicito EAS.", ["impresso-2-urina-tipo-1"]},
    {"Solicito urina 1.", ["impresso-2-urina-tipo-1"]},
    {"Solicito urina tipo 1.", ["impresso-2-urina-tipo-1"]},
    {"Peço um exame de urina.", ["impresso-2-urina-tipo-1"]},
    {"Solicito USG de abdome.", ["impresso-3-exame-de-imagem"]},
    {"Solicito um ultrassom.", ["impresso-3-exame-de-imagem"]},
    {"Peço ultrassonografia de abdome.", ["impresso-3-exame-de-imagem"]},
    {"Solicito uma TC de abdome.", ["impresso-3-exame-de-imagem"]},
    {"Peço tomografia de abdome.", ["impresso-3-exame-de-imagem"]},
    {"Solicito tomografia computadorizada de abdome e pelve.", ["impresso-3-exame-de-imagem"]},
    {"Solicito um exame de imagem.", ["impresso-3-exame-de-imagem"]}
  ]

  # The receituário holds the expected initial conduct (rubric items 9 and 10),
  # so it is intentionally never released: the candidate verbalizes the conduct.
  @answer_key_impresso "impresso-4-receituario"

  @prescription_requests [
    "Prescrevo dipirona e ondansetrona.",
    "Quero prescrever.",
    "Quero fazer a prescrição.",
    "Me dá a receita.",
    "Vou preencher o receituário.",
    "Registro a conduta inicial.",
    "Quais são as medidas de suporte?"
  ]

  describe "acute-appendicitis" do
    for {text, expected} <- @appendicitis_phrasings do
      test "#{inspect(text)} releases #{Enum.join(expected, ", ")}" do
        assert matched("acute-appendicitis", unquote(text)) == unquote(expected)
      end
    end

    test "every impresso except the answer-key receituário is releasable by some phrasing" do
      released = @appendicitis_phrasings |> Enum.flat_map(&elem(&1, 1)) |> MapSet.new()

      authored =
        impressos("acute-appendicitis")
        |> Enum.map(& &1["id"])
        |> MapSet.new()
        |> MapSet.delete(@answer_key_impresso)

      assert released == authored
    end

    test "a prescription-style request releases nothing" do
      for text <- @prescription_requests do
        assert matched("acute-appendicitis", text) == [], text
      end
    end

    test "the receituário is never released by any listed phrasing" do
      phrasings = Enum.map(@appendicitis_phrasings, &elem(&1, 0)) ++ @prescription_requests

      for text <- phrasings do
        refute @answer_key_impresso in matched("acute-appendicitis", text), text
      end
    end

    test "a generic or unrelated request releases nothing" do
      for text <- [
            "exame",
            "Solicito um exame.",
            "Quero os exames.",
            "Solicito exames laboratoriais.",
            "Bom dia, tudo bem?",
            "A dor começou em outras áreas, num episódio de febre, etc.",
            "Tomografia de crânio.",
            "Solicito eletrocardiograma."
          ] do
        assert matched("acute-appendicitis", text) == [], text
      end
    end
  end

  @chest_pain_phrasings [
    {"Solicito o exame físico.", ["exame-fisico-geral"]},
    {"Vou examinar o paciente.", ["exame-fisico-geral"]},
    {"Faço o exame do tórax.", ["exame-fisico-geral"]},
    {"Exame cardiovascular, por favor.", ["exame-fisico-geral"]},
    {"Faço a ausculta.", ["exame-fisico-geral"]},
    {"Solicito troponina.", ["laboratorio-sangue-enzimas"]},
    {"Peço marcadores de necrose miocárdica.", ["laboratorio-sangue-enzimas"]},
    {"Peço marcadores cardíacos.", ["laboratorio-sangue-enzimas"]},
    {"Solicito CKMB.", ["laboratorio-sangue-enzimas"]},
    {"Solicito função renal.", ["laboratorio-sangue-enzimas"]},
    {"Solicito eletrólitos.", ["laboratorio-sangue-enzimas"]},
    {"Peço sódio e potássio.", ["laboratorio-sangue-enzimas"]},
    {"Solicito exames de sangue.", ["laboratorio-sangue-enzimas"]},
    {"Solicito raio x de tórax.", ["imagem-radiografia-torax"]},
    {"Peço um RX do tórax.", ["imagem-radiografia-torax"]},
    {"Peço um raio-x.", ["imagem-radiografia-torax"]},
    {"Solicito ECG de 12 derivações.", ["laudo-eletrocardiograma"]},
    {"Solicito eletrocardiografia.", ["laudo-eletrocardiograma"]}
  ]

  describe "chest-pain-initial-assessment" do
    for {text, expected} <- @chest_pain_phrasings do
      test "#{inspect(text)} releases #{Enum.join(expected, ", ")}" do
        assert matched("chest-pain-initial-assessment", unquote(text)) == unquote(expected)
      end
    end

    test "a generic or unrelated request releases nothing" do
      for text <- [
            "exame",
            "Solicito um exame.",
            "Quero os exames.",
            "Bom dia, tudo bem?",
            "A dor piorou num episódio, etc."
          ] do
        assert matched("chest-pain-initial-assessment", text) == [], text
      end
    end
  end
end
