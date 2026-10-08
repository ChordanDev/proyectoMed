defmodule Mix.Tasks.Stations.QualifyTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.Stations.Qualify

  @moduletag capture_log: true

  defp run(args), do: capture_io(fn -> Qualify.run(args) end)

  test "prints the label-level report for the station" do
    output = run(["acute-appendicitis"])

    assert output =~ "Jev qualification run: acute-appendicitis"
    assert output =~ "Adapter: Backend.Stations.JevDecision.DisabledAdapter"
    assert output =~ "Thresholds: undefined"
    assert output =~ "not a clinical accuracy claim"
    assert output =~ "adapter_disabled"
  end

  @tag :tmp_dir
  test "writes the same report only when --out is given", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "run.txt")
    output = run(["acute-appendicitis", "--out", path])

    assert File.read!(path) <> "\n" == output
    assert File.ls!(tmp_dir) == ["run.txt"]
  end

  test "fails for a missing or unknown station" do
    assert_raise Mix.Error, ~r/Usage: mix stations.qualify/, fn -> run([]) end
    assert_raise Mix.Error, ~r/unknown_station/, fn -> run(["no-such-station"]) end
  end
end
