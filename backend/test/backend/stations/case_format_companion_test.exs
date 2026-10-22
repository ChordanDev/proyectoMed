defmodule Backend.Stations.CaseFormatCompanionTest do
  @moduledoc """
  A case with a patient and a companion (issue #330, spec #326 user stories
  24-25): each actor is declared with its profile and voice, and owns its
  facts and mandatory questions.
  """
  use ExUnit.Case, async: true

  alias Backend.Stations
  alias Backend.Stations.StationPackage

  @fixture_path Path.expand("fixtures/case_format/companion.md", __DIR__)

  setup do
    assert {:ok, package} = @fixture_path |> File.read!() |> Stations.parse_case()
    %{package: package}
  end

  test "parses into a valid Station Package", %{package: package} do
    assert {:ok, ^package} = StationPackage.validate(package)
  end

  test "declares the patient and the companion with their profile and voice",
       %{package: package} do
    assert [patient, companion] = package["actors"]

    assert %{"id" => "paciente", "role" => "patient", "age" => 2, "voice" => "infantil"} = patient

    assert companion == %{
             "id" => "mae",
             "role" => "companion",
             "name" => "Juliana Souza",
             "age" => 34,
             "voice" => "feminina-adulta",
             "persona" => "Mãe de Lucas, preocupada e colaborativa.",
             "tone" => "Fala de forma direta, com vocabulário simples.",
             "fact_ids" => ["febre-inicio", "febre-maxima"],
             "explicit_fact_ids" => ["febre-maxima"],
             "mandatory_question_ids" => ["duvida-mae-01"]
           }

    assert package["patient_profile"] == %{
             "persona" => "Lucas está no colo da mãe, choroso, e não responde a perguntas.",
             "age" => 2,
             "presenting_context" =>
               "Lucas Souza, 2 anos, trazido pela mãe por febre há dois dias.",
             "tone" => "Não fala; apenas chora quando examinado."
           }
  end

  test "keeps each actor's facts and mandatory questions", %{package: package} do
    [patient, _companion] = package["actors"]
    assert patient["fact_ids"] == ["choro"]
    assert patient["mandatory_question_ids"] == []

    assert %{"id" => "duvida-mae-01", "disclosure_condition" => "timed"} =
             Enum.find(package["revealable_facts"], &(&1["id"] == "duvida-mae-01"))
  end

  test "a communication criterion checks the companion's mandatory question",
       %{package: package} do
    assert %{"question_ids" => ["duvida-mae-01"], "type" => "communication"} =
             Enum.find(package["pep_links"]["actions"], &(&1["criterion_id"] == "item-02"))
  end

  test "a companion needs a profile and a tone, but no presenting context" do
    text =
      @fixture_path
      |> File.read!()
      |> String.replace("[TOM] Fala de forma direta, com vocabulário simples.\n", "")

    assert {:error, [%{message: "missing [TOM] for actor mae"}]} = Stations.parse_case(text)
  end
end
