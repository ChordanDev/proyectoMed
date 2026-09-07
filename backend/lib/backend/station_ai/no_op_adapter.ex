defmodule Backend.StationAI.NoOpAdapter do
  @moduledoc """
  Default `Backend.StationAI` adapter used when no LLM-backed adapter is
  configured. Returns the configured refusal text without consulting any
  model. The real OpenAI-backed adapter lives in sub-issue #45.
  """

  @behaviour Backend.StationAI

  @impl true
  def next_reply(_package, _context) do
    {:ok, %{text: Backend.StationAI.refusal_text()}}
  end
end
