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

  test "drives the opening-greeting case through Jev instead of a deterministic denial" do
    output = run(["acute-appendicitis"])

    assert output =~ "Adjudication: 0 of 34 cases adjudicated"
    assert output =~ "unsupported_or_early_disclosure | 5 |"

    assert output =~
             "unsupported-or-early-disclosure-05 | unsupported_or_early_disclosure | dialogue_gate | adapter_disabled | adapter_disabled"
  end

  @tag :tmp_dir
  test "writes the same report only when --out is given", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "run.txt")
    output = run(["acute-appendicitis", "--out", path])

    assert File.read!(path) <> "\n" == output
    assert File.ls!(tmp_dir) == ["run.txt"]
  end

  @tag :tmp_dir
  test "creates the missing parent directories of --out", %{tmp_dir: tmp_dir} do
    path = Path.join([tmp_dir, "runs", "today", "run.txt"])
    output = run(["acute-appendicitis", "--out", path])

    assert File.read!(path) <> "\n" == output
  end

  @tag :tmp_dir
  test "prints the report before failing when --out cannot be written", %{tmp_dir: tmp_dir} do
    blocker = Path.join(tmp_dir, "not-a-directory")
    File.write!(blocker, "")
    path = Path.join(blocker, "run.txt")

    output =
      capture_io(fn ->
        assert_raise Mix.Error, ~r/Could not write the report to #{Regex.escape(path)}/, fn ->
          Qualify.run(["acute-appendicitis", "--out", path])
        end
      end)

    assert output =~ "Jev qualification run: acute-appendicitis"
  end

  test "fails for a missing or unknown station" do
    assert_raise Mix.Error, ~r/Usage: mix stations.qualify/, fn -> run([]) end
    assert_raise Mix.Error, ~r/unknown_station/, fn -> run(["no-such-station"]) end
  end
end

defmodule Mix.Tasks.Stations.QualifyLoggerLevelTest do
  # async: false because the task changes the global Logger level for its run.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  alias Mix.Tasks.Stations.Qualify

  @case_line "[Qualification] case=unsupported-or-early-disclosure-05 surface=dialogue_gate"

  setup do
    level = Logger.level()
    on_exit(fn -> Logger.configure(level: level) end)
  end

  defp run_logged(args) do
    capture_log([level: :debug], fn -> capture_io(fn -> Qualify.run(args) end) end)
  end

  test "--debug prints the debug diagnostics and restores the configured level" do
    level = Logger.level()

    assert run_logged(["acute-appendicitis", "--debug"]) =~ @case_line
    assert Logger.level() == level
  end

  test "without --debug a debug-level configuration is quieted to info for the run" do
    Logger.configure(level: :debug)

    refute run_logged(["acute-appendicitis"]) =~ "[Qualification]"
    assert Logger.level() == :debug
  end

  test "without --debug a quieter configured level is left unchanged" do
    Logger.configure(level: :error)

    refute run_logged(["acute-appendicitis"]) =~ "[Qualification]"
    assert Logger.level() == :error
  end
end
