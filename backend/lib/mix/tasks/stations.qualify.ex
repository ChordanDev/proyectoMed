defmodule Mix.Tasks.Stations.Qualify do
  @shortdoc "Runs the Jev qualification cases of a station"

  @moduledoc """
  Runs the fictional qualification cases of a station through the Jev dialogue
  gate and the rubric assessment, with the configured Jev adapter.

      mix stations.qualify acute-appendicitis
      mix stations.qualify acute-appendicitis --out run.txt

  The report holds case identifiers, categories and outcome labels only. It is
  printed, and written to a file only when `--out` names one. Missing parent
  directories of that file are created; the report is printed first, so a
  failed write does not lose it.

  The report is not a clinical accuracy claim and carries no verdict. With the
  default disabled adapter every case that needs a Jev decision is reported as
  `adapter_disabled`.
  """

  use Mix.Task

  alias Backend.Stations

  @impl Mix.Task
  def run(args) do
    case OptionParser.parse(args, strict: [out: :string]) do
      {opts, [station_id], []} -> qualify(station_id, opts[:out])
      _invalid -> Mix.raise("Usage: mix stations.qualify <station_id> [--out <path>]")
    end
  end

  defp qualify(station_id, out) do
    Mix.Task.run("app.config")
    # A live Jev adapter calls its provider through Req, whose HTTP pool belongs to
    # the :req application; app.config loads configuration without starting it.
    {:ok, _apps} = Application.ensure_all_started(:req)

    case Stations.run_qualification(station_id) do
      {:ok, summary} ->
        report = Stations.render_qualification(summary)
        Mix.shell().info(report)
        if out, do: write_report(out, report)

      {:error, reason} ->
        Mix.raise("Qualification of #{station_id} did not run: #{inspect(reason)}")
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
