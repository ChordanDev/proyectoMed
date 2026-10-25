defmodule Backend.Stations.PatientVerification do
  @moduledoc """
  How generated patient replies are verified (issue #307, amending ADR-011).

  The mode is `config :backend, :patient_verification`, set from
  `PATIENT_VERIFICATION` in `config/runtime.exs`:

    * `:audit` (default) - the only pre-delivery gate is the deterministic
      `Backend.Stations.StationAI.BoundedReply` check (`check_delivery/3`). Jev
      verifies the delivered reply afterwards, asynchronously, for audit and
      measurement only (`start_audit/2`): it never delays, blocks, regenerates or
      rewrites the reply.
    * `:blocking` - the reply is delivered only after
      `Backend.Stations.CandidateGate` verifies it (Jev, the undecided-verdict
      adjudicator and the single regeneration), exactly as before #307.
    * `:off` - only the `BoundedReply` check; no patient-side Jev call at all.

  ## Audit

  One audit per delivered patient reply, recorded on the session with
  `Backend.Stations.Conversation.record_patient_audit/3` (read it back with
  `Backend.Stations.patient_audits/1`) and logged as one `:info` line,
  `[PatientVerification] audit outcome=<o> unclear=<labels> latency_ms=<ms>`,
  never with transcript text. `outcome` is the Jev decision status, `:error`
  for a technical failure, or `:bypassed` for the patient's no-information
  answer, which discloses nothing and is not sent to Jev. The verdict's
  `used_fact_ids` become the message's `verified_fact_ids`, so the facts the
  session disclosed are still derived from Jev for later turns.
  """

  require Logger

  alias Backend.Stations.CandidateGate
  alias Backend.Stations.Conversation
  alias Backend.Stations.JevDecision
  alias Backend.Stations.StationAI.BoundedReply
  alias Backend.Stations.Usage

  @modes [:blocking, :audit, :off]
  @default_mode :audit
  @default_audit_deadline_ms 10_000

  @type mode :: :blocking | :audit | :off

  @typedoc """
  One patient-reply audit: `message_index` is the position of the audited
  patient message in the transcript; `unclear_labels` name the Jev answers that
  were not clear (`question` or `question:fact_id`, plus `fact_unasked:<id>` for
  a fact a refusal found stated without being asked); never any text.
  """
  @type audit :: %{
          message_index: non_neg_integer(),
          outcome: :verified | :semantic_refusal | :low_confidence | :error | :bypassed,
          unclear_labels: [String.t()],
          used_fact_ids: [String.t()],
          latency_ms: non_neg_integer()
        }

  @typedoc "What `start_audit/2` needs to audit one delivered reply."
  @type audit_request :: %{
          session_id: String.t(),
          message_at: DateTime.t(),
          text: String.t(),
          package: map(),
          conversation: list(),
          disclosed_fact_ids: [String.t()]
        }

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

  @doc """
  The pre-delivery check of the `:audit` and `:off` modes: `candidate_text` is
  delivered when `BoundedReply.check_violations/2` passes. A rejected candidate
  gets one regeneration (`regenerate.()`, `{:ok, text}` or `{:error, reason}`),
  delivered when it passes; otherwise the turn is refused as
  `{:error, {:refused, :bounded_reply}}`, so the learner turn is kept. The
  rejected text is never returned, logged or passed to the regeneration.
  """
  @spec check_delivery(term(), map(), (-> {:ok, String.t()} | {:error, term()})) ::
          {:ok, String.t()} | {:error, {:refused, :bounded_reply}}
  def check_delivery(candidate_text, package, regenerate) when is_function(regenerate, 0) do
    case BoundedReply.check_violations(candidate_text, package) do
      :ok ->
        {:ok, candidate_text}

      {:error, {:denied, reason}} ->
        Logger.info("[PatientVerification] bounded_reply denied=#{reason} regenerating=true")

        with {:ok, text} when is_binary(text) <- regenerate.(),
             :ok <- BoundedReply.check_violations(text, package) do
          {:ok, text}
        else
          _rejected_or_failed -> {:error, {:refused, :bounded_reply}}
        end
    end
  end

  @doc """
  Audits a delivered reply with Jev in the background when the mode is
  `:audit`; does nothing otherwise. Returns at once.
  """
  @spec start_audit(audit_request(), keyword()) :: :ok
  def start_audit(request, opts \\ []) do
    if mode() == :audit do
      # The audit may outlive its caller, so it carries the session itself (#342).
      session_id = Usage.current_session()
      {:ok, _pid} = Task.start(fn -> tracked_audit(session_id, request, opts) end)
    end

    :ok
  end

  defp tracked_audit(session_id, request, opts),
    do: Usage.track(session_id, fn -> audit(request, opts) end)

  @doc """
  Audits a delivered reply with Jev now and records the result on the session.
  Returns the audit. `opts` are passed to `JevDecision.decide_patient/2`.
  """
  @spec audit(audit_request(), keyword()) :: audit()
  def audit(request, opts \\ []) do
    started_at = JevDecision.monotonic_now_ms()
    result = decide(request, opts)
    latency_ms = JevDecision.monotonic_now_ms() - started_at

    audit = %{
      outcome: outcome(result),
      unclear_labels: unclear_labels(result),
      used_fact_ids: used_fact_ids(result),
      latency_ms: latency_ms
    }

    Logger.info(
      "[PatientVerification] audit outcome=#{audit.outcome} " <>
        "unclear=#{Enum.join(audit.unclear_labels, ",")} latency_ms=#{latency_ms}"
    )

    fact_ids = if match?({:ok, _decision}, result), do: audit.used_fact_ids, else: nil

    case Conversation.record_patient_audit(request.session_id, request.message_at, %{
           audit: audit,
           verified_fact_ids: fact_ids
         }) do
      {:ok, recorded} -> recorded
      {:error, _reason} -> Map.put(audit, :message_index, nil)
    end
  end

  defp decide(request, opts) do
    if CandidateGate.no_information_answer?(request.text) do
      :bypassed
    else
      deadline_ms =
        Application.get_env(:backend, :patient_audit_deadline_ms, @default_audit_deadline_ms)

      JevDecision.decide_patient(
        %{
          candidate_text: request.text,
          package: request.package,
          conversation: request.conversation,
          deadline_at_monotonic_ms: JevDecision.monotonic_deadline_at(deadline_ms),
          disclosed_fact_ids: request.disclosed_fact_ids
        },
        opts
      )
    end
  end

  defp outcome(:bypassed), do: :bypassed

  defp outcome({:ok, %{status: status}})
       when status in [:verified, :semantic_refusal, :low_confidence],
       do: status

  defp outcome(_failure), do: :error

  defp unclear_labels({:ok, decision}) do
    undecided =
      case Map.get(decision, :undecided_labels) do
        labels when is_list(labels) -> Enum.flat_map(labels, &label_name/1)
        _ -> []
      end

    unasked = for id <- id_list(decision, :unasked_fact_ids), do: "fact_unasked:#{id}"
    undecided ++ unasked
  end

  defp unclear_labels(_other), do: []

  defp label_name(%{question: question, fact_id: fact_id})
       when is_binary(question) and is_binary(fact_id),
       do: ["#{question}:#{fact_id}"]

  defp label_name(%{question: question}) when is_binary(question), do: [question]
  defp label_name(_label), do: []

  defp used_fact_ids({:ok, decision}), do: id_list(decision, :used_fact_ids)
  defp used_fact_ids(_other), do: []

  defp id_list(decision, key) do
    case Map.get(decision, key) do
      ids when is_list(ids) -> Enum.filter(ids, &is_binary/1)
      _ -> []
    end
  end
end
