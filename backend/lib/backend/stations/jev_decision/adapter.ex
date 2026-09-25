defmodule Backend.Stations.JevDecision.Adapter do
  @moduledoc """
  Behaviour for external Jev decision adapters.

  Jev serves as an external decision seam behind `Backend.Stations` for:
    1. Verifying candidate patient responses against station package ground truth
       and response rules (Patient Decision).
    2. Performing closed-set classification for rubric evaluation against code-supplied
       allowed classes and evidence IDs (Rubric Decision).

  Concrete adapters must implement this behaviour. The default adapter is
  `Backend.Stations.JevDecision.DisabledAdapter`, reflecting that live provider
  integration requires human qualification (privacy, zero-data-retention, legal terms,
  and clinical pt-BR calibration).
  """

  @type patient_decision_status :: :verified | :semantic_refusal | :low_confidence

  @type patient_decision :: %{
          required(:status) => patient_decision_status(),
          optional(:rationale) => String.t(),
          optional(:used_fact_ids) => [String.t()]
        }

  @type rubric_decision :: %{
          required(:classification) => String.t(),
          required(:evidence_ids) => [String.t()],
          optional(:rationale) => String.t()
        }

  @type trust_level :: :trusted | :untrusted

  @type conversation_turn :: %{
          required(:seq) => pos_integer(),
          required(:role) => :student | :patient,
          required(:text) => String.t(),
          required(:trust) => trust_level()
        }

  @type revealable_fact :: %{
          required(:id) => String.t(),
          required(:topic) => String.t(),
          required(:content) => String.t(),
          required(:disclosure_condition) => String.t()
        }

  @type patient_request :: %{
          required(:candidate_text) => String.t(),
          required(:package_id) => String.t(),
          required(:package_version) => String.t(),
          required(:package) => map(),
          required(:conversation) => [conversation_turn()],
          required(:latest_learner_turn) => conversation_turn() | nil,
          required(:deadline_ms) => pos_integer(),
          optional(:deadline_at_monotonic_ms) => integer()
        }

  @type rubric_request :: %{
          required(:criterion) => map(),
          required(:allowed_classes) => [String.t()],
          required(:allowed_evidence_ids) => [String.t()],
          required(:evidence_pool) => [map()],
          required(:deadline_ms) => pos_integer(),
          optional(:deadline_at_monotonic_ms) => integer()
        }

  @type technical_failure ::
          :timeout
          | :adapter_disabled
          | :malformed_output
          | :upstream_error
          | :network_error
          | {:adapter_disabled, String.t()}
          | {:upstream_error, non_neg_integer()}
          | {:upstream_5xx, non_neg_integer()}
          | {:technical_failure, atom()}
          | {:invalid_response, atom()}
          | {:invalid_request, atom()}

  @doc """
  Evaluates a candidate patient response against bounded station context.

  Returns `{:ok, decision}` with status `:verified`, `:semantic_refusal`, or `:low_confidence`,
  or `{:error, reason}` on technical failure.
  """
  @callback decide_patient(request :: patient_request()) ::
              {:ok, patient_decision() | map()} | {:error, technical_failure() | term()}

  @doc """
  Performs closed-set classification for a rubric criterion.

  Returns `{:ok, decision}` containing a classification strictly matching one of the
  code-supplied `allowed_classes` and `evidence_ids` containing only IDs from
  `allowed_evidence_ids`. Returns `{:error, reason}` on technical failure.
  """
  @callback decide_rubric(request :: rubric_request()) ::
              {:ok, rubric_decision() | map()} | {:error, technical_failure() | term()}
end
