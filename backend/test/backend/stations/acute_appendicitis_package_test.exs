defmodule Backend.Stations.AcuteAppendicitisPackageTest do
  use ExUnit.Case, async: true

  alias Backend.Stations.RubricAssessment.AuthoredRules
  alias Backend.Stations.RubricAssessment.Points
  alias Backend.Stations.StationPackage

  @package_path Path.expand(
                  "../../../priv/stations/acute-appendicitis/package.json",
                  __DIR__
                )

  @labels ~w(inadequado parcialmente_adequado adequado)

  # The partner's PEP, items 1 to 11: the points of each level as exact decimal
  # strings and the count thresholds, both as {inadequado, parcialmente
  # adequado, adequado}.
  @authored [
    {"item-01", {"0", "0.1", "0.2"}, {0, 1, 2}},
    {"item-02", {"0", "0.4", "0.8"}, {0, 3, 5}},
    {"item-03", {"0", "0.4", "0.8"}, {0, 2, 4}},
    {"item-04", {"0", "0.3", "0.6"}, {0, 2, 4}},
    {"item-05", {"0", "0.6", "1.2"}, {0, 2, 3}},
    {"item-06", {"0", "0.4", "0.8"}, {0, 2, 3}},
    {"item-07", {"0", "0.4", "0.8"}, {0, 2, 3}},
    {"item-08", {"0", "0.7", "1.4"}, {0, 1, 4}},
    {"item-09", {"0", "0.6", "1.2"}, {0, 2, 4}},
    {"item-10", {"0", "0.6", "1.2"}, {0, 2, 3}},
    {"item-11", {"0", "0.5", "1"}, {0, 2, 3}}
  ]

  defp package, do: @package_path |> File.read!() |> Jason.decode!()

  defp level(criterion, label), do: Enum.find(criterion["levels"], &(&1["label"] == label))

  defp points(criterion, label) do
    {:ok, points} = Points.from_authored(level(criterion, label)["points"])
    points
  end

  defp roles(criterion) do
    for %{"id" => id, "role" => role} <- criterion["actions"], role != "counted", do: {id, role}
  end

  test "decodes and passes the package contract" do
    package = package()

    assert {:ok, ^package} = StationPackage.validate(package)
  end

  test "is the pt-BR acute appendicitis station, still a placeholder" do
    package = package()

    assert package["station_id"] == "acute-appendicitis"
    assert package["version"] == StationPackage.version()
    assert package["language"] == "pt-BR"
    assert package["placeholder"] == true
  end

  test "authors the eleven items in order, each with the three levels" do
    rubric = package()["rubric"]

    assert Enum.map(rubric, & &1["id"]) == Enum.map(@authored, &elem(&1, 0))

    for criterion <- rubric do
      assert Enum.map(criterion["levels"], & &1["label"]) == @labels
    end
  end

  test "keeps the partner's points for every level" do
    rubric = package()["rubric"]

    authored =
      for criterion <- rubric do
        decimals = Enum.map(@labels, &Points.to_decimal_string(points(criterion, &1)))
        {criterion["id"], List.to_tuple(decimals)}
      end

    assert authored == Enum.map(@authored, fn {id, points, _thresholds} -> {id, points} end)
  end

  test "keeps the partner's count thresholds for every level" do
    rubric = package()["rubric"]

    authored =
      for criterion <- rubric do
        thresholds = Enum.map(@labels, &level(criterion, &1)["min_actions"])
        {criterion["id"], List.to_tuple(thresholds)}
      end

    assert authored == Enum.map(@authored, fn {id, _points, thresholds} -> {id, thresholds} end)
  end

  test "the adequado levels total exactly 10 points" do
    total = package()["rubric"] |> Enum.map(&points(&1, "adequado")) |> Points.sum()

    assert total == 400
    assert Points.to_decimal_string(total) == "10"
  end

  test "authors a role only where the partner's levels name a single action" do
    non_counted =
      for criterion <- package()["rubric"], roles(criterion) != [] do
        {criterion["id"], roles(criterion), criterion["veto"]}
      end

    assert non_counted == [
             {"item-07", [{"atribuicao-a-infeccao-urinaria", "forbidden"}], true},
             {"item-08", [{"criterio-4", "mandatory"}], false}
           ]
  end

  # Issue #228: only the actions that are themselves a request for an impresso
  # name it. Item 5 asks for authorization and verbalized findings, so the
  # physical exam handout does not decide any of its actions.
  test "authors impresso_ids only on the lab and imaging request actions" do
    authored =
      for criterion <- package()["rubric"],
          %{"impresso_ids" => ids} = action <- criterion["actions"] do
        {criterion["id"], action["id"], ids}
      end

    assert authored == [
             {"item-06", "criterio-1", ["impresso-2-hemograma"]},
             {"item-06", "criterio-2", ["impresso-2-pcr"]},
             {"item-06", "criterio-3", ["impresso-2-urina-tipo-1"]},
             {"item-06", "criterio-4",
              ["impresso-2-ureia", "impresso-2-creatinina", "impresso-2-eletrolitos"]},
             {"item-08", "criterio-1", ["impresso-3-exame-de-imagem"]}
           ]
  end

  # Issue #264: one on-request fact per rubric characteristic, so a reply to one
  # question cannot volunteer the answer to another criterion.
  @item_2_facts [
    {"criterio-1", "hda-01", "A dor começou ao redor do umbigo."},
    {"criterio-2", "hda-01-migracao",
     "Há cerca de 10 horas, a dor migrou para a parte inferior direita do abdome."},
    {"criterio-3", "hda-02", "É uma dor contínua."},
    {"criterio-3", "hda-02-progressao", "A dor foi aumentando progressivamente."},
    {"criterio-4", "hda-01-tempo", "A dor começou há 18 horas."},
    {"criterio-5", "hda-02-intensidade", "Atualmente, a dor é 7/10."}
  ]

  defp fact(id), do: Enum.find(package()["revealable_facts"], &(&1["id"] == id))

  test "each item-2 characteristic is a separate on-request fact" do
    item_2 = Enum.find(package()["rubric"], &(&1["id"] == "item-02"))
    action_ids = Enum.map(item_2["actions"], & &1["id"])

    for {criterion, id, content} <- @item_2_facts do
      assert criterion in action_ids
      assert %{"content" => ^content, "disclosure_condition" => "on_request"} = fact(id)
    end
  end

  test "no fact still bundles the item-2 characteristics" do
    contents = Enum.map(package()["revealable_facts"], & &1["content"])

    refute Enum.any?(contents, &(&1 =~ "18 horas" and &1 =~ "umbigo"))
    refute Enum.any?(contents, &(&1 =~ "umbigo" and &1 =~ "migrou"))
    refute Enum.any?(contents, &(&1 =~ "contínua" and &1 =~ "7/10"))
  end

  @item_4_facts [
    {"criterio-1", "antecedentes-01", "Nega doenças crônicas."},
    {"criterio-2", "antecedentes-01-internacoes-cirurgias",
     "Nega internações anteriores e cirurgias."},
    {"criterio-3", "pergunta-explicita-02-anti-inflamatorios",
     "Nega uso recente de anti-inflamatórios."},
    {"criterio-5", "pergunta-explicita-02",
     "Nega uso recente de antibióticos ou anticoagulantes."}
  ]

  test "each item-4 characteristic is a separate on-request fact" do
    item_4 = Enum.find(package()["rubric"], &(&1["id"] == "item-04"))
    action_ids = Enum.map(item_4["actions"], & &1["id"])

    for {criterion, id, content} <- @item_4_facts do
      assert criterion in action_ids
      assert %{"content" => ^content, "disclosure_condition" => "on_request"} = fact(id)
    end
  end

  test "every criterion has rule fields the assessment can apply" do
    for criterion <- package()["rubric"] do
      assert AuthoredRules.check(criterion) == :ok
      assert criterion["exclusion"] == false
      assert criterion["rule"] == nil
    end
  end
end
