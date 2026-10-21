defmodule Backend.Stations.PatientAdjudicator.DisabledAdapter do
  @moduledoc """
  The default undecided-verdict adjudicator: decides nothing, so a
  low-confidence Jev verdict keeps today's behaviour (issue #290).
  """

  @behaviour Backend.Stations.PatientAdjudicator

  @impl true
  def adjudicate(_request, _opts), do: {:error, :disabled}
end
