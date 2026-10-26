defmodule Backend.E2ESupport.ScriptedStationAIAdapter do
  @moduledoc """
  Deterministic patient generator for process-level tests only, such as the
  Unreal station client's typed-turn tests against a local Phoenix (#192).

  **This adapter generates nothing.** It never reads the package or the
  conversation and performs no I/O: every learner turn addressed to the patient
  gets the same fixed reply. It exists so a client that boots against a real
  Phoenix process, which cannot inject an adapter, can exercise a full turn
  through the real HTTP contract without a text provider.

  Like `Backend.E2ESupport.ApprovingJevAdapter`, which it is meant to be
  combined with, it lives outside `lib/`, is compiled only for `:dev` and
  `:test` (`elixirc_paths/1` in `mix.exs`), and is selected only by
  `STATION_AI_E2E_SCRIPTED_ADAPTER=true` under `:dev` (`config/runtime.exs`).
  """

  @behaviour Backend.Stations.StationAI

  @reply_text "Bom dia, doutor."

  @doc "The patient-facing text of every reply."
  @spec reply_text() :: String.t()
  def reply_text, do: @reply_text

  @impl true
  def next_reply(_package, _context) do
    {:ok, %{text: "[PACIENTE] " <> @reply_text}}
  end
end
