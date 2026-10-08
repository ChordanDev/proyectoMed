defmodule Mix.Tasks.Stations.Qualify do
  @shortdoc "Runs the Jev qualification cases of a station"

  @moduledoc """
  Runs the fictional qualification cases of a station through the Jev dialogue
  gate and the rubric assessment, with the configured Jev adapter.

      mix stations.qualify acute-appendicitis
      mix stations.qualify acute-appendicitis --out run.txt

  The report holds case identifiers, categories and outcome labels only. It is
  printed, and written to a file only when `--out` names one.

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

    case Stations.run_qualification(station_id) do
      {:ok, summary} ->
        report = Stations.render_qualification(summary)
        if out, do: File.write!(out, report)
        Mix.shell().info(report)

      {:error, reason} ->
        Mix.raise("Qualification of #{station_id} did not run: #{inspect(reason)}")
    end
  end
end
