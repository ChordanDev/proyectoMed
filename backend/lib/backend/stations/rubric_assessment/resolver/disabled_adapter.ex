defmodule Backend.Stations.RubricAssessment.Resolver.DisabledAdapter do
  @moduledoc """
  The default rubric resolver: decides nothing, so every action Jev left
  undecided stays `"uncertain"`.
  """

  @behaviour Backend.Stations.RubricAssessment.Resolver

  @impl true
  def resolve(_request, _opts), do: {:ok, %{actions: []}}
end
