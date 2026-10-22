defmodule Backend.Stations.CaseFormatN8nSamplesTest do
  @moduledoc """
  The n8n prompts stay in step with the tagged case format (issue #335,
  spec #326 user stories 1-6).

  - The generator system prompt names every tag of the format spec, and the
    complete example it embeds parses with zero errors.
  """
  use ExUnit.Case, async: true

  alias Backend.Stations

  @repo_root Path.expand("../../../..", __DIR__)
  @format_spec Path.join(@repo_root, "docs/case-format/README.md")
  @generator_prompt Path.join(@repo_root, "docs/n8n/generator-prompt.md")

  describe "generator prompt" do
    setup do
      %{prompt: system_prompt(@generator_prompt)}
    end

    test "names every tag of the format spec", %{prompt: prompt} do
      spec_tags = spec_tags()
      assert length(spec_tags) >= 20

      # The spec also shows unaccented spellings (`[ESTACAO]`); either counts.
      prompt = strip_accents(prompt)
      missing = Enum.reject(spec_tags, &String.contains?(prompt, "[" <> strip_accents(&1)))
      assert missing == [], "generator prompt does not mention: #{inspect(missing)}"
    end

    test "embeds a complete example that parses with zero errors", %{prompt: prompt} do
      assert [_, example] = Regex.run(~r/```case\n(.*?)```/s, prompt)
      assert {:ok, package} = Stations.parse_case(example)
      assert Enum.any?(package["actors"], &(&1["role"] == "companion"))
    end
  end

  describe "cases generated with the generator prompt" do
    # Raw model output for three themes, saved unedited (see docs/n8n/README.md).
    @samples Path.wildcard(Path.expand("fixtures/case_format/n8n-sample-*.md", __DIR__))

    test "cover at least three themes, one with a companion" do
      assert length(@samples) >= 3

      assert Enum.any?(@samples, fn path ->
               {:ok, package} = path |> File.read!() |> Stations.parse_case()
               Enum.any?(package["actors"], &(&1["role"] == "companion"))
             end)
    end

    for path <- @samples do
      test "#{Path.basename(path)} parses with zero errors" do
        assert {:ok, _package} = unquote(path) |> File.read!() |> Stations.parse_case()
      end
    end
  end

  # The text the user pastes into n8n: the body of the ~~~~text fence.
  defp system_prompt(path) do
    assert [_, prompt] = Regex.run(~r/~~~~text\n(.*?)~~~~/s, File.read!(path))
    prompt
  end

  # Tag names as the spec writes them in its headings and tables: `[NAME`.
  defp spec_tags do
    ~r/`\[([A-ZÁÂÃÉÊÍÓÔÕÚÇ][A-ZÁÂÃÉÊÍÓÔÕÚÇ-]*)/u
    |> Regex.scan(File.read!(@format_spec), capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp strip_accents(text) do
    text
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
  end
end

defmodule Backend.Stations.CaseFormatN8nInsertTest do
  @moduledoc """
  The Neon insert node instructions (issue #335) match the `cases` table
  (issue #331): the documented SQL inserts a pending case and Postgres
  returns its sequential number.
  """
  use Backend.DataCase, async: true

  @repo_root Path.expand("../../../..", __DIR__)
  @neon_insert Path.join(@repo_root, "docs/n8n/neon-insert.md")
  @format_spec Path.join(@repo_root, "docs/case-format/README.md")

  test "the documented insert is the contract of the format spec" do
    assert insert_sql(@neon_insert) == insert_sql(@format_spec)
  end

  test "the documented insert stores a pending case and returns its sequential number" do
    sql = insert_sql(@neon_insert)

    markdown =
      File.read!(Path.join(@repo_root, "backend/priv/stations/acute-appendicitis/case.md"))

    %{rows: [[first]]} = Repo.query!(sql, ["Cirurgia Geral", "Apendicite aguda", markdown])
    %{rows: [[second]]} = Repo.query!(sql, ["Pediatria", "Febre em lactente", markdown])

    assert is_integer(first) and second > first

    assert %{rows: [["pending", "Cirurgia Geral", ^markdown]]} =
             Repo.query!("SELECT status, area, markdown FROM cases WHERE number = $1", [first])
  end

  defp insert_sql(path) do
    # The block may be indented inside a Markdown list; compare it unindented.
    assert [_, sql] = Regex.run(~r/```sql\n\s*(INSERT INTO cases.*?)```/s, File.read!(path))
    sql |> String.split("\n") |> Enum.map_join("\n", &String.trim/1) |> String.trim()
  end
end
