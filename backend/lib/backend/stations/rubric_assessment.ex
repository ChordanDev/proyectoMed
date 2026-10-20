defmodule Backend.Stations.RubricAssessment do
  @moduledoc """
  Grounded rubric assessment of a completed session (issue #128, ADR-012).

  `assess/3` runs one deterministic pipeline over the v2 rubric, in rubric
  order:

    1. **Triage without Jev.** An authored exclusion is `:not_applicable`; a
       criterion whose required modality the station cannot provide is
       `:not_observable`. The `task_order` criterion is set aside for step 5.
       Every other criterion becomes a question.
    2. **One evidence pool** is built from the session and shared by every
       question. Only verified items are offered to Jev, while citations are
       checked against the full pool. An action authored with `impresso_ids`
       that a verified request released is decided `"performed"` here
       (`Backend.Stations.RubricAssessment.ImpressoActions`), citing that
       request: it is asked of neither Jev nor the resolver, and a criterion
       whose actions are all decided this way and whose rule fields decide its
       level is not asked at all.
    3. **One batched Jev call** carries every question. More calls happen only
       for a provider capacity limit (`:max_questions_per_call`), and every
       call is recorded with its justification.
    4. **The rubric resolver** (`Backend.Stations.RubricAssessment.Resolver`)
       decides, through its own provider and deadline, only the authored
       actions Jev left `"uncertain"`. Jev's clear answers stay final, a
       positive decision must cite learner evidence that passes validation, and
       a resolver failure leaves those actions `"uncertain"` without
       invalidating the attempt.
       Its `"not_performed"` answers cite nothing, so they never ground a
       zero-point level on their own: when the level is zero only because of
       them (Jev's answers and the rules, with those actions left undecided,
       reach other outcomes too), the criterion is `:uncertain`.
    5. **Deterministic post-processing** validates each cited evidence
       identifier and fails closed per criterion: nothing is repaired, dropped
       or substituted. The one exception is an action authored with
       `interprets_impresso_ids`: a learner cannot interpret an exam before
       receiving it, so its citations that are not learner turns sent after the
       release are dropped, and it is `"not_performed"` when none remains
       (`Backend.Stations.RubricAssessment.InterpretationEvidence`).
    6. **The task-order criterion** (`rule: "task_order"`) is assessed in code
       from the results of the ranked criteria and the position of their
       earliest evidence (`Backend.Stations.RubricAssessment.TaskOrder`). It is
       never a question, and it counts in the totals like any other criterion.

  A technical failure of any call, or a rubric that cannot be converted to
  exact points, invalidates the whole attempt: no partial criteria are
  returned.

  Only `:assessed` criteria carry `:level` and `:points`. Points are exact
  integer fortieths (`Backend.Stations.RubricAssessment.Points`); no probability
  or confidence ever multiplies or adjusts them.

  The authored rule fields change the level only through
  `Backend.Stations.RubricAssessment.AuthoredRules`, which owns the
  per-criterion rules (action roles, thresholds and `count_cap`). A criterion
  that authors none of them keeps the level Jev chose, and stays `:uncertain`
  when Jev chose none.

  `first_n` runs before those rules, through
  `Backend.Stations.RubricAssessment.FirstN`: a criterion that authors it and
  at least one action asks Jev to enumerate the learner's answers, and only the
  first N of them are eligible. Such a criterion must author thresholds; one
  that does not invalidates the attempt. The reported `:sub_actions` stay as
  Jev classified them; the level and its evidence use the eligible ones.
  """

  alias Backend.Stations.JevDecision
  alias Backend.Stations.JevDecision.RubricBatch
  alias Backend.Stations.RubricAssessment.AuthoredRules
  alias Backend.Stations.RubricAssessment.Estimates
  alias Backend.Stations.RubricAssessment.Evidence
  alias Backend.Stations.RubricAssessment.FirstN
  alias Backend.Stations.RubricAssessment.ImpressoActions
  alias Backend.Stations.RubricAssessment.InterpretationEvidence
  alias Backend.Stations.RubricAssessment.Points
  alias Backend.Stations.RubricAssessment.Resolver
  alias Backend.Stations.RubricAssessment.TaskOrder

  @uncertain_class "uncertain"
  @not_performed_class "not_performed"
  @task_order "task_order"
  @own_opts [
    :max_questions_per_call,
    :resolver_adapter,
    :resolver_opts,
    :rubric_resolver_deadline_ms
  ]

  @typedoc "Why a criterion that is not assessed has no level."
  @type reason ::
          :authored_exclusion
          | Evidence.providability_error()
          | :classifier_uncertain
          | :unsupported_credit
          | {:invalid_evidence, Evidence.rejection(), term()}
          | AuthoredRules.uncertainty()
          | FirstN.uncertainty()
          | TaskOrder.uncertainty()

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
  @type attempt_error ::
          package_error()
          | JevDecision.rubric_batch_error()
          | {:invalid_option, :max_questions_per_call}

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

  @typep route :: :ask | :task_order | {:skip, :not_applicable | :not_observable, reason()}

  @typep plan :: %{
           id: term(),
           criterion: map(),
           max_points: Points.t(),
           requirement: Evidence.requirement(),
           route: route(),
           settled: %{optional(String.t()) => sub_action()},
           unproven: MapSet.t(String.t())
         }

  @typep level :: %{label: String.t(), points: Points.t()}

  @typep draft :: %{level: level(), evidence: [Evidence.item()], sub_actions: [sub_action()]}

  @doc """
  Assesses a completed session against the rubric of its v2 Station Package.

  `package` is the decoded package (string keys). `session` is the completed
  session map with `messages` and, optionally, `impresso_requests`. `opts` are
  passed to `Backend.Stations.JevDecision.decide_rubric_batch/2` (`:adapter`
  and the deadline options), except `:max_questions_per_call`, a positive
  integer that caps the questions of one call, and the resolver options
  (`:resolver_adapter`, `:resolver_opts`, `:rubric_resolver_deadline_ms`) read
  by `Backend.Stations.RubricAssessment.Resolver`.

  Returns criterion results in rubric order, the point estimates and the Jev
  calls made, or `{:error, {:invalid_attempt, reason}}` with no criteria when a
  call fails technically or the rubric has an authoring defect.
  """
  @spec assess(map(), map(), keyword()) ::
          {:ok, t()} | {:error, {:invalid_attempt, attempt_error()}}
  def assess(package, session, opts \\ [])
      when is_map(package) and is_map(session) and is_list(opts) do
    with :ok <- validate_batch_limit(opts),
         pool <- Evidence.build(session, package),
         {:ok, plans} <- triage(package),
         plans <- Enum.map(plans, &settle(&1, pool)),
         {:ok, decisions, calls} <- ask(questions(plans), pool, opts) do
      resolved = Resolver.resolve(decisions, asked(plans), pool, opts)
      plans = with_unproven(plans, decisions, resolved)
      decisions = with_settled(resolved, plans)

      criteria =
        plans |> Enum.map(&criterion_result(&1, decisions, pool)) |> task_order(plans, pool)

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
         :ok <- AuthoredRules.check(criterion),
         :ok <- check_task_order(criterion) do
      requirement = Evidence.requirement(criterion)

      {:ok,
       %{
         id: id,
         criterion: criterion,
         max_points: max_points,
         requirement: requirement,
         route: route(criterion, requirement, package),
         settled: %{},
         unproven: MapSet.new()
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

  defp route(criterion, requirement, package) do
    case Evidence.providability(requirement, package) do
      :ok -> if task_order?(criterion), do: :task_order, else: :ask
      {:error, reason} -> {:skip, :not_observable, reason}
    end
  end

  defp task_order?(criterion), do: Map.get(criterion, "rule") == @task_order

  # The order criterion scores its zero-point level when the order is broken,
  # so that level has to exist.
  defp check_task_order(criterion) do
    if task_order?(criterion) and not Enum.any?(list(criterion, "levels"), &(&1["points"] == 0)) do
      {:error, :missing_zero_point_level}
    else
      :ok
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
  defp questions(plans), do: plans |> asked() |> Enum.map(&question/1)

  # The criteria a provider is asked about: every one to ask, except those
  # whose actions a released impresso decided and whose thresholds decide the
  # level from them. A mandatory or forbidden role alone still needs Jev's level
  # when every action is performed (Jorge review of #228), so it is asked.
  defp asked(plans) do
    for %{route: :ask} = plan <- plans, not settled?(plan), do: plan
  end

  defp settled?(%{criterion: criterion, settled: settled}) do
    actions = authored_actions(criterion)

    actions != [] and Enum.all?(actions, &is_map_key(settled, &1.id)) and
      AuthoredRules.authors_thresholds?(criterion)
  end

  defp question(%{id: id, criterion: criterion, settled: settled}) do
    question = %{
      criterion: %{id: id, description: compose_description(criterion)},
      allowed_classes: level_labels(criterion) ++ [@uncertain_class],
      actions: Enum.reject(authored_actions(criterion), &is_map_key(settled, &1.id))
    }

    # The enumeration of the learner's answers is requested only where the
    # first-N rule needs it.
    if FirstN.applies?(criterion), do: Map.put(question, :enumerate_answers, true), else: question
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
  # Actions decided by released impressos
  # ============================================================================

  defp settle(%{route: :ask, criterion: criterion, requirement: requirement} = plan, pool) do
    %{plan | settled: ImpressoActions.settle(criterion, requirement, pool)}
  end

  defp settle(plan, _pool), do: plan

  # Puts the settled actions back among the provider's, in authored order. A
  # criterion nobody was asked about gets a decision with no criterion-level
  # class, so its rule fields decide the level from the actions.
  defp with_settled(decisions, plans) do
    for %{route: :ask, settled: settled} = plan <- plans, settled != %{}, reduce: decisions do
      acc ->
        decision =
          Map.get(acc, plan.id, %{
            criterion_id: plan.id,
            classification: @uncertain_class,
            evidence_ids: [],
            actions: []
          })

        Map.put(acc, plan.id, %{decision | actions: in_authored_order(plan, decision.actions)})
    end
  end

  defp in_authored_order(%{criterion: criterion, settled: settled}, provided) do
    by_id = Map.new(provided, &{&1.id, &1})

    for %{id: id} <- authored_actions(criterion),
        action = settled[id] || by_id[id],
        action != nil,
        do: action
  end

  # ============================================================================
  # Actions decided not performed by the resolver
  # ============================================================================

  # Records, per criterion, the actions Jev left uncertain that the resolver
  # answered `"not_performed"`. Such an answer cites nothing, so it may not be
  # the only ground of a zero-point level (`proven_zero/6`).
  defp with_unproven(plans, asked_decisions, resolved) do
    Enum.map(plans, fn plan ->
      %{plan | unproven: resolver_not_performed(asked_decisions[plan.id], resolved[plan.id])}
    end)
  end

  defp resolver_not_performed(%{actions: asked}, %{actions: resolved}) do
    undecided =
      for %{classification: @uncertain_class, id: id} <- asked, into: MapSet.new(), do: id

    for %{classification: @not_performed_class, id: id} <- resolved,
        MapSet.member?(undecided, id),
        into: MapSet.new(),
        do: id
  end

  defp resolver_not_performed(_asked, _resolved), do: MapSet.new()

  # ============================================================================
  # Batching
  # ============================================================================

  defp validate_batch_limit(opts) do
    case Keyword.get(opts, :max_questions_per_call) do
      nil -> :ok
      max when is_integer(max) and max > 0 -> :ok
      _invalid -> {:error, {:invalid_option, :max_questions_per_call}}
    end
  end

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

  # A task-order criterion gets `:pending` here and its result in `task_order/3`,
  # once the criteria it ranks are decided.
  @spec criterion_result(plan(), map(), Evidence.pool()) :: criterion_result() | :pending
  defp criterion_result(%{route: {:skip, status, reason}} = plan, _decisions, _pool) do
    unscored(plan, status, reason)
  end

  defp criterion_result(%{route: :task_order}, _decisions, _pool), do: :pending

  defp criterion_result(plan, decisions, pool) do
    case judge(plan, Map.fetch!(decisions, plan.id), pool) do
      {:assessed, draft} -> assessed(plan, draft)
      {:uncertain, reason} -> unscored(plan, :uncertain, reason)
    end
  end

  # A classifier that is uncertain about the criterion still classified its
  # actions. The criterion stays uncertain at once only when no rule field
  # could decide the level without the classifier's class.
  @spec judge(plan(), RubricBatch.decision(), Evidence.pool()) ::
          {:assessed, draft()} | {:uncertain, reason()}
  defp judge(%{criterion: criterion} = plan, %{classification: @uncertain_class} = decision, pool) do
    if AuthoredRules.decides?(criterion) do
      rule(plan, :uncertain, decision, pool)
    else
      {:uncertain, :classifier_uncertain}
    end
  end

  defp judge(%{criterion: criterion} = plan, decision, pool) do
    rule(plan, level(criterion, decision.classification), decision, pool)
  end

  defp rule(%{requirement: requirement} = plan, jev_level, decision, pool) do
    with {:ok, evidence} <- Evidence.validate(pool, decision.evidence_ids, requirement),
         {:ok, sub_actions} <- sub_actions(plan, decision.actions, pool),
         {:ok, level, grounding} <- decide(plan, jev_level, sub_actions, decision, pool),
         :ok <- proven_zero(plan, jev_level, level, sub_actions, decision, pool) do
      grounded(%{
        level: level,
        evidence: with_actions(evidence, grounding, pool),
        sub_actions: sub_actions
      })
    else
      {:error, {rejection, id}} -> {:uncertain, {:invalid_evidence, rejection, id}}
      {:uncertain, _reason} = uncertain -> uncertain
    end
  end

  defp decide(
         %{criterion: criterion, requirement: requirement},
         jev_level,
         sub_actions,
         decision,
         pool
       ) do
    with {:ok, eligible} <-
           FirstN.eligible(criterion, sub_actions, answers(decision), pool, requirement) do
      AuthoredRules.decide_level(criterion, jev_level, eligible)
    end
  end

  # A zero-point level needs no evidence, so the resolver's `"not_performed"`
  # answers, which cite nothing, could otherwise turn a criterion into a
  # confident zero without proof. The zero stands only when Jev's answers and
  # the deterministic rules reach it with those actions left undecided; when
  # they reach several outcomes, the criterion is uncertain.
  defp proven_zero(%{unproven: unproven} = plan, jev_level, level, sub_actions, decision, pool) do
    undecided = Enum.map(sub_actions, &undecide(&1, unproven))

    if level.points != Points.zero() or undecided == sub_actions do
      :ok
    else
      case decide(plan, jev_level, undecided, decision, pool) do
        {:ok, ^level, _grounding} -> :ok
        {:uncertain, _reason} = uncertain -> uncertain
        _other -> {:uncertain, {:uncertain_sub_action, first_unproven(sub_actions, unproven)}}
      end
    end
  end

  defp undecide(%{id: id} = sub_action, unproven) do
    if MapSet.member?(unproven, id),
      do: %{sub_action | classification: @uncertain_class, evidence_ids: []},
      else: sub_action
  end

  defp first_unproven(sub_actions, unproven) do
    Enum.find_value(sub_actions, &(MapSet.member?(unproven, &1.id) && &1.id))
  end

  # Present only on a decision whose question requested the enumeration.
  defp answers(decision), do: Map.get(decision, :answers, [])

  # A level earned by count is grounded by the actions that earned it, and a
  # veto zero by the forbidden actions that triggered it: their evidence,
  # already validated, joins the criterion evidence in pool order.
  defp with_actions(evidence, [], _pool), do: evidence

  defp with_actions(evidence, grounding, pool) do
    ids = MapSet.new(Evidence.ids(evidence) ++ Enum.flat_map(grounding, & &1.evidence_ids))

    Enum.filter(pool, &(&1.id in ids))
  end

  # Credit is never awarded without grounded learner evidence; a zero-point
  # level needs none, because a genuine omission leaves nothing to cite (but
  # see `proven_zero/6` for a zero the resolver alone reaches).
  defp grounded(%{level: %{points: points}, evidence: []}) when points > 0 do
    {:uncertain, :unsupported_credit}
  end

  defp grounded(draft), do: {:assessed, draft}

  # A sub-action may cite learner evidence the criterion cannot accept, such as an
  # Impressos event that released nothing or a turn for an Impressos criterion.
  # Those citations are dropped, so they never void the valid ones beside them; a
  # performed action left without evidence is unresolved, as any evidence-less one.
  # Every other rejection (an unknown id, a patient turn, an unverified event)
  # still fails the criterion closed.
  #
  # An action that interprets an impresso then keeps only the learner turns sent
  # after its release (`InterpretationEvidence`, issue #265). The resolver's
  # answers are already merged here, so the rule covers its citations and Jev's.
  defp sub_actions(%{criterion: criterion, requirement: requirement}, action_decisions, pool) do
    interprets = InterpretationEvidence.dependencies(criterion)

    map_ok(action_decisions, fn action ->
      cited = Enum.reject(action.evidence_ids, &wrong_channel?(pool, &1, requirement))

      with {:ok, evidence} <- Evidence.validate(pool, cited, requirement) do
        {:ok,
         InterpretationEvidence.restrict(
           %{
             id: action.id,
             classification: action.classification,
             evidence_ids: Evidence.ids(evidence)
           },
           interprets[action.id],
           pool
         )}
      end
    end)
  end

  defp wrong_channel?(pool, id, requirement) do
    match?({:error, {:wrong_channel, _id}}, Evidence.validate(pool, [id], requirement))
  end

  # ============================================================================
  # Task order
  # ============================================================================

  # The station-level pass: replaces each pending task-order result with the
  # decision over the ranked criteria, which are the other active criteria that
  # author an `order` rank.
  @spec task_order([criterion_result() | :pending], [plan()], Evidence.pool()) ::
          [criterion_result()]
  defp task_order(results, plans, pool) do
    decided = Enum.zip(plans, results)

    ranked =
      for {%{id: id, criterion: %{"order" => rank} = criterion}, %{status: status} = result} <-
            decided,
          is_integer(rank) and status != :not_applicable and not task_order?(criterion) do
        %{id: id, rank: rank, result: result}
      end

    Enum.map(decided, fn
      {plan, :pending} -> order_result(plan, TaskOrder.decide(ranked, pool))
      {_plan, result} -> result
    end)
  end

  defp order_result(plan, {:uncertain, reason}), do: unscored(plan, :uncertain, reason)

  defp order_result(%{criterion: criterion} = plan, {outcome, evidence}) do
    levels = for label <- level_labels(criterion), do: level(criterion, label)

    level =
      case outcome do
        :held -> Enum.max_by(levels, & &1.points)
        _not_held -> Enum.find(levels, &(&1.points == Points.zero()))
      end

    assessed(plan, %{level: level, evidence: evidence, sub_actions: []})
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
