defmodule Backend.Stations.RubricAssessment do
  @moduledoc """
  Grounded rubric assessment of a completed session (issue #128, ADR-012).

  `assess/3` runs one deterministic pipeline over the v2 rubric, in rubric
  order:

    1. **Triage without Jev.** An authored exclusion is `:not_applicable`; a
       criterion whose required modality the station cannot provide is
       `:not_observable`. Every other criterion becomes a question.
    2. **One evidence pool** is built from the session and shared by every
       question. Only verified items are offered to Jev, while citations are
       checked against the full pool.
    3. **One batched Jev call** carries every question. More calls happen only
       for a provider capacity limit (`:max_questions_per_call`), and every
       call is recorded with its justification.
    4. **Deterministic post-processing** validates each cited evidence
       identifier and fails closed per criterion: nothing is repaired, dropped
       or substituted.

  A technical failure of any call, or a rubric that cannot be converted to
  exact points, invalidates the whole attempt: no partial criteria are
  returned.

  Only `:assessed` criteria carry `:level` and `:points`. Points are exact
  integer eighths (`Backend.Stations.RubricAssessment.Points`); no probability
  or confidence ever multiplies or adjusts them.

  The authored rule fields change the level only through
  `apply_authored_rules/2`, which delegates the per-criterion rules (action
  roles, thresholds and `count_cap`) to
  `Backend.Stations.RubricAssessment.AuthoredRules`. A criterion that authors
  none of them keeps the level Jev chose. `order`, `first_n` and the
  `task_order` rule are not applied yet.
  """

  alias Backend.Stations.JevDecision
  alias Backend.Stations.JevDecision.RubricBatch
  alias Backend.Stations.RubricAssessment.AuthoredRules
  alias Backend.Stations.RubricAssessment.Estimates
  alias Backend.Stations.RubricAssessment.Evidence
  alias Backend.Stations.RubricAssessment.Points

  @uncertain_class "uncertain"
  @own_opts [:max_questions_per_call]

  @typedoc "Why a criterion that is not assessed has no level."
  @type reason ::
          :authored_exclusion
          | Evidence.providability_error()
          | :classifier_uncertain
          | :unsupported_credit
          | {:invalid_evidence, Evidence.rejection(), term()}
          | AuthoredRules.uncertainty()

  @typedoc "A pool item as reported on a criterion result."
  @type evidence_excerpt :: %{id: String.t(), role: term(), text: String.t()}

  @typedoc "The decision of one authored action, with validated evidence in pool order."
  @type sub_action :: %{id: String.t(), classification: String.t(), evidence_ids: [String.t()]}

  @typedoc """
  The result of one criterion. `:level` (the authored label) and `:points` are
  present only when the status is `:assessed`; `:reason` is `nil` only then.
  """
  @type criterion_result :: %{
          required(:id) => String.t(),
          required(:status) => Estimates.status(),
          required(:max_points) => Points.t(),
          required(:evidence_ids) => [String.t()],
          required(:evidence) => [evidence_excerpt()],
          required(:reason) => reason() | nil,
          required(:sub_actions) => [sub_action()],
          required(:recommendation) => String.t(),
          optional(:level) => String.t(),
          optional(:points) => Points.t()
        }

  @typedoc "One Jev call and why it was made."
  @type call :: %{
          question_count: pos_integer(),
          justification: :single_batch | :provider_capacity
        }

  @typedoc "The assessment of one attempt."
  @type t :: %{criteria: [criterion_result()], estimates: Estimates.t(), calls: [call()]}

  @typedoc "An authoring defect that prevents exact, unambiguous assessment."
  @type package_error ::
          {:invalid_package, term(),
           Estimates.max_points_error()
           | :invalid_level_labels
           | :duplicate_criterion_id
           | AuthoredRules.authoring_error()}

  @typedoc "Why an attempt is invalid as a whole."
  @type attempt_error :: package_error() | JevDecision.rubric_batch_error()

  @typedoc "The legacy evaluator shape (`Backend.Stations.Evaluator`)."
  @type legacy :: %{
          criteria: [
            %{
              id: String.t(),
              status: :met | :omitted | :uncertain,
              evidence: [%{role: term(), text: String.t()}],
              recommendation: String.t()
            }
          ]
        }

  @typep route :: :ask | {:skip, :not_applicable | :not_observable, reason()}

  @typep plan :: %{
           id: term(),
           criterion: map(),
           max_points: Points.t(),
           requirement: Evidence.requirement(),
           route: route()
         }

  @typep level :: %{label: String.t(), points: Points.t()}

  @typep draft :: %{level: level(), evidence: [Evidence.item()], sub_actions: [sub_action()]}

  @doc """
  Assesses a completed session against the rubric of its v2 Station Package.

  `package` is the decoded package (string keys). `session` is the completed
  session map with `messages` and, optionally, `impresso_requests`. `opts` are
  passed to `Backend.Stations.JevDecision.decide_rubric_batch/2` (`:adapter`
  and the deadline options), except `:max_questions_per_call`, a positive
  integer that caps the questions of one call.

  Returns criterion results in rubric order, the point estimates and the Jev
  calls made, or `{:error, {:invalid_attempt, reason}}` with no criteria when a
  call fails technically or the rubric has an authoring defect.
  """
  @spec assess(map(), map(), keyword()) ::
          {:ok, t()} | {:error, {:invalid_attempt, attempt_error()}}
  def assess(package, session, opts \\ [])
      when is_map(package) and is_map(session) and is_list(opts) do
    pool = Evidence.build(session, package)

    with {:ok, plans} <- triage(package),
         {:ok, decisions, calls} <- ask(questions(plans), pool, opts) do
      criteria = Enum.map(plans, &criterion_result(&1, decisions, pool))
      {:ok, %{criteria: criteria, estimates: Estimates.estimate(criteria), calls: calls}}
    else
      {:error, reason} -> {:error, {:invalid_attempt, reason}}
    end
  end

  @doc """
  Projects an assessment to the legacy evaluator shape, as the explicit
  migration path while the HTTP result contract stays on that shape.

  A criterion assessed at a zero-point level is `:omitted`, one assessed above
  zero is `:met`, `:uncertain` and `:not_observable` are `:uncertain`, and
  `:not_applicable` criteria are dropped.
  """
  @spec to_legacy(t()) :: legacy()
  def to_legacy(%{criteria: criteria}) do
    %{
      criteria:
        for(
          %{status: status} = result <- criteria,
          status != :not_applicable,
          do: legacy_criterion(result)
        )
    }
  end

  # ============================================================================
  # Triage
  # ============================================================================

  @spec triage(map()) :: {:ok, [plan()]} | {:error, package_error()}
  defp triage(package) do
    rubric = package |> Map.get("rubric") |> List.wrap()

    with {:ok, plans} <- map_ok(rubric, &plan(&1, package)),
         :ok <- unique_ids(plans) do
      {:ok, plans}
    end
  end

  defp plan(criterion, package) when is_map(criterion) do
    id = Map.get(criterion, "id")

    with {:ok, max_points} <- Estimates.max_points(criterion),
         :ok <- check_level_labels(criterion),
         :ok <- AuthoredRules.check(criterion) do
      requirement = Evidence.requirement(criterion)

      {:ok,
       %{
         id: id,
         criterion: criterion,
         max_points: max_points,
         requirement: requirement,
         route: route(criterion, requirement, package)
       }}
    else
      {:error, reason} -> {:error, {:invalid_package, id, reason}}
    end
  end

  defp plan(_criterion, _package), do: {:error, {:invalid_package, nil, :no_levels}}

  @spec route(map(), Evidence.requirement(), map()) :: route()
  defp route(%{"exclusion" => true}, _requirement, _package) do
    {:skip, :not_applicable, :authored_exclusion}
  end

  defp route(_criterion, requirement, package) do
    case Evidence.providability(requirement, package) do
      :ok -> :ask
      {:error, reason} -> {:skip, :not_observable, reason}
    end
  end

  # A label is the class Jev answers with, so it must identify exactly one level
  # and must not collide with the reserved uncertainty class.
  defp check_level_labels(criterion) do
    labels = level_labels(criterion)

    valid? =
      Enum.all?(labels, &(is_binary(&1) and String.trim(&1) != "")) and
        Enum.uniq(labels) == labels and @uncertain_class not in labels

    if valid?, do: :ok, else: {:error, :invalid_level_labels}
  end

  defp unique_ids(plans) do
    ids = Enum.map(plans, & &1.id)

    case ids -- Enum.uniq(ids) do
      [] -> :ok
      [id | _rest] -> {:error, {:invalid_package, id, :duplicate_criterion_id}}
    end
  end

  # ============================================================================
  # Question composition
  # ============================================================================

  @spec questions([plan()]) :: [RubricBatch.question()]
  defp questions(plans) do
    for %{route: :ask} = plan <- plans, do: question(plan)
  end

  defp question(%{id: id, criterion: criterion}) do
    %{
      criterion: %{id: id, description: compose_description(criterion)},
      allowed_classes: level_labels(criterion) ++ [@uncertain_class],
      actions: authored_actions(criterion)
    }
  end

  # The authored description, then the evidence questions and one line per
  # level, so the classifier can pick a level by its label.
  defp compose_description(criterion) do
    evidence_questions =
      for question <- list(criterion, "evidence_questions"), is_binary(question), do: question

    levels =
      for level <- list(criterion, "levels") do
        "#{level["label"]}: #{level["description"]}"
      end

    [to_string(criterion["description"])]
    |> Kernel.++(section("Evidence questions:", evidence_questions))
    |> Kernel.++(section("Levels:", levels))
    |> Enum.join("\n")
  end

  defp section(_title, []), do: []
  defp section(title, lines), do: [title | Enum.map(lines, &"- #{&1}")]

  defp authored_actions(criterion) do
    for %{} = action <- list(criterion, "actions") do
      %{id: action["id"], description: action["description"] || ""}
    end
  end

  defp level_labels(criterion), do: criterion |> list("levels") |> Enum.map(&label/1)

  defp label(%{"label" => label}), do: label
  defp label(_level), do: nil

  # ============================================================================
  # Batching
  # ============================================================================

  @spec ask([RubricBatch.question()], Evidence.pool(), keyword()) ::
          {:ok, %{optional(String.t()) => RubricBatch.decision()}, [call()]}
          | {:error, JevDecision.rubric_batch_error()}
  defp ask([], _pool, _opts), do: {:ok, %{}, []}

  defp ask(questions, pool, opts) do
    evidence_pool = pool |> Enum.reject(&(&1.provenance == :unverified)) |> Evidence.jev_view()
    jev_opts = Keyword.drop(opts, @own_opts)

    questions
    |> chunks(opts[:max_questions_per_call])
    |> Enum.reduce_while({:ok, %{}, []}, fn chunk, {:ok, decisions, calls} ->
      request = %{questions: chunk, evidence_pool: evidence_pool}

      case JevDecision.decide_rubric_batch(request, jev_opts) do
        {:ok, answered} ->
          {:cont, {:ok, index(answered, decisions), calls ++ [call(chunk, calls)]}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  # One call unless the provider capacity is set and exceeded.
  defp chunks(questions, max) when is_integer(max) and max > 0 do
    Enum.chunk_every(questions, max)
  end

  defp chunks(questions, _no_limit), do: [questions]

  defp call(chunk, []), do: %{question_count: length(chunk), justification: :single_batch}

  defp call(chunk, _earlier),
    do: %{question_count: length(chunk), justification: :provider_capacity}

  defp index(answered, decisions) do
    Enum.reduce(answered, decisions, &Map.put(&2, &1.criterion_id, &1))
  end

  # ============================================================================
  # Deterministic post-processing
  # ============================================================================

  @spec criterion_result(plan(), map(), Evidence.pool()) :: criterion_result()
  defp criterion_result(%{route: {:skip, status, reason}} = plan, _decisions, _pool) do
    unscored(plan, status, reason)
  end

  defp criterion_result(plan, decisions, pool) do
    case judge(plan, Map.fetch!(decisions, plan.id), pool) do
      {:assessed, draft} -> assessed(plan, draft)
      {:uncertain, reason} -> unscored(plan, :uncertain, reason)
    end
  end

  @spec judge(plan(), RubricBatch.decision(), Evidence.pool()) ::
          {:assessed, draft()} | {:uncertain, reason()}
  defp judge(_plan, %{classification: @uncertain_class}, _pool) do
    {:uncertain, :classifier_uncertain}
  end

  defp judge(%{criterion: criterion, requirement: requirement}, decision, pool) do
    with {:ok, evidence} <- Evidence.validate(pool, decision.evidence_ids, requirement),
         {:ok, sub_actions} <- sub_actions(decision.actions, pool, requirement) do
      draft = %{
        level: level(criterion, decision.classification),
        evidence: evidence,
        sub_actions: sub_actions
      }

      with {:ok, ruled} <- apply_authored_rules(criterion, draft), do: grounded(ruled)
    else
      {:error, {rejection, id}} -> {:uncertain, {:invalid_evidence, rejection, id}}
      {:uncertain, _reason} = uncertain -> uncertain
    end
  end

  @doc false
  # T5 seam (issue #128): the only place where the authored rule fields may
  # change the level of a criterion whose evidence already validated. The
  # sub-action evidence in the draft went through the same validation as the
  # criterion evidence, so the rules need no access to the pool.
  @spec apply_authored_rules(map(), draft()) :: {:ok, draft()} | {:uncertain, reason()}
  defp apply_authored_rules(criterion, %{level: level, sub_actions: sub_actions} = draft) do
    with {:ok, ruled_level} <- AuthoredRules.decide_level(criterion, level, sub_actions) do
      {:ok, %{draft | level: ruled_level}}
    end
  end

  # Credit is never awarded without grounded learner evidence; a zero-point
  # level needs none, because a genuine omission leaves nothing to cite.
  defp grounded(%{level: %{points: points}, evidence: []}) when points > 0 do
    {:uncertain, :unsupported_credit}
  end

  defp grounded(draft), do: {:assessed, draft}

  defp sub_actions(action_decisions, pool, requirement) do
    map_ok(action_decisions, fn action ->
      with {:ok, evidence} <- Evidence.validate(pool, action.evidence_ids, requirement) do
        {:ok,
         %{
           id: action.id,
           classification: action.classification,
           evidence_ids: Evidence.ids(evidence)
         }}
      end
    end)
  end

  # The classification is one of the authored labels (the batch contract
  # rejects any other class) and every level already converted to exact points.
  defp level(criterion, label) do
    authored = criterion |> list("levels") |> Enum.find(&(label(&1) == label))
    {:ok, points} = Points.from_authored(authored["points"])

    %{label: label, points: points}
  end

  defp assessed(plan, %{level: level, evidence: evidence, sub_actions: sub_actions}) do
    plan
    |> base_result(:assessed, nil)
    |> Map.merge(%{
      level: level.label,
      points: level.points,
      evidence_ids: Evidence.ids(evidence),
      evidence: Enum.map(evidence, &Map.take(&1, [:id, :role, :text])),
      sub_actions: sub_actions
    })
  end

  defp unscored(plan, status, reason), do: base_result(plan, status, reason)

  defp base_result(%{id: id, criterion: criterion, max_points: max_points}, status, reason) do
    %{
      id: id,
      status: status,
      max_points: max_points,
      evidence_ids: [],
      evidence: [],
      reason: reason,
      sub_actions: [],
      recommendation: criterion["practice_recommendation"] || ""
    }
  end

  # ============================================================================
  # Legacy projection
  # ============================================================================

  defp legacy_criterion(result) do
    %{
      id: result.id,
      status: legacy_status(result),
      evidence: Enum.map(result.evidence, &Map.take(&1, [:role, :text])),
      recommendation: result.recommendation
    }
  end

  defp legacy_status(%{status: :assessed, points: 0}), do: :omitted
  defp legacy_status(%{status: :assessed}), do: :met
  defp legacy_status(_unresolved), do: :uncertain

  # ============================================================================
  # Helpers
  # ============================================================================

  defp list(criterion, key) do
    case Map.get(criterion, key) do
      entries when is_list(entries) -> entries
      _missing -> []
    end
  end

  defp map_ok(items, fun) do
    result =
      Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
        case fun.(item) do
          {:ok, value} -> {:cont, {:ok, [value | acc]}}
          {:error, _reason} = error -> {:halt, error}
        end
      end)

    with {:ok, reversed} <- result, do: {:ok, Enum.reverse(reversed)}
  end
end
