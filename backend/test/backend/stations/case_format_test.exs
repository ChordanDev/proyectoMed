defmodule Backend.Stations.CaseFormatTest do
  @moduledoc """
  The tagged case format (issue #330): the reference acute-appendicitis case
  parses, through the public `Backend.Stations` interface, into a valid Station
  Package equal to the hand-tuned package on every hand-tuned field.
  """
  use ExUnit.Case, async: true

  alias Backend.Stations
  alias Backend.Stations.StationPackage

  @station_dir Path.expand("../../../priv/stations/acute-appendicitis", __DIR__)
  @case_path Path.join(@station_dir, "case.md")
  @package_path Path.join(@station_dir, "package.json")

  defp reference_case, do: File.read!(@case_path)
  defp hand_tuned, do: @package_path |> File.read!() |> Jason.decode!()

  defp parse!(text) do
    assert {:ok, package} = Stations.parse_case(text)
    package
  end

  describe "the reference acute-appendicitis case" do
    test "parses into a valid Station Package" do
      package = parse!(reference_case())

      assert {:ok, ^package} = StationPackage.validate(package)
    end

    test "equals the hand-tuned package on every hand-tuned field" do
      package = parse!(reference_case())
      hand_tuned = hand_tuned()

      for {field, value} <- hand_tuned do
        assert package[field] == value, "field #{field} differs"
      end
    end

    test "declares area, theme and the patient actor" do
      package = parse!(reference_case())

      assert package["area"] == "Cirurgia Geral"
      assert package["theme"] == "Abdome agudo inflamatório — apendicite aguda"

      assert [patient] = package["actors"]

      assert %{
               "id" => "paciente",
               "role" => "patient",
               "name" => "Rafael Nogueira",
               "age" => 27,
               "voice" => "masculina-adulta",
               "mandatory_question_ids" => ["duvida-final-01", "duvida-final-02"]
             } = patient

      assert patient["persona"] == hand_tuned()["patient_profile"]["persona"]
      assert "hda-01" in patient["fact_ids"]
      assert "pergunta-explicita-05" in patient["explicit_fact_ids"]
      refute "hda-01" in patient["explicit_fact_ids"]
    end

    test "links facts and criteria to the PEP" do
      links = parse!(reference_case())["pep_links"]

      assert %{"fact_id" => "hda-01", "criterion_id" => "item-02", "action_id" => "criterio-1"} in links[
               "facts"
             ]

      refute Enum.any?(links["facts"], &(&1["fact_id"] == "antecedentes-04"))

      types = Map.new(links["actions"], &{{&1["criterion_id"], &1["action_id"]}, &1})

      assert types[{"item-02", "criterio-1"}]["type"] == "question"
      assert types[{"item-06", "criterio-1"}]["type"] == "request"
      assert types[{"item-07", "criterio-1"}]["type"] == "verbalization"
      assert types[{"item-11", "criterio-3"}]["type"] == "communication"

      assert types[{"item-11", "criterio-3"}]["question_ids"] == [
               "duvida-final-01",
               "duvida-final-02"
             ]
    end
  end
end
