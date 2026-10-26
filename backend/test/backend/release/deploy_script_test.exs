defmodule Backend.Release.DeployScriptTest do
  @moduledoc """
  `rel/deploy.sh` (#344): drains every running machine, waits until their
  active sessions reach zero or a 12-minute ceiling, then runs `fly deploy`.
  It runs against a stub `fly` that records its calls; nothing reaches Fly.
  """

  use ExUnit.Case, async: true

  @script Path.expand("../../../rel/deploy.sh", __DIR__)

  # Answers like flyctl: `machines list --quiet` prints the ids in MACHINES;
  # `drain status` prints the next count of `<machine>.counts` (the last one
  # repeats); `deploy` exits with DEPLOY_EXIT.
  @stub ~S"""
  #!/usr/bin/env bash
  set -u
  echo "$*" >> "$STUB_DIR/calls"
  case "$1 ${2:-}" in
    "machines list") for m in $MACHINES; do echo "$m"; done ;;
    "ssh console")
      machine=""; command=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --machine) machine="$2"; shift ;;
          --command) command="$2"; shift ;;
        esac
        shift
      done
      case "$command" in
        "/app/bin/drain start") echo "draining=true active_sessions=?" ;;
        "/app/bin/drain stop") echo "draining=false active_sessions=0" ;;
        "/app/bin/drain status")
          file="$STUB_DIR/$machine.counts"
          [ -s "$file" ] || exit 1
          count=$(head -n 1 "$file")
          if [ "$(wc -l < "$file")" -gt 1 ]; then tail -n +2 "$file" > "$file.next"; mv "$file.next" "$file"; fi
          echo "draining=true active_sessions=$count" ;;
      esac ;;
    "deploy "*) exit "${DEPLOY_EXIT:-0}" ;;
  esac
  """

  setup do
    dir = Path.join(System.tmp_dir!(), "deploy-script-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "bin"))
    stub = Path.join([dir, "bin", "fly"])
    File.write!(stub, @stub)
    File.chmod!(stub, 0o755)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp counts(dir, machine, counts),
    do: File.write!(Path.join(dir, "#{machine}.counts"), Enum.join(counts, "\n") <> "\n")

  defp run(dir, env, args \\ []) do
    env =
      [
        {"PATH", Path.join(dir, "bin") <> ":" <> System.get_env("PATH")},
        {"STUB_DIR", dir},
        {"FLY_APP", "proyectomed-test"},
        {"DRAIN_POLL_S", "0"}
      ] ++ env

    {output, status} = System.cmd("bash", [@script | args], env: env, stderr_to_stdout: true)
    calls = dir |> Path.join("calls") |> File.read!() |> String.split("\n", trim: true)
    {output, status, calls}
  end

  test "drains every machine, waits for zero sessions, then deploys", %{dir: dir} do
    counts(dir, "m1", [2, 1, 0])
    counts(dir, "m2", [1, 0])

    {output, 0, calls} = run(dir, [{"MACHINES", "m1 m2"}], ["--image-label", "v1"])

    assert [
             "machines list --app proyectomed-test --quiet",
             "ssh console --app proyectomed-test --machine m1 --command /app/bin/drain start",
             "ssh console --app proyectomed-test --machine m2 --command /app/bin/drain start"
             | rest
           ] = calls

    assert List.last(rest) == "deploy --app proyectomed-test --image-label v1"
    assert Enum.count(rest, &(&1 =~ "m1 --command /app/bin/drain status")) == 3
    refute Enum.any?(calls, &(&1 =~ "drain stop"))
    assert output =~ "active sessions: 3"
    assert output =~ "active sessions: 0"
  end

  test "deploys at the ceiling even with sessions still running", %{dir: dir} do
    counts(dir, "m1", [4])

    {output, 0, calls} =
      run(dir, [{"MACHINES", "m1"}, {"DRAIN_CEILING_S", "1"}, {"DRAIN_POLL_S", "1"}])

    assert output =~ "ceiling"
    assert output =~ "4 active sessions"
    assert List.last(calls) == "deploy --app proyectomed-test"
  end

  test "the default ceiling is 12 minutes", %{dir: _dir} do
    assert File.read!(@script) =~ "DRAIN_CEILING_S:-720"
  end

  test "a failed deploy resumes the drained machines and fails", %{dir: dir} do
    counts(dir, "m1", [0])

    {output, status, calls} = run(dir, [{"MACHINES", "m1"}, {"DEPLOY_EXIT", "3"}])

    assert status != 0
    assert output =~ "resuming"

    assert List.last(calls) ==
             "ssh console --app proyectomed-test --machine m1 --command /app/bin/drain stop"
  end

  test "an unreadable drain status resumes the machines and never deploys", %{dir: dir} do
    {_output, status, calls} = run(dir, [{"MACHINES", "m1"}])

    assert status != 0
    refute Enum.any?(calls, &String.starts_with?(&1, "deploy"))
    assert List.last(calls) =~ "--machine m1 --command /app/bin/drain stop"
  end

  test "without running machines (first deploy) it deploys directly", %{dir: dir} do
    {_output, 0, calls} = run(dir, [{"MACHINES", ""}])

    assert calls == [
             "machines list --app proyectomed-test --quiet",
             "deploy --app proyectomed-test"
           ]
  end
end
