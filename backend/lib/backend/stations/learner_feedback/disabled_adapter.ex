defmodule Backend.Stations.LearnerFeedback.DisabledAdapter do
  @moduledoc """
  Default learner feedback adapter. It never calls a provider, so every
  criterion keeps its authored `practice_recommendation`.
  """

  @behaviour Backend.Stations.LearnerFeedback.Adapter

  @impl true
  def write_feedback(_request), do: {:error, :disabled}
end
