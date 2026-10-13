defmodule Backend.Stations.JevDecision.DisabledAdapter do
  @moduledoc """
  Default Jev decision adapter used when live qualification is pending.

  Live provider integration (credentials, zero-data-retention terms, clinical pt-BR
  calibration, and legal terms) requires human approval and qualification before
  activation. Until qualified and enabled, this adapter safely rejects all requests
  with a typed technical failure.
  """

  @behaviour Backend.Stations.JevDecision.Adapter

  @disabled_message "Live Jev adapter is disabled by default; human qualification pending"

  @impl true
  def decide_patient(_request) do
    {:error, {:adapter_disabled, @disabled_message}}
  end

  @impl true
  def decide_rubric(_request) do
    {:error, {:adapter_disabled, @disabled_message}}
  end

  @impl true
  def decide_rubric_batch(_request) do
    {:error, {:adapter_disabled, @disabled_message}}
  end
end
