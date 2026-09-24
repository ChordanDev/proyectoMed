defmodule Backend.StationPackageTest do
  use ExUnit.Case, async: true

  alias Backend.StationPackage

  @fixtures_path Path.expand("../../priv/stations/fixtures", __DIR__)
  @schema_path Path.expand("../../priv/stations/package.schema.json", __DIR__)

  test "validates the complete versioned package fixture" do
    package = fixture("valid-package.json")

    assert package["version"] == StationPackage.version()
    assert Map.has_key?(package["patient_profile"], "persona")
    assert Map.has_key?(package["patient_profile"], "age")
    assert Map.has_key?(package["patient_profile"], "presenting_context")
    assert Map.has_key?(package["patient_profile"], "tone")
    assert %{"topic" => _, "content" => _} = hd(package["revealable_facts"])
    assert {:ok, ^package} = StationPackage.validate(package)
  end

  test "declares the package version and numeric rubric weight in the JSON schema" do
    schema = json_file(@schema_path)
    rubric_criterion = schema["$defs"]["rubricCriterion"]

    assert schema["properties"]["version"]["const"] == StationPackage.version()

    assert schema["properties"]["patient_profile"]["required"] == [
             "persona",
             "age",
             "presenting_context",
             "tone"
           ]

    assert schema["$defs"]["revealableFact"]["required"] == ["topic", "content"]
    assert "weight" in rubric_criterion["required"]
    assert rubric_criterion["properties"]["weight"]["type"] == "number"

    assert schema["properties"]["impressos"]["oneOf"] == [
             %{"$ref" => "#/$defs/impressos"},
             %{"type" => "null"}
           ]

    assert schema["$defs"]["impressos"]["type"] == "array"
    impresso_def = schema["$defs"]["impresso"]
    assert impresso_def["required"] == ["id", "title", "category", "keywords", "content"]
    assert impresso_def["properties"]["id"]["type"] == "string"
    assert impresso_def["properties"]["title"]["type"] == "string"

    assert impresso_def["properties"]["category"]["enum"] == [
             "physical_exam",
             "laboratory",
             "imaging",
             "report"
           ]

    assert impresso_def["properties"]["keywords"]["type"] == "array"

    assert impresso_def["properties"]["content"]["oneOf"] == [
             %{"type" => "string", "minLength" => 1},
             %{"type" => "object", "minProperties" => 1}
           ]
  end

  test "validates impressos in the valid package fixture covering all clinical categories" do
    package = fixture("valid-package.json")

    assert is_list(package["impressos"])
    assert length(package["impressos"]) == 4

    categories = Enum.map(package["impressos"], & &1["category"])
    assert "physical_exam" in categories
    assert "laboratory" in categories
    assert "imaging" in categories
    assert "report" in categories

    for impresso <- package["impressos"] do
      assert is_binary(impresso["id"]) and impresso["id"] != ""
      assert is_binary(impresso["title"]) and impresso["title"] != ""
      assert is_list(impresso["keywords"]) and impresso["keywords"] != []
      assert Enum.all?(impresso["keywords"], &(is_binary(&1) and &1 != ""))
      assert is_binary(impresso["content"]) and impresso["content"] != ""
    end

    assert {:ok, ^package} = StationPackage.validate(package)
  end

  test "accepts packages when impressos is omitted, nil, or empty list" do
    base = fixture("valid-package.json")

    omitted = Map.delete(base, "impressos")
    assert {:ok, ^omitted} = StationPackage.validate(omitted)

    with_nil = Map.put(base, "impressos", nil)
    assert {:ok, ^with_nil} = StationPackage.validate(with_nil)

    with_empty = Map.put(base, "impressos", [])
    assert {:ok, ^with_empty} = StationPackage.validate(with_empty)
  end

  test "accepts impressos with structured findings map content" do
    package =
      fixture("valid-package.json")
      |> put_in(["impressos"], [
        %{
          "id" => "laboratorio-estruturado",
          "title" => "Resultados Laboratoriais Estruturados",
          "category" => "laboratory",
          "keywords" => ["laboratório", "glicemia"],
          "content" => %{"glicemia" => 118, "troponina" => "positiva"}
        }
      ])

    assert {:ok, ^package} = StationPackage.validate(package)
  end

  test "rejects package when impressos is not a list" do
    base = fixture("valid-package.json")

    for invalid_impressos <- ["invalid", 123, %{"id" => "test"}, true] do
      package = Map.put(base, "impressos", invalid_impressos)
      assert {:error, errors} = StationPackage.validate(package)
      assert "impressos must be a list" in errors
    end
  end

  test "rejects package when an impressos entry is not an object" do
    package =
      fixture("valid-package.json")
      |> Map.put("impressos", ["not_an_object"])

    assert {:error, errors} = StationPackage.validate(package)
    assert "impressos entries must be objects" in errors
  end

  test "rejects impressos entries with missing or empty required fields" do
    base = fixture("valid-package.json")

    missing_id =
      Map.put(base, "impressos", [
        %{
          "id" => "",
          "title" => "Título",
          "category" => "physical_exam",
          "keywords" => ["exame"],
          "content" => "conteúdo"
        }
      ])

    assert {:error, errors} = StationPackage.validate(missing_id)
    assert "impressos entries require a non-empty id" in errors

    missing_title =
      Map.put(base, "impressos", [
        %{
          "id" => "teste-id",
          "title" => "",
          "category" => "physical_exam",
          "keywords" => ["exame"],
          "content" => "conteúdo"
        }
      ])

    assert {:error, errors} = StationPackage.validate(missing_title)
    assert "impressos entries require a non-empty title" in errors

    missing_category =
      Map.put(base, "impressos", [
        %{
          "id" => "teste-id",
          "title" => "Título",
          "keywords" => ["exame"],
          "content" => "conteúdo"
        }
      ])

    assert {:error, errors} = StationPackage.validate(missing_category)
    assert "impressos entries require a non-empty category" in errors
  end

  test "rejects impressos entries with invalid category" do
    package =
      fixture("valid-package.json")
      |> Map.put("impressos", [
        %{
          "id" => "teste-id",
          "title" => "Título",
          "category" => "exame_invalido",
          "keywords" => ["exame"],
          "content" => "conteúdo"
        }
      ])

    assert {:error, errors} = StationPackage.validate(package)

    assert "impressos entries category must be one of: physical_exam, laboratory, imaging, report" in errors
  end

  test "rejects impressos entries with invalid keywords" do
    base = fixture("valid-package.json")

    non_list_keywords =
      Map.put(base, "impressos", [
        %{
          "id" => "teste-id",
          "title" => "Título",
          "category" => "physical_exam",
          "keywords" => "palavra-chave-string",
          "content" => "conteúdo"
        }
      ])

    assert {:error, errors} = StationPackage.validate(non_list_keywords)
    assert "impressos entries keywords must be a list" in errors

    empty_string_keywords =
      Map.put(base, "impressos", [
        %{
          "id" => "teste-id",
          "title" => "Título",
          "category" => "physical_exam",
          "keywords" => ["valido", ""],
          "content" => "conteúdo"
        }
      ])

    assert {:error, errors} = StationPackage.validate(empty_string_keywords)
    assert "impressos entries keywords must contain non-empty strings" in errors
  end

  test "rejects impressos entries with empty content" do
    base = fixture("valid-package.json")

    empty_string_content =
      Map.put(base, "impressos", [
        %{
          "id" => "teste-id",
          "title" => "Título",
          "category" => "physical_exam",
          "keywords" => ["exame"],
          "content" => ""
        }
      ])

    assert {:error, errors} = StationPackage.validate(empty_string_content)
    assert "impressos entries require non-empty string or structured content" in errors

    empty_map_content =
      Map.put(base, "impressos", [
        %{
          "id" => "teste-id",
          "title" => "Título",
          "category" => "physical_exam",
          "keywords" => ["exame"],
          "content" => %{}
        }
      ])

    assert {:error, errors} = StationPackage.validate(empty_map_content)
    assert "impressos entries require non-empty string or structured content" in errors
  end

  test "rejects impressos with duplicate IDs" do
    package =
      fixture("valid-package.json")
      |> Map.put("impressos", [
        %{
          "id" => "exame-duplicado",
          "title" => "Exame 1",
          "category" => "physical_exam",
          "keywords" => ["exame 1"],
          "content" => "conteudo 1"
        },
        %{
          "id" => "exame-duplicado",
          "title" => "Exame 2",
          "category" => "laboratory",
          "keywords" => ["exame 2"],
          "content" => "conteudo 2"
        }
      ])

    assert {:error, errors} = StationPackage.validate(package)
    assert "impressos entries must have unique ids" in errors
  end

  test "rejects malformed impressos fixture" do
    assert {:error, errors} =
             "invalid-package-malformed-impressos.json"
             |> fixture()
             |> StationPackage.validate()

    assert "impressos entries category must be one of: physical_exam, laboratory, imaging, report" in errors
    assert "impressos entries keywords must be a list" in errors
    assert "impressos entries require non-empty string or structured content" in errors
  end

  test "rejects a rubric criterion without a weight" do
    assert {:error, errors} =
             "invalid-package-missing-rubric-weight.json"
             |> fixture()
             |> StationPackage.validate()

    assert "rubric criteria require a numeric weight" in errors
  end

  test "rejects a rubric criterion with a non-numeric weight" do
    assert {:error, errors} =
             "invalid-package-non-numeric-rubric-weight.json"
             |> fixture()
             |> StationPackage.validate()

    assert "rubric criteria require a numeric weight" in errors
  end

  defp fixture(name) do
    @fixtures_path
    |> Path.join(name)
    |> json_file()
  end

  defp json_file(path), do: path |> File.read!() |> Jason.decode!()
end
