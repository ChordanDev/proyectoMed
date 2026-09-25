defmodule Backend.Stations.StationAI.NoOpAdapter do
  @moduledoc """
  Default `Backend.Stations.StationAI` adapter used when no LLM-backed adapter is
  configured. Returns the configured refusal text without consulting any
  model.
  """

  @behaviour Backend.Stations.StationAI

  @impl true
  def next_reply(_package, _context) do
    {:ok, %{text: Backend.Stations.StationAI.refusal_text()}}
  end
end

defmodule Backend.StationAI.NoOpAdapter do
  @moduledoc false
  @behaviour Backend.StationAI

  alias Backend.Stations.StationAI.NoOpAdapter, as: Target

  @impl true
  defdelegate next_reply(package, context), to: Target
end
