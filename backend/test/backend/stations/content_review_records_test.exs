defmodule Backend.Stations.ContentReviewRecordsTest do
  use ExUnit.Case, async: true

  # The review records of a partner-authored station are documents a human
  # completes. These tests only keep them from drifting away from the package
  # and from being committed with a review already ticked.

  @package_path Path.expand(
                  "../../../priv/stations/acute-appendicitis/package.json",
                  __DIR__
                )
  @records_path Path.expand("../../../../docs/content/acute-appendicitis", __DIR__)

  defp package, do: @package_path |> File.read!() |> Jason.decode!()

  defp record(name), do: @records_path |> Path.join(name) |> File.read!()

  defp ids(entries, key \\ "id"), do: Enum.map(entries || [], & &1[key])

  defp mapping_ids(pattern) do
    pattern |> Regex.scan(record("package-mapping.md")) |> Enum.map(&List.last/1) |> Enum.uniq()
  end

  test "the checklist names every fact, template, impresso and criterion of the package" do
    package = package()
    checklist = record("clinical-review-checklist.md")

    authored =
      ids(package["revealable_facts"]) ++
        ids(package["approved_templates"], "template_id") ++
        ids(package["impressos"]) ++ ids(package["rubric"])

    assert authored != []
    assert Enum.reject(authored, &String.contains?(checklist, "`#{&1}`")) == []
  end

  test "the checklist has a row for every level and action of every criterion" do
    checklist = record("clinical-review-checklist.md")

    for criterion <- package()["rubric"] do
      [_before, section] = String.split(checklist, "### `#{criterion["id"]}`\n", parts: 2)
      section = section |> String.split("\n### ", parts: 2) |> hd()

      for level <- criterion["levels"] do
        assert section =~ "| `level #{level["label"]}: points` | `#{level["points"]}` |"
        assert section =~ "| `level #{level["label"]}: min_actions` | `#{level["min_actions"]}` |"
      end

      for action <- criterion["actions"] do
        role = Map.get(action, "role", "counted")
        assert section =~ "| `action #{action["id"]}: role` | #{role} |"
      end
    end
  end

  test "the checklist lists every gap and derived field of the mapping record" do
    checklist = record("clinical-review-checklist.md")
    recorded = mapping_ids(~r/^\| (G\d+[a-z]?) \|/m) ++ mapping_ids(~r/^\| (D\d+) \|/m)

    assert length(recorded) > 2
    assert Enum.reject(recorded, &String.contains?(checklist, "| #{&1} |")) == []
  end

  test "no review record is committed with a box already ticked" do
    for name <- ["clinical-review-checklist.md", "provenance-and-rights.md"] do
      refute record(name) =~ ~r/\[[xX]\]/
    end
  end
end
