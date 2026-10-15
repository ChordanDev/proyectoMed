defmodule Mix.Tasks.Stations.Qualify do
  @shortdoc "Runs the Jev qualification cases of a station (--debug for per-question nouls)"

  @moduledoc """
  Runs the fictional qualification cases of a station through the Jev dialogue
  gate and the rubric assessment, with the configured Jev adapter and rubric
  resolver (`RUBRIC_RESOLVER`). The report names both.

      mix stations.qualify acute-appendicitis
      mix stations.qualify acute-appendicitis --out run.txt
      mix stations.qualify acute-appendicitis --debug

  The report holds case identifiers, categories and outcome labels only. It is
  printed, and written to a file only when `--out` names one. Missing parent
  directories of that file are created; the report is printed first, so a
  failed write does not lose it.

  The report is not a clinical accuracy claim and carries no verdict. With the
  default disabled adapter every case that needs a Jev decision is reported as
  `adapter_disabled`.

  ## Debug diagnostics

  `--debug` sets the Logger level to `:debug` for the run. The harness then logs
  `[Qualification] case=<id> surface=<surface>` before each case and, with the
  TypeSafe adapter, `[TypesafeAdapter] patient verdict=<status>` with every
  question id, its noul rounded to 3 decimals and its class (`yes`, `no`,
  `undecided`). Those lines carry ids and numbers only, never case text, and go
  to the console only, never to the `--out` file. Without `--debug`, a
  configured level more verbose than `:info` is raised to `:info` for the run,
  so default runs stay quiet. The configured level is restored afterwards.
  """

  use Mix.Task

  alias Backend.Stations

  @impl Mix.Task
  def run(args) do
    case OptionParser.parse(args, strict: [out: :string, debug: :boolean]) do
      {opts, [station_id], []} -> qualify(station_id, opts[:out], opts[:debug] == true)
      _invalid -> Mix.raise("Usage: mix stations.qualify <station_id> [--out <path>] [--debug]")
    end
  end

  defp qualify(station_id, out, debug?) do
    Mix.Task.run("app.config")
    # A live Jev adapter calls its provider through Req, whose HTTP pool belongs to
    # the :req application; app.config loads configuration without starting it.
    {:ok, _apps} = Application.ensure_all_started(:req)

    with_log_level(run_level(debug?), fn ->
      case Stations.run_qualification(station_id) do
        {:ok, summary} ->
          report = Stations.render_qualification(summary)
          Mix.shell().info(report)
          if out, do: write_report(out, report)

        {:error, reason} ->
          Mix.raise("Qualification of #{station_id} did not run: #{inspect(reason)}")
      end
    end)
  end

  defp run_level(true), do: :debug

  defp run_level(false) do
    if Logger.compare_levels(Logger.level(), :info) == :lt, do: :info, else: Logger.level()
  end

  # The level is global, so it is only touched when it differs, and always restored.
  defp with_log_level(level, fun) do
    case Logger.level() do
      ^level ->
        fun.()

      configured ->
        Logger.configure(level: level)

        try do
          fun.()
        after
          Logger.configure(level: configured)
        end
    end
  end

  defp write_report(out, report) do
    with :ok <- File.mkdir_p(Path.dirname(out)),
         :ok <- File.write(out, report) do
      :ok
    else
      {:error, reason} ->
        Mix.raise("Could not write the report to #{out}: #{:file.format_error(reason)}")
    end
  end
end
