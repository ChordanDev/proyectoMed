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
       for active `station_id` and `version`. Natural-language prose strings
       fail closed to Jev verification. Only explicit, executable predicates
       (e.g., "unconditional" or executable functions evaluating to `true`) bypass Jev.
       Shortness, tone, or model-provided IDs never authorize a bypass.
    3. **Jev verification**:
       Every non-bypassed candidate is verified via `Backend.Stations.JevDecision.decide_patient/2`.
       Verified candidates are delivered (`{:ok, candidate_text}`).
       Technical errors are returned immediately as typed error tuples without fallback text.
    4. **Single monotonic semantic retry**:
       A candidate refused for `:semantic_refusal` or `:low_confidence` permits at most
       one regeneration within the remaining monotonic deadline budget.
       The regenerated candidate undergoes the full recheck (deny -> template -> Jev).
       If the second candidate fails for any reason, no text is released and
       `{:error, {:refused, status}}` or `{:error, reason}` is returned.

  ## Security & No-Leak Invariants

    * Rejected or unverified patient text is NEVER returned, added to trusted history,
      or passed into the regeneration prompt.
    * Learner input is treated as untrusted evidence.
    * Errors are sanitized without leaking candidate text or learner audio/text.
  """

  alias Backend.Stations.JevDecision
  alias Backend.Stations.StationAI.BoundedReply

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
    conversation = conversation || []
    deadline_at = resolve_monotonic_deadline(opts)

    with :ok <- BoundedReply.check_violations(candidate_text, package) do
      if template_bypass?(candidate_text, package, opts) do
        {:ok, candidate_text}
      else
        verify_with_jev(candidate_text, package, conversation, deadline_at, opts)
      end
    end
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
    * Applicability must be an explicit executable predicate evaluating to true.
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
  Returns `{:error, reason}` if not matched, identity mismatch, or unexecutable prose.
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

      # Template-embedded executable function
      is_function(applicability, 1) ->
        case_state = opts[:case_state] || opts[:context] || %{}

        if applicability.(case_state) == true do
          :ok
        else
          {:error, :applicability_predicate_false}
        end

      # Explicit unconditional literal
      applicability == "unconditional" ->
        :ok

      applicability === true ->
        :ok

      applicability == %{"type" => "unconditional"} or applicability == %{type: "unconditional"} ->
        :ok

      # Option B: Natural-language prose strings NEVER bypass Jev
      is_binary(applicability) ->
        {:error, :unexecutable_prose_applicability}

      # Missing or unexecutable: fail closed
      true ->
        {:error, :unexecutable_applicability}
    end
  end

  # ============================================================================
  # Jev Verification & Monotonic Retry
  # ============================================================================

  defp verify_with_jev(candidate_text, package, conversation, deadline_at, opts) do
    if JevDecision.remaining_budget_ms(deadline_at) <= 0 do
      {:error, :timeout}
    else
      jev_request = %{
        candidate_text: candidate_text,
        package: package,
        conversation: conversation,
        deadline_at_monotonic_ms: deadline_at
      }

      jev_opts = Keyword.put(opts, :deadline_at_monotonic_ms, deadline_at)

      case JevDecision.decide_patient(jev_request, jev_opts) do
        {:ok, %{status: :verified}} ->
          {:ok, candidate_text}

        {:ok, %{status: status}} when status in [:semantic_refusal, :low_confidence] ->
          handle_refusal(status, package, conversation, deadline_at, opts)

        {:error, reason} ->
          # Technical failures (:timeout, {:adapter_disabled, _}, {:upstream_5xx, _}, etc.)
          # are returned immediately without converting to uncertainty or fallback.
          {:error, reason}
      end
    end
  end

  defp handle_refusal(status, package, conversation, deadline_at, opts) do
    retry_count = Keyword.get(opts, :retry_count, 0)
    can_retry? = Keyword.get(opts, :can_retry?, true)

    if can_retry? and retry_count == 0 do
      attempt_regeneration(package, conversation, deadline_at, opts)
    else
      {:error, {:refused, status}}
    end
  end

  defp attempt_regeneration(package, conversation, deadline_at, opts) do
    if JevDecision.remaining_budget_ms(deadline_at) <= 0 do
      {:error, :timeout}
    else
      generator = opts[:generator]

      case invoke_generator(generator, package, conversation, deadline_at) do
        {:ok, regen_text} ->
          if JevDecision.remaining_budget_ms(deadline_at) <= 0 do
            {:error, :timeout}
          else
            recheck_regenerated(regen_text, package, conversation, deadline_at, opts)
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp recheck_regenerated(regen_text, package, conversation, deadline_at, opts) do
    recheck_opts =
      opts
      |> Keyword.put(:retry_count, 1)
      |> Keyword.put(:can_retry?, false)
      |> Keyword.put(:deadline_at_monotonic_ms, deadline_at)

    with :ok <- BoundedReply.check_violations(regen_text, package) do
      if template_bypass?(regen_text, package, recheck_opts) do
        {:ok, regen_text}
      else
        if JevDecision.remaining_budget_ms(deadline_at) <= 0 do
          {:error, :timeout}
        else
          jev_request = %{
            candidate_text: regen_text,
            package: package,
            conversation: conversation,
            deadline_at_monotonic_ms: deadline_at
          }

          case JevDecision.decide_patient(jev_request, recheck_opts) do
            {:ok, %{status: :verified}} ->
              {:ok, regen_text}

            {:ok, %{status: second_status}}
            when second_status in [:semantic_refusal, :low_confidence] ->
              {:error, {:refused, second_status}}

            {:error, reason} ->
              {:error, reason}
          end
        end
      end
    end
  end

  defp invoke_generator(generator, package, conversation, deadline_at) do
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

            is_nil(generator) ->
              Backend.Stations.StationAI.next_reply(package, %{conversation: conversation})

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
