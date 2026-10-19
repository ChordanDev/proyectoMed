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
    {"Solicito um exame de imagem.", ["impresso-3-exame-de-imagem"]},
    {"Prescrevo dipirona e ondansetrona.", ["impresso-4-receituario"]},
    {"Quero fazer a prescrição.", ["impresso-4-receituario"]},
    {"Vou preencher o receituário.", ["impresso-4-receituario"]},
    {"Registro a conduta inicial.", ["impresso-4-receituario"]}
  ]

  describe "acute-appendicitis" do
    for {text, expected} <- @appendicitis_phrasings do
      test "#{inspect(text)} releases #{Enum.join(expected, ", ")}" do
        assert matched("acute-appendicitis", unquote(text)) == unquote(expected)
      end
    end

    test "every impresso, including the receituário, is releasable by some phrasing" do
      released = @appendicitis_phrasings |> Enum.flat_map(&elem(&1, 1)) |> MapSet.new()
      authored = impressos("acute-appendicitis") |> Enum.map(& &1["id"]) |> MapSet.new()

      assert released == authored
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
end
