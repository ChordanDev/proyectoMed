defmodule Backend.Stations.JevDecision.Adapter do
  @moduledoc """
  Behaviour for external Jev decision adapters.

  Jev serves as an external decision seam behind `Backend.Stations` for:
    1. Verifying candidate patient responses against station package ground truth
       and response rules (Patient Decision).
    2. Performing closed-set classification for rubric evaluation against code-supplied
       allowed classes and evidence IDs (Rubric Decision).
    3. Optionally, classifying several independent rubric questions over one shared
       evidence pool in a single call (Rubric Batch Decision).
    4. Optionally, deciding whether a learner turn is addressed to the examiner or
       to the patient before any reply is generated (Addressee Decision, #274).

  Concrete adapters must implement this behaviour. The default adapter is
  `Backend.Stations.JevDecision.DisabledAdapter`, reflecting that live provider
  integration requires human qualification (privacy, zero-data-retention, legal terms,
  and clinical pt-BR calibration).
  """

  alias Backend.Stations.JevDecision.RubricBatch

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

  @type rubric_batch_request :: RubricBatch.adapter_request()

  @type rubric_batch_response :: %{required(:decisions) => [RubricBatch.decision() | map()]}

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

  @doc """
  Classifies several independent rubric questions over one shared evidence pool.

  The request carries `questions` (each with its `criterion`, `allowed_classes`
  and authored `actions`) and a single `evidence_pool` for the whole batch.

  Returns `{:ok, %{decisions: decisions}}` with exactly one decision per question,
  identified by `criterion_id`, classified with one of that question's
  `allowed_classes`, and carrying one action decision per authored action
  (`"performed"`, `"not_performed"` or `"uncertain"`). Returns `{:error, reason}`
  on technical failure.

  A question that carries `enumerate_answers: true` must also be answered with
  `answers`: the ordered list of the distinct answers the learner gave to that
  criterion, each `%{evidence_id, action_id}`, where `action_id` is the authored
  action the answer matches or `nil`. Answers that match no authored action are
  listed too. An adapter that does not enumerate fails the batch, like any
  other missing output.

  This callback is optional: an adapter that does not implement it cannot serve
  batched rubric decisions and the caller receives a typed technical failure.
  """
  @callback decide_rubric_batch(request :: rubric_batch_request()) ::
              {:ok, rubric_batch_response() | map()} | {:error, technical_failure() | term()}

  @type addressee :: :examiner | :patient | :undecided

  @type addressee_request :: %{
          required(:conversation) => [conversation_turn()],
          required(:latest_learner_turn) => conversation_turn(),
          required(:deadline_ms) => pos_integer(),
          optional(:deadline_at_monotonic_ms) => integer()
        }

  @doc """
  Decides whether the latest learner turn is addressed to the examiner or to the
  patient (issue #274), from the latest learner turn and the bounded recent
  conversation only.

  Returns `{:ok, %{addressee: :examiner | :patient | :undecided}}` or
  `{:error, reason}` on technical failure.

  This callback is optional: an adapter that does not implement it leaves every
  turn patient-addressed.
  """
  @callback decide_addressee(request :: addressee_request()) ::
              {:ok, %{required(:addressee) => addressee()} | map()}
              | {:error, technical_failure() | term()}

  @optional_callbacks decide_rubric_batch: 1, decide_addressee: 1
end
