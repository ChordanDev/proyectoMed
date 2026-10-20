defmodule Backend.Stations.CandidateGate do
  @moduledoc """
  Candidate verification gate for patient responses.

  Enforces the dialogue safety pipeline defined in ADR-011 (#123) and ADR-012 (#124):

    1. **Deny-first check**: Deterministic rules (malformed, roleplay leakage,
       pt-BR language containment, package response rules) run first via
       `Backend.Stations.StationAI.BoundedReply.check_violations/2`. Any violation
       immediately rejects the candidate without clinical refusal or text release.
    2. **Approved template check (Option B fail-closed)**:
       Exact byte-identical match against `package["approved_templates"]`
       for active `station_id` and `version`. Applicability must be a
       structured, machine-evaluable predicate from the vocabulary in
       `Backend.Stations.TemplateApplicability` evaluating to `true` against
       trusted case state (`opts[:case_state]`, never the AI `context` map).
       Legacy deterministic literals (the `"unconditional"` string, `true`,
       and the `unconditional` map) remain accepted as defense in depth.
       Prose strings, malformed maps, unknown predicates, and predicates
       evaluating `false` fail closed to Jev verification. Shortness, tone, or
       model-provided IDs never authorize a bypass.
    3. **Jev verification**:
       Every non-bypassed candidate is verified via `Backend.Stations.JevDecision.decide_patient/2`.
       Verified candidates are delivered (`{:ok, candidate_text}`).
       Technical errors are returned immediately as typed error tuples without fallback text.
    4. **Single monotonic semantic retry**:
       A candidate refused for `:semantic_refusal` or `:low_confidence` permits at most
       one regeneration within the remaining monotonic deadline budget.
       The regenerated candidate undergoes the full recheck (deny -> template -> Jev).
       When Jev reports `unasked_fact_ids` (on-request facts stated without being
       asked, issue #242), the regeneration is targeted: an arity-4 generator
       `(package, conversation, remaining_ms, guidance)` receives
       `%{withheld_fact_ids: ids}`, and the default generator puts the same ids in
       the StationAI context. A `:low_confidence` refusal that Jev reports with
       `undecided_fact_ids` (on-request facts it could not tell were stated while the
       learner did not ask, issue #273, or stated facts it could not tell the
       learner asked for, issue #284) is targeted the same way with those ids.
       Every other refusal passes `withheld_fact_ids: []`, so the retry is unchanged. Generators of arity 0 to 3 receive no guidance.
       If the second candidate fails for any reason, no text is released and
       `{:error, {:refused, status}}` or `{:error, reason}` is returned.
       When the regeneration runs out of budget (before or during generation,
       or while it is verified), the original `{:error, {:refused, status}}` is
       returned instead of `{:error, :timeout}` (issue #256), so the learner
       turn is kept (#235). A timeout before any refusal stays `{:error, :timeout}`.

  ## Refusal causes (issue #273)

  Every Jev decision on a candidate, the regenerated one included, is counted
  node-wide by cause, so the false-refusal rate can be tracked:
  `:verified`; `:unasked_fact` (a semantic refusal naming `unasked_fact_ids`,
  even when a risk is also high); `:risk` (any other semantic refusal: a risk or
  a response rule); `:undecided_unasked_fact` (a low-confidence decision naming
  `undecided_fact_ids`); `:undecided_other` (any other low-confidence decision).
  `refusal_cause_counts/0` reads the counts, which restart with the node. Each
  refusal also logs one `:info` line, `[CandidateGate] refusal cause=<cause>
  count=<n>`, with no text and no fact id.

  ## Security & No-Leak Invariants

    * Rejected or unverified patient text is NEVER returned, added to trusted history,
      or passed into the regeneration prompt.
    * Learner input is treated as untrusted evidence.
    * Errors are sanitized without leaking candidate text or learner audio/text.
  """

  require Logger

  alias Backend.Stations.JevDecision
  alias Backend.Stations.StationAI.BoundedReply
  alias Backend.Stations.TemplateApplicability

  @decision_causes [:verified, :risk, :unasked_fact, :undecided_unasked_fact, :undecided_other]
  @counts_key {__MODULE__, :decision_cause_counts}

  @type candidate_error ::
          {:denied, atom()}
          | {:refused, :semantic_refusal | :low_confidence}
          | JevDecision.technical_failure()
          | term()

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Verifies a candidate patient reply and delivers it if verified or bypassed.

  Returns `{:ok, text}` if verified by Jev or bypassed via an approved template.
  Returns `{:error, {:denied, reason}}` if deterministic deny checks fire.
  Returns `{:error, {:refused, status}}` if refused and retry budget is exhausted.
  Returns `{:error, reason}` on technical failure or timeout.
  """
  @spec verify_and_deliver(term(), map(), list(), keyword()) ::
          {:ok, String.t()} | {:error, candidate_error()}
  def verify_and_deliver(candidate_text, package, conversation \\ [], opts \\ [])
      when is_list(opts) do
    with {:ok, %{text: text}} <- verify(candidate_text, package, conversation, opts) do
      {:ok, text}
    end
  end

  @doc """
  Verifies a candidate like `verify_and_deliver/4` and also returns the facts the
  delivered text states (issue #286): `{:ok, %{text: text, used_fact_ids: ids}}`.

  `used_fact_ids` are the authored ids of the Jev verdict that verified `text`
  (the regeneration's verdict when the regeneration is delivered), and `[]` for
  an approved-template bypass. `opts[:disclosed_fact_ids]`, the facts earlier
  verified patient turns of the session disclosed, is passed to every Jev
  request.
  """
  @spec verify(term(), map(), list(), keyword()) ::
          {:ok, %{text: String.t(), used_fact_ids: [String.t()]}}
          | {:error, candidate_error()}
  def verify(candidate_text, package, conversation \\ [], opts \\ []) when is_list(opts) do
    conversation = conversation || []
    deadline_at = resolve_monotonic_deadline(opts)

    with :ok <- BoundedReply.check_violations(candidate_text, package) do
      if template_bypass?(candidate_text, package, opts) do
        {:ok, delivered(candidate_text, %{})}
      else
        verify_with_jev(candidate_text, package, conversation, deadline_at, opts)
      end
    end
  end

  defp delivered(text, decision) do
    ids =
      case Map.get(decision, :used_fact_ids) do
        ids when is_list(ids) -> Enum.filter(ids, &is_binary/1)
        _ -> []
      end

    %{text: text, used_fact_ids: ids}
  end

  defp patient_jev_request(candidate_text, package, conversation, deadline_at, opts) do
    %{
      candidate_text: candidate_text,
      package: package,
      conversation: conversation,
      deadline_at_monotonic_ms: deadline_at,
      disclosed_fact_ids: Keyword.get(opts, :disclosed_fact_ids, [])
    }
  end

  @doc """
  Convenience alias for `verify_and_deliver/4`.
  """
  @spec verify_patient_reply(term(), map(), list(), keyword()) ::
          {:ok, String.t()} | {:error, candidate_error()}
  def verify_patient_reply(candidate_text, package, conversation \\ [], opts \\ []) do
    verify_and_deliver(candidate_text, package, conversation, opts)
  end

  @doc """
  Returns how many Jev decisions on candidates each cause has had since the node
  started (see "Refusal causes"). Holds only cause names and counts.
  """
  @spec refusal_cause_counts() :: %{atom() => non_neg_integer()}
  def refusal_cause_counts do
    ref = cause_counters()

    @decision_causes
    |> Enum.with_index(1)
    |> Map.new(fn {cause, index} -> {cause, :counters.get(ref, index)} end)
  end

  @doc """
  Delegates deny-first violation checks to `BoundedReply.check_violations/2`.
  """
  defdelegate check_violations(text, package), to: BoundedReply

  # ============================================================================
  # Approved Template Check (Option B Fail-Closed)
  # ============================================================================

  @doc """
  Determines whether `candidate_text` qualifies for an approved template bypass.

  Under Option B (fail closed):
    * Text must match an entry in `package["approved_templates"]` byte-identically.
    * Active `station_id` and `version` must match.
    * Applicability must be a structured predicate (see `Backend.Stations.TemplateApplicability`)
      evaluating to true against trusted case state. Structured predicates read
      only `opts[:case_state]`, never the AI `context` map.
      Natural-language prose strings fail closed and return `false`.
    * Model-provided IDs, shortness, or tone never authorize a bypass.
  """
  @spec template_bypass?(term(), map(), keyword()) :: boolean()
  def template_bypass?(candidate_text, package, opts \\ []) do
    match?({:ok, _template}, check_approved_template(candidate_text, package, opts))
  end

  @doc """
  Validates candidate text against approved templates in `package`.

  Returns `{:ok, template}` if byte-identical and applicability predicate evaluates to true.
  Returns `{:error, reason}` if not matched, identity mismatch, predicate false,
  or unexecutable (prose/missing) applicability.
  """
  @spec check_approved_template(term(), map(), keyword()) ::
          {:ok, map()} | {:error, atom()}
  def check_approved_template(candidate_text, package, opts \\ [])

  def check_approved_template(text, package, opts)
      when is_binary(text) and is_map(package) and is_list(opts) do
    templates = Map.get(package, "approved_templates") || Map.get(package, :approved_templates)

    with true <- is_list(templates) and templates != [],
         :ok <- validate_package_identity(package, opts),
         {:ok, template} <- find_byte_identical_template(templates, text),
         :ok <- validate_template_id_if_provided(template, opts),
         :ok <- check_template_applicability(template, opts) do
      {:ok, template}
    else
      false ->
        {:error, :no_templates}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def check_approved_template(_text, _package, _opts) do
    {:error, :invalid_input}
  end

  defp validate_package_identity(package, opts) do
    pkg_id = to_string(Map.get(package, "station_id") || Map.get(package, :station_id) || "")
    pkg_ver = to_string(Map.get(package, "version") || Map.get(package, :version) || "")

    expected_id = opts[:station_id] || opts[:package_id]
    expected_ver = opts[:version] || opts[:package_version]

    cond do
      pkg_id == "" or pkg_ver == "" ->
        {:error, :missing_package_identity}

      expected_id != nil and to_string(expected_id) != pkg_id ->
        {:error, :station_id_mismatch}

      expected_ver != nil and to_string(expected_ver) != pkg_ver ->
        {:error, :version_mismatch}

      true ->
        :ok
    end
  end

  defp find_byte_identical_template(templates, text) do
    case Enum.find(templates, fn
           %{"text" => t_text} -> t_text === text
           %{text: t_text} -> t_text === text
           _ -> false
         end) do
      nil -> {:error, :no_matching_template}
      template -> {:ok, template}
    end
  end

  defp validate_template_id_if_provided(template, opts) do
    case opts[:template_id] do
      nil ->
        :ok

      expected_id ->
        actual_id = Map.get(template, "template_id") || Map.get(template, :template_id)

        if to_string(actual_id) == to_string(expected_id) do
          :ok
        else
          {:error, :template_id_mismatch}
        end
    end
  end

  defp check_template_applicability(template, opts) do
    applicability = Map.get(template, "applicability") || Map.get(template, :applicability)

    cond do
      # Caller-supplied predicate evaluator function
      is_function(opts[:predicate_evaluator], 2) ->
        if opts[:predicate_evaluator].(template, opts) == true do
          :ok
        else
          {:error, :applicability_predicate_false}
        end

      is_function(opts[:predicate_evaluator], 1) ->
        if opts[:predicate_evaluator].(template) == true do
          :ok
        else
          {:error, :applicability_predicate_false}
        end

      # Template-embedded executable function (test hatch)
      is_function(applicability, 1) ->
        case_state = opts[:case_state] || opts[:context] || %{}

        if applicability.(case_state) == true do
          :ok
        else
          {:error, :applicability_predicate_false}
        end

      # Structured predicate map: evaluates ONLY against trusted case state,
      # never the AI `context` map (issue #147). The unconditional map literal
      # is part of the vocabulary, so legacy map literals stay accepted here.
      is_map(applicability) ->
        apply_structured_applicability(applicability, opts)

      # Legacy deterministic literals (defense in depth)
      applicability == "unconditional" ->
        :ok

      applicability === true ->
        :ok

      # Option B: Natural-language prose strings NEVER bypass Jev
      is_binary(applicability) ->
        {:error, :unexecutable_prose_applicability}

      # Missing or unexecutable: fail closed
      true ->
        {:error, :unexecutable_applicability}
    end
  end

  defp apply_structured_applicability(applicability, opts) do
    case_state = opts[:case_state] || %{}

    if TemplateApplicability.evaluate(applicability, case_state) == true do
      :ok
    else
      {:error, :applicability_predicate_false}
    end
  end

  # ============================================================================
  # Jev Verification & Monotonic Retry
  # ============================================================================

  defp verify_with_jev(candidate_text, package, conversation, deadline_at, opts) do
    if JevDecision.remaining_budget_ms(deadline_at) <= 0 do
      {:error, :timeout}
    else
      jev_request =
        patient_jev_request(candidate_text, package, conversation, deadline_at, opts)

      jev_opts = Keyword.put(opts, :deadline_at_monotonic_ms, deadline_at)

      case jev_request |> JevDecision.decide_patient(jev_opts) |> count_cause() do
        {:ok, %{status: :verified} = decision} ->
          {:ok, delivered(candidate_text, decision)}

        {:ok, %{status: status} = decision}
        when status in [:semantic_refusal, :low_confidence] ->
          handle_refusal(
            status,
            regeneration_guidance(decision),
            package,
            conversation,
            deadline_at,
            opts
          )

        {:error, reason} ->
          # Technical failures (:timeout, {:adapter_disabled, _}, {:upstream_5xx, _}, etc.)
          # are returned immediately without converting to uncertainty or fallback.
          {:error, reason}
      end
    end
  end

  # The guidance names facts only by authored ids: those Jev reported as stated
  # without being asked (issue #242), or, on a low-confidence decision, those it
  # could not tell were stated while the learner did not ask (issue #273). It
  # never carries Jev or candidate text.
  defp regeneration_guidance(decision) do
    key =
      case decision.status do
        :semantic_refusal -> :unasked_fact_ids
        :low_confidence -> :undecided_fact_ids
      end

    case Map.get(decision, key) do
      ids when is_list(ids) -> %{withheld_fact_ids: Enum.filter(ids, &is_binary/1)}
      _ -> %{withheld_fact_ids: []}
    end
  end

  defp handle_refusal(status, guidance, package, conversation, deadline_at, opts) do
    retry_count = Keyword.get(opts, :retry_count, 0)
    can_retry? = Keyword.get(opts, :can_retry?, true)

    if can_retry? and retry_count == 0 do
      guidance
      |> attempt_regeneration(package, conversation, deadline_at, opts)
      |> keep_refusal_on_timeout(status)
    else
      {:error, {:refused, status}}
    end
  end

  # Issue #256: when the regeneration cannot finish inside the budget (before
  # or during generation, or while it is verified), the turn ends with the
  # original refusal, so the caller keeps the learner turn (#235). Nothing of
  # the late candidate is returned. Any other regeneration failure is unchanged.
  defp keep_refusal_on_timeout({:error, :timeout}, status), do: {:error, {:refused, status}}
  defp keep_refusal_on_timeout(result, _status), do: result

  defp attempt_regeneration(guidance, package, conversation, deadline_at, opts) do
    with :ok <- check_regeneration_budget(deadline_at),
         generator = opts[:generator],
         {:ok, regen_text} <-
           invoke_generator(generator, guidance, package, conversation, deadline_at),
         :ok <- check_regeneration_budget(deadline_at) do
      recheck_regenerated(regen_text, package, conversation, deadline_at, opts)
    end
  end

  defp check_regeneration_budget(deadline_at) do
    if JevDecision.remaining_budget_ms(deadline_at) <= 0 do
      {:error, :timeout}
    else
      :ok
    end
  end

  defp recheck_regenerated(regen_text, package, conversation, deadline_at, opts) do
    recheck_opts =
      opts
      |> Keyword.put(:retry_count, 1)
      |> Keyword.put(:can_retry?, false)
      |> Keyword.put(:deadline_at_monotonic_ms, deadline_at)

    with :ok <- BoundedReply.check_violations(regen_text, package) do
      recheck_candidate_dispatch(regen_text, package, conversation, deadline_at, recheck_opts)
    end
  end

  defp recheck_candidate_dispatch(regen_text, package, conversation, deadline_at, recheck_opts) do
    if template_bypass?(regen_text, package, recheck_opts) do
      {:ok, delivered(regen_text, %{})}
    else
      recheck_with_jev(regen_text, package, conversation, deadline_at, recheck_opts)
    end
  end

  defp recheck_with_jev(regen_text, package, conversation, deadline_at, recheck_opts) do
    with :ok <- check_regeneration_budget(deadline_at) do
      regen_text
      |> patient_jev_request(package, conversation, deadline_at, recheck_opts)
      |> JevDecision.decide_patient(recheck_opts)
      |> count_cause()
      |> eval_recheck_jev_result(regen_text)
    end
  end

  # ============================================================================
  # Refusal Causes
  # ============================================================================

  # Counts the decision's cause and returns the result unchanged. Errors are
  # technical failures, not decisions, and are not counted.
  defp count_cause({:ok, %{status: status} = decision} = result)
       when status in [:verified, :semantic_refusal, :low_confidence] do
    cause = decision_cause(decision)
    index = Enum.find_index(@decision_causes, &(&1 == cause)) + 1
    ref = cause_counters()
    :counters.add(ref, index, 1)

    if cause != :verified do
      Logger.info("[CandidateGate] refusal cause=#{cause} count=#{:counters.get(ref, index)}")
    end

    result
  end

  defp count_cause(result), do: result

  defp decision_cause(%{status: :verified}), do: :verified

  defp decision_cause(%{status: :semantic_refusal} = decision) do
    if named_fact_ids?(decision, :unasked_fact_ids), do: :unasked_fact, else: :risk
  end

  defp decision_cause(%{status: :low_confidence} = decision) do
    if named_fact_ids?(decision, :undecided_fact_ids),
      do: :undecided_unasked_fact,
      else: :undecided_other
  end

  defp named_fact_ids?(decision, key) do
    case Map.get(decision, key) do
      [_ | _] -> true
      _ -> false
    end
  end

  # The counters live for the node. Two first callers racing may each create a
  # set; the later one wins and at most the other's first count is lost.
  defp cause_counters do
    case :persistent_term.get(@counts_key, nil) do
      nil ->
        ref = :counters.new(length(@decision_causes), [:write_concurrency])
        :persistent_term.put(@counts_key, ref)
        ref

      ref ->
        ref
    end
  end

  defp eval_recheck_jev_result({:ok, %{status: :verified} = decision}, regen_text),
    do: {:ok, delivered(regen_text, decision)}

  defp eval_recheck_jev_result({:ok, %{status: status}}, _text)
       when status in [:semantic_refusal, :low_confidence],
       do: {:error, {:refused, status}}

  defp eval_recheck_jev_result({:error, reason}, _text), do: {:error, reason}

  defp invoke_generator(generator, guidance, package, conversation, deadline_at) do
    remaining_ms = JevDecision.remaining_budget_ms(deadline_at)

    if remaining_ms <= 0 do
      {:error, :timeout}
    else
      result =
        try do
          cond do
            is_function(generator, 0) ->
              generator.()

            is_function(generator, 1) ->
              generator.(remaining_ms)

            is_function(generator, 2) ->
              generator.(package, conversation)

            is_function(generator, 3) ->
              generator.(package, conversation, remaining_ms)

            is_function(generator, 4) ->
              generator.(package, conversation, remaining_ms, guidance)

            is_nil(generator) ->
              language = package["language"] || package[:language] || "pt-BR"

              Backend.Stations.StationAI.next_reply(package, %{
                conversation: conversation,
                language: language,
                withheld_fact_ids: guidance.withheld_fact_ids
              })

            true ->
              {:error, {:invalid_generator, :unsupported_generator_type}}
          end
        rescue
          e -> {:error, {:generator_crash, Exception.message(e)}}
        end

      extract_candidate_text(result)
    end
  end

  defp extract_candidate_text({:ok, %{text: text}}) when is_binary(text), do: {:ok, text}
  defp extract_candidate_text({:ok, %{"text" => text}}) when is_binary(text), do: {:ok, text}
  defp extract_candidate_text({:ok, text}) when is_binary(text), do: {:ok, text}
  defp extract_candidate_text({:error, reason}), do: {:error, reason}
  defp extract_candidate_text(other), do: {:error, {:invalid_generator_output, other}}

  defp resolve_monotonic_deadline(opts) do
    cond do
      deadline_at = opts[:deadline_at_monotonic_ms] ->
        if is_integer(deadline_at), do: deadline_at, else: JevDecision.monotonic_deadline_at()

      deadline_ms = opts[:deadline_ms] ->
        if is_integer(deadline_ms) and deadline_ms > 0,
          do: JevDecision.monotonic_deadline_at(deadline_ms),
          else: JevDecision.monotonic_deadline_at()

      true ->
        JevDecision.monotonic_deadline_at()
    end
  end
end
