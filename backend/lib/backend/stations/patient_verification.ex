defmodule Backend.Stations.PatientVerification do
  @moduledoc """
  How generated patient replies are verified (issue #307, amending ADR-011).

  The mode is `config :backend, :patient_verification`, set from
  `PATIENT_VERIFICATION` in `config/runtime.exs`:

    * `:audit` (default) - the only pre-delivery gate is the deterministic
      `Backend.Stations.StationAI.BoundedReply` check. Jev verifies the delivered
      reply afterwards, asynchronously, for audit and measurement only: it never
      delays, blocks, regenerates or rewrites the reply.
    * `:blocking` - the reply is delivered only after
      `Backend.Stations.CandidateGate` verifies it (Jev, the undecided-verdict
      adjudicator and the single regeneration), exactly as before #307.
    * `:off` - only the `BoundedReply` check; no patient-side Jev call at all.
  """

  @modes [:blocking, :audit, :off]
  @default_mode :audit

  @type mode :: :blocking | :audit | :off

  @doc """
  The configured verification mode. Raises `ArgumentError` when the configured
  value is not one of `:blocking`, `:audit` or `:off`.
  """
  @spec mode() :: mode()
  def mode do
    case Application.get_env(:backend, :patient_verification, @default_mode) do
      mode when mode in @modes ->
        mode

      other ->
        raise ArgumentError,
              "invalid :patient_verification #{inspect(other)}; " <>
                "expected one of #{inspect(@modes)}"
    end
  end
end
