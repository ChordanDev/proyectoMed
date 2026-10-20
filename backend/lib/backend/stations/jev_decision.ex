defmodule Backend.Stations.JevDecision do
  @moduledoc """
  Internal Jev decision seam encapsulated behind `Backend.Stations`.

  Provides:
    1. Patient candidate response verification (`decide_patient/2`).
    2. Closed-set rubric criterion classification (`decide_rubric/2`).
    3. Batched classification of independent rubric questions over one shared
       evidence pool (`decide_rubric_batch/2`).

  ## Safety & Reliability Invariants

    * **Disabled by default**: Live provider adapters are disabled until human
      qualification is completed (privacy, ZDR, legal, and pt-BR calibration).
    * **Strict input & output validation**: All inputs and adapter responses are
      strictly validated; invalid inputs or outputs produce typed errors.
    * **Bounded & minimized context**: Extraneous session state and package metadata
      are stripped; conversation history is bounded to recent turns; learner turns
      are explicitly marked with `:trust => :untrusted` and patient turns with
      `:trust => :trusted`; `latest_learner_turn`, `package_id`, `package_version`,
      and authored `disclosure_condition` are preserved.
    * **Total text cap, never truncated**: The learner/conversation text handed to
      any adapter (candidate, bounded conversation and latest learner turn for
      patient requests, capped by `max_context_characters/0`; the evidence pool
      for rubric requests, capped by `max_rubric_context_characters/0`). Over the cap the decision fails closed with
      `{:invalid_request, :context_limit_exceeded}` before the adapter is called.
      Trusted package content is not counted.
    * **Canonical fact IDs only**: `used_fact_ids` strictly requires canonical fact
      IDs; topic slugs are rejected.
    * **Monotonic deadline & budget sharing**: Monotonic absolute deadlines prevent
      retries from resetting a new timeout window.
    * **Sanitized technical errors**: Technical failures, crashes, 5xx, timeouts,
      and invalid outputs return sanitized typed atoms/tuples without leaking
      candidate text, learner speech, or raw exception bodies.
    * **No nonexistent evidence IDs**: Closed-set rubric classification strictly rejects
      any returned evidence IDs that do not belong to `allowed_evidence_ids`. The
      batched call returns cited IDs verbatim instead, and its caller fails the
      affected criterion closed.
    * **Privacy-safe logging**: No learner statements or patient text are ever logged.
  """

  require Logger

  alias Backend.Stations.JevDecision.DisabledAdapter
  alias Backend.Stations.JevDecision.RubricBatch

  @default_deadline_ms 3_000
  @default_max_context_turns 10
  @default_max_characters 2_000
  # Worst case of a validated session: candidate (2,000) + 10 bounded turns of at
  # most 2,000 each (learner messages are capped at entry, patient replies by
  # `max_characters`) + the latest learner turn sent again (2,000) = 24,000.
  # Normal requests never reach it; it is a fail-closed safety net.
  @default_max_context_characters 24_000
  # The rubric evidence pool is the whole transcript. Stations last 10 minutes
  # (`Conversation` default station duration) and a real session totals about
  # 20,000-30,000 characters, so 120,000 leaves ~4-5x headroom while still
  # bounding abuse (fail closed, never truncate).
  @default_max_rubric_context_characters 120_000

  @type patient_decision_status :: :verified | :semantic_refusal | :low_confidence

  @type patient_decision :: %{
          required(:status) => patient_decision_status(),
          optional(:rationale) => String.t(),
          optional(:used_fact_ids) => [String.t()],
          optional(:unasked_fact_ids) => [String.t()],
          optional(:undecided_fact_ids) => [String.t()]
        }

  @type rubric_decision :: %{
          required(:classification) => String.t(),
          required(:evidence_ids) => [String.t()],
          optional(:rationale) => String.t()
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

  @typedoc "Every error `decide_rubric_batch/2` can return."
  @type rubric_batch_error :: technical_failure() | {:malformed_output, atom()}

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Evaluates a candidate patient reply against the station package and recent conversation.

  Returns `{:ok, decision}` where `decision.status` is `:verified`, `:semantic_refusal`,
  or `:low_confidence`.

  Returns `{:error, reason}` on technical failure or invalid input.
  """
  @spec decide_patient(map(), keyword()) ::
          {:ok, patient_decision()} | {:error, technical_failure()}
  def decide_patient(request, opts \\ []) when is_list(opts) do
    with {:ok, validated_request} <- validate_patient_request(request, opts) do
      adapter = resolve_adapter(opts)
      deadline_ms = validated_request.deadline_ms
      started_at = monotonic_now_ms()

      result =
        adapter
        |> execute_adapter(:decide_patient, validated_request, deadline_ms, opts)
        |> validate_patient_output(validated_request.package)

      log_patient_latency(monotonic_now_ms() - started_at, result)
      result
    end
  end

  # Debug-level latency of each patient verification, so live runs can tune
  # the budget (issue #256). Only the decision status or "error" and the
  # milliseconds are logged, never candidate, learner or rationale text.
  defp log_patient_latency(latency_ms, result) do
    outcome =
      case result do
        {:ok, %{status: status}} when is_atom(status) -> Atom.to_string(status)
        _other -> "error"
      end

    log_privacy_safe(
      :debug,
      "patient_verification latency_ms=#{latency_ms} outcome=#{outcome}"
    )
  end

  @doc """
  Performs closed-set classification for a rubric criterion.

  Returns `{:ok, decision}` where `decision.classification` matches one of `allowed_classes`
  and `decision.evidence_ids` contains only IDs present in `allowed_evidence_ids`.

  Returns `{:error, reason}` on technical failure, invalid input, disallowed classification,
  or nonexistent evidence IDs.
  """
  @spec decide_rubric(map(), keyword()) ::
          {:ok, rubric_decision()} | {:error, technical_failure()}
  def decide_rubric(request, opts \\ []) when is_list(opts) do
    with {:ok, validated_request} <- validate_rubric_request(request, opts) do
      adapter = resolve_adapter(opts)
      deadline_ms = validated_request.deadline_ms

      result =
        execute_adapter(adapter, :decide_rubric, validated_request, deadline_ms, opts)

      validate_rubric_output(
        result,
        validated_request.allowed_classes,
        validated_request.allowed_evidence_ids
      )
    end
  end

  @doc """
  Classifies several independent rubric questions over one shared evidence pool
  with a single adapter call and a single deadline for the whole batch.

  The request is `%{questions: [question], evidence_pool: [item]}` plus the same
  optional deadline fields `decide_rubric/2` accepts. A question is
  `%{criterion: %{id, description}, allowed_classes: [String.t()], actions: [%{id, description}]}`
  (`actions` defaults to `[]`) and a pool item is `%{id, role, text}`. A question
  may add `enumerate_answers: true` to request the ordered list of the learner's
  answers to that criterion. Atom and string keys are both accepted, and the
  request is minimized before it reaches the adapter (see
  `Backend.Stations.JevDecision.RubricBatch.build_payload/1`).

  Returns `{:ok, decisions}` in question order, each decision being
  `%{criterion_id, classification, evidence_ids, rationale, actions}` as described
  in `Backend.Stations.JevDecision.RubricBatch.validate_response/2`, plus
  `answers` (`[%{evidence_id, action_id}]`) on the questions that requested the
  enumeration. A response that omits a requested enumeration is rejected like
  any other missing output.

  Returns `{:error, reason}` on an invalid request, on technical failure, or when
  the response does not carry exactly one well-formed decision per question. No
  partial result is ever returned, and an adapter that does not implement the
  batch callback yields `{:technical_failure, :rubric_batch_unsupported}` rather
  than a series of single calls.

  ## Difference from `decide_rubric/2`

  `decide_rubric/2` rejects the whole response when an evidence ID is outside
  `allowed_evidence_ids`. This function does **not** check evidence IDs against
  the pool: it only requires lists of binaries and returns them verbatim. The
  caller must validate existence, role, channel and provenance and fail the
  affected criterion closed, so one bad citation does not discard the batch.
  """
  @spec decide_rubric_batch(map(), keyword()) ::
          {:ok, [RubricBatch.decision()]} | {:error, rubric_batch_error()}
  def decide_rubric_batch(request, opts \\ []) when is_list(opts) do
    with {:ok, payload} <- RubricBatch.build_payload(request),
         :ok <- validate_evidence_pool_size(payload.evidence_pool, opts),
         {:ok, deadline_ms, deadline_at} <- resolve_deadline(request, opts) do
      adapter_request =
        Map.merge(payload, %{deadline_ms: deadline_ms, deadline_at_monotonic_ms: deadline_at})

      opts
      |> resolve_adapter()
      |> execute_batch_adapter(adapter_request, opts)
      |> validate_batch_output(payload.questions)
    end
  end

  @doc """
  Returns `true` if the given term represents a typed technical failure.
  """
  @spec technical_failure?(term()) :: boolean()
  def technical_failure?(:timeout), do: true
  def technical_failure?(:adapter_disabled), do: true
  def technical_failure?({:adapter_disabled, _}), do: true
  def technical_failure?(:malformed_output), do: true
  def technical_failure?({:malformed_output, _}), do: true
  def technical_failure?(:upstream_error), do: true
  def technical_failure?({:upstream_error, _}), do: true
  def technical_failure?({:upstream_5xx, _}), do: true
  def technical_failure?(:network_error), do: true
  def technical_failure?({:technical_failure, _}), do: true
  def technical_failure?({:invalid_response, _}), do: true
  def technical_failure?({:invalid_request, _}), do: true
  def technical_failure?(_), do: false

  @doc """
  Resolves the decision adapter to use from options or application configuration.
  """
  @spec resolve_adapter(keyword()) :: module()
  def resolve_adapter(opts \\ []) do
    opts[:adapter] ||
      Application.get_env(:backend, :jev_decision_adapter, DisabledAdapter)
  end

  @doc "Returns configured default deadline in milliseconds."
  @spec default_deadline_ms() :: pos_integer()
  def default_deadline_ms do
    Application.get_env(:backend, :jev_decision_default_deadline_ms, @default_deadline_ms)
  end

  @doc "Returns configured maximum conversation history turns."
  @spec max_context_turns() :: pos_integer()
  def max_context_turns do
    Application.get_env(:backend, :jev_decision_max_context_turns, @default_max_context_turns)
  end

  @doc "Returns configured maximum candidate text characters."
  @spec max_characters() :: pos_integer()
  def max_characters do
    Application.get_env(:backend, :jev_decision_max_characters, @default_max_characters)
  end

  @doc """
  Returns the configured maximum total characters of learner/conversation text
  sent to an adapter in one patient request. Trusted package content is not counted.
  """
  @spec max_context_characters() :: pos_integer()
  def max_context_characters do
    Application.get_env(
      :backend,
      :jev_decision_max_context_characters,
      @default_max_context_characters
    )
  end

  @doc """
  Returns the configured maximum total characters of evidence pool text sent to
  an adapter in one rubric request (`decide_rubric/2`, `decide_rubric_batch/2`).
  """
  @spec max_rubric_context_characters() :: pos_integer()
  def max_rubric_context_characters do
    Application.get_env(
      :backend,
      :jev_decision_max_rubric_context_characters,
      @default_max_rubric_context_characters
    )
  end

  @doc "Returns the current monotonic time in milliseconds."
  @spec monotonic_now_ms() :: integer()
  def monotonic_now_ms do
    System.monotonic_time(:millisecond)
  end

  @doc "Computes an absolute monotonic deadline from a timeout budget in milliseconds."
  @spec monotonic_deadline_at(pos_integer()) :: integer()
  def monotonic_deadline_at(timeout_ms \\ default_deadline_ms()) do
    monotonic_now_ms() + timeout_ms
  end

  @doc "Calculates remaining milliseconds before a monotonic deadline, bounded at 0."
  @spec remaining_budget_ms(integer()) :: non_neg_integer()
  def remaining_budget_ms(deadline_at_monotonic_ms) do
    max(0, deadline_at_monotonic_ms - monotonic_now_ms())
  end

  # ============================================================================
  # Deadline Resolution (Monotonic & Budget-Aware)
  # ============================================================================

  defp resolve_deadline(request, opts) do
    now = monotonic_now_ms()

    cond do
      deadline_at = extract_deadline_at(request, opts) ->
        resolve_from_deadline_at(deadline_at, now)

      budget = extract_budget(request, opts) ->
        resolve_from_budget(budget, now)

      true ->
        raw = extract_raw_deadline(request, opts)
        resolve_from_raw_deadline(raw, now)
    end
  end

  defp extract_deadline_at(request, opts) do
    opts[:deadline_at_monotonic_ms] ||
      Map.get(request, :deadline_at_monotonic_ms) ||
      Map.get(request, "deadline_at_monotonic_ms")
  end

  defp extract_budget(request, opts) do
    opts[:remaining_budget_ms] ||
      Map.get(request, :remaining_budget_ms) ||
      Map.get(request, "remaining_budget_ms")
  end

  defp extract_raw_deadline(request, opts) do
    opts[:deadline_ms] ||
      Map.get(request, :deadline_ms) ||
      Map.get(request, "deadline_ms") ||
      default_deadline_ms()
  end

  defp resolve_from_deadline_at(d, now) when is_integer(d) and d - now > 0, do: {:ok, d - now, d}
  defp resolve_from_deadline_at(d, _now) when is_integer(d), do: {:error, :timeout}
  defp resolve_from_deadline_at(_d, _now), do: {:error, {:invalid_request, :invalid_deadline}}

  defp resolve_from_budget(b, now) when is_integer(b) and b > 0, do: {:ok, b, now + b}
  defp resolve_from_budget(b, _now) when is_integer(b), do: {:error, :timeout}
  defp resolve_from_budget(_b, _now), do: {:error, {:invalid_request, :invalid_deadline}}

  defp resolve_from_raw_deadline(r, now) when is_integer(r) and r > 0, do: {:ok, r, now + r}
  defp resolve_from_raw_deadline(_r, _now), do: {:error, {:invalid_request, :invalid_deadline}}

  # ============================================================================
  # Input Validation & Context Bounding: Patient
  # ============================================================================

  defp validate_patient_request(request, opts) when is_map(request) do
    candidate_text = Map.get(request, :candidate_text) || Map.get(request, "candidate_text")
    package = Map.get(request, :package) || Map.get(request, "package")
    conversation = Map.get(request, :conversation) || Map.get(request, "conversation") || []
    max_chars = opts[:max_characters] || max_characters()

    with :ok <- validate_candidate_text(candidate_text, max_chars),
         :ok <- validate_package(package),
         :ok <- validate_conversation(conversation),
         {:ok, deadline_ms, deadline_at} <- resolve_deadline(request, opts) do
      minimized =
        minimize_patient_request(
          candidate_text,
          package,
          conversation,
          deadline_ms,
          deadline_at,
          opts
        )

      max_chars = opts[:max_context_characters] || max_context_characters()

      with :ok <- validate_context_size(patient_request_texts(minimized), max_chars) do
        {:ok, minimized}
      end
    end
  end

  defp validate_patient_request(_not_a_map, _opts) do
    {:error, {:invalid_request, :expected_map}}
  end

  defp validate_candidate_text(text, max_chars) when is_binary(text) do
    trimmed = String.trim(text)

    cond do
      trimmed == "" ->
        {:error, {:invalid_request, :invalid_candidate_text}}

      String.length(text) > max_chars ->
        {:error, {:invalid_request, :context_limit_exceeded}}

      true ->
        :ok
    end
  end

  defp validate_candidate_text(_text, _max_chars) do
    {:error, {:invalid_request, :invalid_candidate_text}}
  end

  # Every learner/conversation text the adapter receives. `latest_learner_turn`
  # is taken from all turns, so it may lie outside the bounded window.
  defp patient_request_texts(request) do
    latest = if request.latest_learner_turn, do: [request.latest_learner_turn.text], else: []
    [request.candidate_text | Enum.map(request.conversation, & &1.text)] ++ latest
  end

  # Fails closed over the cap; the text is never truncated.
  defp validate_context_size(texts, max_chars) do
    total = texts |> Enum.map(&text_length/1) |> Enum.sum()

    if total > max_chars do
      {:error, {:invalid_request, :context_limit_exceeded}}
    else
      :ok
    end
  end

  defp text_length(text) when is_binary(text), do: String.length(text)
  defp text_length(nil), do: 0
  # A non-binary text still reaches the adapter, so it is counted conservatively.
  defp text_length(other), do: other |> inspect() |> String.length()

  defp validate_package(package) when is_map(package), do: :ok
  defp validate_package(_package), do: {:error, {:invalid_request, :invalid_package}}

  defp validate_conversation(list) when is_list(list), do: :ok
  defp validate_conversation(_list), do: {:error, {:invalid_request, :invalid_conversation}}

  defp minimize_patient_request(
         candidate_text,
         package,
         conversation,
         deadline_ms,
         deadline_at_monotonic_ms,
         opts
       ) do
    max_turns = opts[:max_context_turns] || max_context_turns()

    package_id =
      to_string(
        Map.get(package, "station_id") ||
          Map.get(package, :station_id) || ""
      )

    package_version =
      to_string(
        Map.get(package, "version") ||
          Map.get(package, :version) || ""
      )

    labelled_turns =
      conversation
      |> Enum.with_index(1)
      |> Enum.map(fn {item, idx} -> minimize_and_label_turn(item, idx) end)

    latest_learner_turn =
      labelled_turns
      |> Enum.filter(&(&1.role == :student))
      |> List.last()

    bounded_conversation = Enum.take(labelled_turns, -max_turns)

    revealable_facts =
      (Map.get(package, "revealable_facts") ||
         Map.get(package, :revealable_facts) || [])
      |> Enum.map(&minimize_fact/1)

    response_rules =
      (Map.get(package, "response_rules") ||
         Map.get(package, :response_rules) || [])
      |> Enum.map(&minimize_rule/1)

    minimized_package = %{
      "station_id" => package_id,
      "version" => package_version,
      "patient_profile" =>
        Map.take(
          Map.get(package, "patient_profile") ||
            Map.get(package, :patient_profile) || %{},
          ["persona", "age", "tone", "presenting_context"]
        ),
      "revealable_facts" => revealable_facts,
      "response_rules" => response_rules,
      "language" => Map.get(package, "language") || Map.get(package, :language) || "pt-BR"
    }

    %{
      candidate_text: candidate_text,
      package_id: package_id,
      package_version: package_version,
      package: minimized_package,
      conversation: bounded_conversation,
      latest_learner_turn: latest_learner_turn,
      deadline_ms: deadline_ms,
      deadline_at_monotonic_ms: deadline_at_monotonic_ms
    }
  end

  defp minimize_and_label_turn(item, default_idx) when is_map(item) do
    role_raw = Map.get(item, :role) || Map.get(item, "role")

    role =
      case role_raw do
        r when r in [:student, "student", :user, "user", :learner, "learner"] -> :student
        r when r in [:patient, "patient", :assistant, "assistant"] -> :patient
        _ -> :student
      end

    trust =
      case role do
        :student -> :untrusted
        :patient -> :trusted
      end

    seq =
      case Map.get(item, :seq) || Map.get(item, "seq") do
        s when is_integer(s) and s > 0 -> s
        _ -> default_idx
      end

    %{
      seq: seq,
      role: role,
      text: to_string(Map.get(item, :text) || Map.get(item, "text") || ""),
      trust: trust
    }
  end

  defp minimize_and_label_turn(_, default_idx) do
    %{seq: default_idx, role: :student, text: "", trust: :untrusted}
  end

  defp minimize_fact(fact) when is_map(fact) do
    %{
      "id" => to_string(Map.get(fact, "id") || Map.get(fact, :id) || ""),
      "topic" => to_string(Map.get(fact, "topic") || Map.get(fact, :topic) || ""),
      "content" => to_string(Map.get(fact, "content") || Map.get(fact, :content) || ""),
      "disclosure_condition" =>
        to_string(
          Map.get(fact, "disclosure_condition") ||
            Map.get(fact, :disclosure_condition) ||
            "on_request"
        )
    }
  end

  defp minimize_fact(_), do: %{}

  defp minimize_rule(rule) when is_map(rule) do
    %{
      "id" => to_string(Map.get(rule, "id") || Map.get(rule, :id) || ""),
      "instruction" =>
        to_string(Map.get(rule, "instruction") || Map.get(rule, :instruction) || "")
    }
  end

  defp minimize_rule(_), do: %{}

  # ============================================================================
  # Input Validation & Context Bounding: Rubric
  # ============================================================================

  defp validate_rubric_request(request, opts) when is_map(request) do
    criterion = Map.get(request, :criterion) || Map.get(request, "criterion")
    allowed_classes = Map.get(request, :allowed_classes) || Map.get(request, "allowed_classes")

    allowed_evidence_ids =
      Map.get(request, :allowed_evidence_ids) ||
        Map.get(request, "allowed_evidence_ids") || []

    evidence_pool =
      Map.get(request, :evidence_pool) || Map.get(request, "evidence_pool") || []

    with :ok <- validate_criterion(criterion),
         :ok <- validate_allowed_classes(allowed_classes),
         :ok <- validate_allowed_evidence_ids(allowed_evidence_ids),
         :ok <- validate_evidence_pool(evidence_pool),
         {:ok, deadline_ms, deadline_at} <- resolve_deadline(request, opts) do
      minimized =
        minimize_rubric_request(
          criterion,
          allowed_classes,
          allowed_evidence_ids,
          evidence_pool,
          deadline_ms,
          deadline_at,
          opts
        )

      with :ok <- validate_evidence_pool_size(minimized.evidence_pool, opts) do
        {:ok, minimized}
      end
    end
  end

  defp validate_rubric_request(_not_a_map, _opts) do
    {:error, {:invalid_request, :expected_map}}
  end

  defp validate_evidence_pool_size(pool, opts) do
    max_chars = opts[:max_rubric_context_characters] || max_rubric_context_characters()
    validate_context_size(Enum.map(pool, & &1.text), max_chars)
  end

  defp validate_criterion(criterion) when is_map(criterion) do
    id = Map.get(criterion, :id) || Map.get(criterion, "id")

    if is_binary(id) and String.trim(id) != "" do
      :ok
    else
      {:error, {:invalid_request, :invalid_criterion}}
    end
  end

  defp validate_criterion(_criterion), do: {:error, {:invalid_request, :invalid_criterion}}

  defp validate_allowed_classes(classes) when is_list(classes) and classes != [] do
    if Enum.all?(classes, fn c -> is_binary(c) and String.trim(c) != "" end) do
      :ok
    else
      {:error, {:invalid_request, :invalid_allowed_classes}}
    end
  end

  defp validate_allowed_classes(_classes),
    do: {:error, {:invalid_request, :invalid_allowed_classes}}

  defp validate_allowed_evidence_ids(ids) when is_list(ids) do
    if Enum.all?(ids, fn id -> is_binary(id) and String.trim(id) != "" end) do
      :ok
    else
      {:error, {:invalid_request, :invalid_allowed_evidence_ids}}
    end
  end

  defp validate_allowed_evidence_ids(_ids),
    do: {:error, {:invalid_request, :invalid_allowed_evidence_ids}}

  defp validate_evidence_pool(pool) when is_list(pool) do
    if Enum.all?(pool, &is_map/1) do
      :ok
    else
      {:error, {:invalid_request, :invalid_evidence_pool}}
    end
  end

  defp validate_evidence_pool(_pool), do: {:error, {:invalid_request, :invalid_evidence_pool}}

  defp minimize_rubric_request(
         criterion,
         allowed_classes,
         allowed_evidence_ids,
         evidence_pool,
         deadline_ms,
         deadline_at_monotonic_ms,
         _opts
       ) do
    minimized_pool =
      Enum.map(evidence_pool, fn item ->
        %{
          id: to_string(Map.get(item, :id) || Map.get(item, "id")),
          role: Map.get(item, :role) || Map.get(item, "role"),
          text: Map.get(item, :text) || Map.get(item, "text")
        }
      end)

    minimized_criterion = %{
      id: to_string(Map.get(criterion, :id) || Map.get(criterion, "id")),
      description: Map.get(criterion, :description) || Map.get(criterion, "description") || ""
    }

    %{
      criterion: minimized_criterion,
      allowed_classes: allowed_classes,
      allowed_evidence_ids: allowed_evidence_ids,
      evidence_pool: minimized_pool,
      deadline_ms: deadline_ms,
      deadline_at_monotonic_ms: deadline_at_monotonic_ms
    }
  end

  # ============================================================================
  # Adapter Execution & Deadline Enforcement
  # ============================================================================

  defp execute_adapter(adapter, fun_name, request, deadline_ms, opts) do
    if Code.ensure_loaded?(adapter) and
         (function_exported?(adapter, fun_name, 1) or function_exported?(adapter, fun_name, 2)) do
      run_with_deadline(adapter, fun_name, request, deadline_ms, opts)
    else
      log_privacy_safe(:warning, "Adapter does not export #{fun_name}")
      {:error, {:technical_failure, :unsupported_adapter}}
    end
  end

  defp run_with_deadline(adapter, fun_name, request, deadline_ms, opts) do
    task =
      Task.async(fn ->
        try do
          if function_exported?(adapter, fun_name, 2) do
            apply(adapter, fun_name, [request, opts])
          else
            apply(adapter, fun_name, [request])
          end
        rescue
          _e -> {:error, {:technical_failure, :adapter_crashed}}
        catch
          :exit, _reason -> {:error, {:technical_failure, :task_exit}}
          :throw, _value -> {:error, {:technical_failure, :adapter_threw}}
        end
      end)

    case Task.yield(task, deadline_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} ->
        result

      nil ->
        log_privacy_safe(:warning, "Request timed out after #{deadline_ms}ms")
        {:error, :timeout}

      {:exit, _reason} ->
        log_privacy_safe(:warning, "Adapter task exited unexpectedly")
        {:error, {:technical_failure, :task_exit}}
    end
  end

  # The batch callback is optional, so an adapter that predates it is reported as
  # a typed failure; it is never replaced by serial single-criterion calls.
  defp execute_batch_adapter(adapter, request, opts) do
    if Code.ensure_loaded?(adapter) and
         (function_exported?(adapter, :decide_rubric_batch, 1) or
            function_exported?(adapter, :decide_rubric_batch, 2)) do
      run_with_deadline(adapter, :decide_rubric_batch, request, request.deadline_ms, opts)
    else
      {:error, {:technical_failure, :rubric_batch_unsupported}}
    end
  end

  defp validate_batch_output({:ok, response}, questions) do
    RubricBatch.validate_response(response, questions)
  end

  defp validate_batch_output({:error, reason}, _questions), do: normalize_error(reason)

  defp validate_batch_output(_other, _questions), do: {:error, {:malformed_output, :expected_map}}

  # ============================================================================
  # Strict Output Validation: Patient Decision
  # ============================================================================

  defp validate_patient_output({:ok, response}, package) when is_map(response) do
    raw_status = Map.get(response, :status) || Map.get(response, "status")
    used_fact_ids = Map.get(response, :used_fact_ids) || Map.get(response, "used_fact_ids")

    unasked_fact_ids =
      Map.get(response, :unasked_fact_ids) || Map.get(response, "unasked_fact_ids")

    undecided_fact_ids =
      Map.get(response, :undecided_fact_ids) || Map.get(response, "undecided_fact_ids")

    with {:ok, status} <- normalize_patient_status(raw_status),
         {:ok, validated_fact_ids} <- validate_used_fact_ids(used_fact_ids, package),
         {:ok, validated_unasked_ids} <- validate_used_fact_ids(unasked_fact_ids, package),
         {:ok, validated_undecided_ids} <- validate_used_fact_ids(undecided_fact_ids, package) do
      rationale = Map.get(response, :rationale) || Map.get(response, "rationale")

      {:ok,
       status
       |> build_patient_output_result(rationale, validated_fact_ids)
       |> maybe_put(:unasked_fact_ids, validated_unasked_ids)
       |> maybe_put(:undecided_fact_ids, validated_undecided_ids)}
    else
      :error -> {:error, {:invalid_response, :unrecognized_patient_status}}
      {:error, reason} -> {:error, {:invalid_response, reason}}
    end
  end

  defp validate_patient_output({:ok, _other}, _package) do
    {:error, {:malformed_output, :expected_map}}
  end

  defp validate_patient_output({:error, reason}, _package) do
    normalize_error(reason)
  end

  defp validate_patient_output(_other, _package) do
    {:error, {:malformed_output, :expected_map}}
  end

  defp build_patient_output_result(status, rationale, validated_fact_ids) do
    %{status: status}
    |> maybe_put(:rationale, rationale)
    |> maybe_put(:used_fact_ids, validated_fact_ids)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  defp normalize_patient_status(:verified), do: {:ok, :verified}
  defp normalize_patient_status("verified"), do: {:ok, :verified}
  defp normalize_patient_status(:semantic_refusal), do: {:ok, :semantic_refusal}
  defp normalize_patient_status("semantic_refusal"), do: {:ok, :semantic_refusal}
  defp normalize_patient_status(:low_confidence), do: {:ok, :low_confidence}
  defp normalize_patient_status("low_confidence"), do: {:ok, :low_confidence}
  defp normalize_patient_status(_other), do: :error

  defp validate_used_fact_ids(nil, _package), do: {:ok, nil}

  defp validate_used_fact_ids(ids, package) when is_list(ids) do
    if Enum.all?(ids, &is_binary/1) do
      facts =
        Map.get(package, "revealable_facts") ||
          Map.get(package, :revealable_facts) || []

      canonical_fact_ids =
        facts
        |> Enum.map(fn fact when is_map(fact) ->
          Map.get(fact, "id") || Map.get(fact, :id)
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&to_string/1)
        |> MapSet.new()

      nonexistent = Enum.reject(ids, &MapSet.member?(canonical_fact_ids, &1))

      if nonexistent == [] do
        {:ok, ids}
      else
        {:error, :nonexistent_fact_ids}
      end
    else
      {:error, :invalid_used_fact_ids}
    end
  end

  defp validate_used_fact_ids(_other, _package), do: {:error, :invalid_used_fact_ids}

  # ============================================================================
  # Strict Output Validation: Rubric Decision
  # ============================================================================

  defp validate_rubric_output({:ok, response}, allowed_classes, allowed_evidence_ids)
       when is_map(response) do
    raw_class = Map.get(response, :classification) || Map.get(response, "classification")

    raw_evidence_ids =
      Map.get(response, :evidence_ids) || Map.get(response, "evidence_ids") || []

    rationale = Map.get(response, :rationale) || Map.get(response, "rationale")

    with :ok <- validate_classification_output(raw_class, allowed_classes),
         :ok <- validate_evidence_ids_output(raw_evidence_ids, allowed_evidence_ids) do
      result = %{
        classification: raw_class,
        evidence_ids: raw_evidence_ids
      }

      result = if rationale, do: Map.put(result, :rationale, rationale), else: result
      {:ok, result}
    end
  end

  defp validate_rubric_output({:ok, _other}, _allowed_classes, _allowed_evidence_ids) do
    {:error, {:malformed_output, :expected_map}}
  end

  defp validate_rubric_output({:error, reason}, _allowed_classes, _allowed_evidence_ids) do
    normalize_error(reason)
  end

  defp validate_rubric_output(_other, _allowed_classes, _allowed_evidence_ids) do
    {:error, {:malformed_output, :expected_map}}
  end

  defp validate_classification_output(class, allowed_classes) when is_binary(class) do
    if class in allowed_classes do
      :ok
    else
      {:error, {:invalid_response, :disallowed_classification}}
    end
  end

  defp validate_classification_output(nil, _allowed_classes) do
    {:error, {:invalid_response, :missing_classification}}
  end

  defp validate_classification_output(_class, _allowed_classes) do
    {:error, {:invalid_response, :invalid_classification_type}}
  end

  defp validate_evidence_ids_output(ids, allowed_evidence_ids) when is_list(ids) do
    if Enum.all?(ids, &is_binary/1) do
      allowed_set = MapSet.new(allowed_evidence_ids)
      nonexistent = Enum.reject(ids, &MapSet.member?(allowed_set, &1))

      if nonexistent == [] do
        :ok
      else
        {:error, {:invalid_response, :nonexistent_evidence_ids}}
      end
    else
      {:error, {:invalid_response, :invalid_evidence_ids}}
    end
  end

  defp validate_evidence_ids_output(_other, _allowed_evidence_ids) do
    {:error, {:invalid_response, :invalid_evidence_ids}}
  end

  # ============================================================================
  # Technical Failure Normalization & Logging
  # ============================================================================

  defp normalize_error(reason) do
    sanitized = sanitize_error(reason)
    log_error_safe(sanitized)
    {:error, sanitized}
  end

  defp sanitize_error(:timeout), do: :timeout
  defp sanitize_error({:adapter_disabled, msg}) when is_binary(msg), do: {:adapter_disabled, msg}
  defp sanitize_error(:adapter_disabled), do: :adapter_disabled
  defp sanitize_error({:upstream_5xx, code}) when is_integer(code), do: {:upstream_5xx, code}

  defp sanitize_error({:upstream_error, code}) when is_integer(code) and code >= 500,
    do: {:upstream_5xx, code}

  defp sanitize_error({:upstream_error, code}) when is_integer(code), do: {:upstream_error, code}
  defp sanitize_error({:upstream_error, _raw}), do: :upstream_error
  defp sanitize_error(:upstream_error), do: :upstream_error
  defp sanitize_error(:network_error), do: :network_error
  defp sanitize_error(:malformed_output), do: :malformed_output
  defp sanitize_error({:malformed_output, _}), do: :malformed_output

  defp sanitize_error({:invalid_response, atom_code}) when is_atom(atom_code),
    do: {:invalid_response, atom_code}

  defp sanitize_error({:invalid_response, _}), do: {:invalid_response, :invalid_payload}

  defp sanitize_error({:technical_failure, atom_code}) when is_atom(atom_code),
    do: {:technical_failure, atom_code}

  defp sanitize_error(_other), do: {:technical_failure, :adapter_error}

  defp log_privacy_safe(level, message) do
    Logger.log(level, "[JevDecision] " <> message)
  end

  defp log_error_safe(error) do
    case error do
      :timeout ->
        log_privacy_safe(:warning, "Request timed out")

      :adapter_disabled ->
        log_privacy_safe(:warning, "Adapter is disabled")

      {:adapter_disabled, _msg} ->
        log_privacy_safe(:warning, "Adapter is disabled")

      {:upstream_5xx, code} ->
        log_privacy_safe(:warning, "Upstream HTTP 5xx: #{code}")

      {:upstream_error, code} when is_integer(code) ->
        log_privacy_safe(:warning, "Upstream error code: #{code}")

      :upstream_error ->
        log_privacy_safe(:warning, "Upstream error")

      :network_error ->
        log_privacy_safe(:warning, "Network error")

      :malformed_output ->
        log_privacy_safe(:warning, "Malformed output from adapter")

      {:invalid_response, _} ->
        log_privacy_safe(:warning, "Invalid response from adapter")

      _ ->
        log_privacy_safe(:warning, "Technical failure occurred")
    end
  end
end
