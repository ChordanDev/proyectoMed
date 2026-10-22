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
