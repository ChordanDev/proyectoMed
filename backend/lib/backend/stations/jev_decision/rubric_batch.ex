defmodule Backend.Stations.JevDecision.RubricBatch do
  @moduledoc """
  Request minimization and response validation for the batched rubric decision.

  A batch carries every independent rubric question of one evaluation together
  with a single shared evidence pool, so one adapter call can classify all of
  them. This module is pure: `Backend.Stations.JevDecision.decide_rubric_batch/2`
  owns adapter resolution, the deadline and error sanitization.

  A question may also request the enumeration of the learner's answers
  (`enumerate_answers: true`). Its decision must then carry `answers`: the
  ordered list of the distinct answers the learner gave to that criterion, each
  with the evidence item that holds it and the authored action it matches, or
  `nil` when it matches none. The caller uses it for rules that depend on the
  order of what was said, such as scoring only the first N answers.

  Structural problems are reported as typed errors that never embed adapter or
  learner text: `{:invalid_request, reason}` before the adapter is called, and
  `{:invalid_response, reason}` or `{:malformed_output, reason}` afterwards.
  """

  @action_classes ["performed", "not_performed", "uncertain"]

  @criterion_index %{
    key: :criterion_id,
    shape: :expected_decision_map,
    invalid: :invalid_criterion_id,
    unknown: :unknown_criterion_id,
    duplicate: :duplicate_criterion_id
  }

  @action_index %{
    key: :id,
    shape: :expected_action_map,
    invalid: :invalid_action_id,
    unknown: :unknown_action_id,
    duplicate: :duplicate_action_id
  }

  @typedoc "An identified item with its authored description (criterion or action)."
  @type described :: %{id: String.t(), description: String.t()}

  @typedoc """
  One independent rubric question, minimized for the decision provider.
  `:enumerate_answers` is present, and `true`, only when the enumeration of the
  learner's answers is requested.
  """
  @type question :: %{
          required(:criterion) => described(),
          required(:allowed_classes) => [String.t(), ...],
          required(:actions) => [described()],
          optional(:enumerate_answers) => true
        }

  @typedoc "One minimized evidence pool item."
  @type pool_item :: %{id: String.t(), role: term(), text: term()}

  @typedoc "The validated, minimized batch before the deadline is attached."
  @type payload :: %{questions: [question(), ...], evidence_pool: [pool_item()]}

  @typedoc "The request an adapter receives in `decide_rubric_batch/1`."
  @type adapter_request :: %{
          questions: [question(), ...],
          evidence_pool: [pool_item()],
          deadline_ms: pos_integer(),
          deadline_at_monotonic_ms: integer()
        }

  @typedoc "The classification of one authored action of a question."
  @type action_decision :: %{
          id: String.t(),
          classification: String.t(),
          evidence_ids: [String.t()]
        }

  @typedoc """
  One answer the learner gave to a question: the evidence item that holds it
  and the authored action it matches, or `nil` when it matches none.
  """
  @type answer :: %{evidence_id: String.t(), action_id: String.t() | nil}

  @typedoc """
  The normalized decision for one question. `:answers` is present only when the
  question requested the enumeration, in the order the provider listed them.
  """
  @type decision :: %{
          required(:criterion_id) => String.t(),
          required(:classification) => String.t(),
          required(:evidence_ids) => [String.t()],
          required(:rationale) => String.t() | nil,
          required(:actions) => [action_decision()],
          optional(:answers) => [answer()]
        }

  @type request_error :: {:invalid_request, atom()}
  @type response_error :: {:invalid_response, atom()} | {:malformed_output, atom()}

  @doc """
  Returns the closed set of classes an action decision may carry.
  """
  @spec action_classes() :: [String.t(), ...]
  def action_classes, do: @action_classes

  @doc """
  Validates a batch request and minimizes it to what the provider needs.

  Atom and string keys are both accepted. Criteria and actions are reduced to
  `id` and `description`, pool items to `id`, `role` and `text`; every other
  field is dropped, except `enumerate_answers`, which is kept on a question
  only when it is `true`. The evidence pool is kept once for the whole batch
  and may be empty (or absent).

  Returns `{:error, {:invalid_request, reason}}` with one of `:expected_map`,
  `:invalid_questions`, `:empty_questions`, `:invalid_question`,
  `:invalid_criterion`, `:duplicate_criterion_ids`, `:invalid_allowed_classes`,
  `:invalid_actions`, `:duplicate_action_ids`, `:invalid_enumerate_answers`,
  `:invalid_evidence_pool` or `:duplicate_evidence_ids`.
  """
  @spec build_payload(term()) :: {:ok, payload()} | {:error, request_error()}
  def build_payload(request) when is_map(request) do
    with {:ok, questions} <- build_questions(field(request, :questions)),
         {:ok, pool} <- build_pool(field(request, :evidence_pool)) do
      {:ok, %{questions: questions, evidence_pool: pool}}
    end
  end

  def build_payload(_request), do: invalid_request(:expected_map)

  @doc """
  Validates an adapter response against the questions that were asked.

  Requires exactly one decision per question, a classification from that
  question's `allowed_classes`, and exactly one action decision per authored
  action. Evidence identifiers only have to be lists of binaries: identifiers
  absent from the pool are returned verbatim for the caller to validate.

  A question that requested the enumeration must be answered with an `answers`
  list. Each entry carries a binary `evidence_id`, returned verbatim like every
  other evidence identifier, and an `action_id` that is `nil` (or absent) or one
  of that question's authored actions; an action may be named by one entry
  only. Any other question must carry no answers (an empty list is tolerated
  and dropped).

  Decisions are returned in question order with atom keys; `actions` follows the
  authored action order, `rationale` is `nil` when absent, and `answers` keeps
  the order of the response.

  Returns `{:error, {:invalid_response, reason}}` with one of
  `:invalid_criterion_id`, `:unknown_criterion_id`, `:duplicate_criterion_id`,
  `:missing_criterion_decision`, `:missing_classification`,
  `:invalid_classification_type`, `:disallowed_classification`,
  `:invalid_evidence_ids`, `:invalid_rationale`, `:unexpected_action_decisions`,
  `:invalid_action_id`, `:unknown_action_id`, `:duplicate_action_id`,
  `:missing_action_decision`, `:disallowed_action_classification`,
  `:invalid_action_evidence_ids`, `:missing_answers`, `:unexpected_answers`,
  `:invalid_answer_evidence_id`, `:invalid_answer_action_id`,
  `:unknown_answer_action_id` or `:duplicate_answer_action_id`; or
  `{:error, {:malformed_output, reason}}` with one of `:expected_map`,
  `:expected_decisions_list`, `:expected_decision_map`, `:expected_actions_list`,
  `:expected_action_map`, `:expected_answers_list` or `:expected_answer_map`.
  """
  @spec validate_response(term(), [question()]) ::
          {:ok, [decision()]} | {:error, response_error()}
  def validate_response(response, questions) when is_map(response) and is_list(questions) do
    criterion_ids = Enum.map(questions, & &1.criterion.id)

    with {:ok, raw_decisions} <-
           expect_list(field(response, :decisions), :expected_decisions_list),
         {:ok, by_id} <- index_by_id(raw_decisions, criterion_ids, @criterion_index) do
      map_ok(questions, &build_decision(&1, by_id))
    end
  end

  def validate_response(_response, _questions), do: malformed(:expected_map)

  # ============================================================================
  # Request validation and minimization
  # ============================================================================

  defp build_questions([]), do: invalid_request(:empty_questions)

  defp build_questions(questions) when is_list(questions) do
    with {:ok, built} <- map_ok(questions, &build_question/1),
         :ok <- unique_ids(Enum.map(built, & &1.criterion), :duplicate_criterion_ids) do
      {:ok, built}
    end
  end

  defp build_questions(_questions), do: invalid_request(:invalid_questions)

  defp build_question(question) when is_map(question) do
    with {:ok, criterion} <- build_described(field(question, :criterion), :invalid_criterion),
         {:ok, classes} <- build_allowed_classes(field(question, :allowed_classes)),
         {:ok, actions} <- build_actions(field(question, :actions)),
         {:ok, enumeration} <- build_enumeration(field(question, :enumerate_answers)) do
      {:ok,
       Map.merge(%{criterion: criterion, allowed_classes: classes, actions: actions}, enumeration)}
    end
  end

  defp build_question(_question), do: invalid_request(:invalid_question)

  # The flag travels only when set, so a question that requests nothing keeps
  # the shape it always had.
  defp build_enumeration(true), do: {:ok, %{enumerate_answers: true}}
  defp build_enumeration(off) when off in [nil, false], do: {:ok, %{}}
  defp build_enumeration(_other), do: invalid_request(:invalid_enumerate_answers)

  defp build_allowed_classes([_ | _] = classes) do
    if Enum.all?(classes, &non_blank?/1) do
      {:ok, classes}
    else
      invalid_request(:invalid_allowed_classes)
    end
  end

  defp build_allowed_classes(_classes), do: invalid_request(:invalid_allowed_classes)

  defp build_actions(nil), do: {:ok, []}

  defp build_actions(actions) when is_list(actions) do
    with {:ok, built} <- map_ok(actions, &build_described(&1, :invalid_actions)),
         :ok <- unique_ids(built, :duplicate_action_ids) do
      {:ok, built}
    end
  end

  defp build_actions(_actions), do: invalid_request(:invalid_actions)

  defp build_described(item, reason) when is_map(item) do
    id = field(item, :id)

    if non_blank?(id) do
      {:ok, %{id: id, description: field(item, :description) || ""}}
    else
      invalid_request(reason)
    end
  end

  defp build_described(_item, reason), do: invalid_request(reason)

  defp build_pool(nil), do: {:ok, []}

  defp build_pool(pool) when is_list(pool) do
    with {:ok, built} <- map_ok(pool, &build_pool_item/1),
         :ok <- unique_ids(built, :duplicate_evidence_ids) do
      {:ok, built}
    end
  end

  defp build_pool(_pool), do: invalid_request(:invalid_evidence_pool)

  defp build_pool_item(item) when is_map(item) do
    id = field(item, :id)

    if non_blank?(id) do
      {:ok, %{id: id, role: field(item, :role), text: field(item, :text)}}
    else
      invalid_request(:invalid_evidence_pool)
    end
  end

  defp build_pool_item(_item), do: invalid_request(:invalid_evidence_pool)

  defp unique_ids(items, reason) do
    ids = Enum.map(items, & &1.id)

    if Enum.uniq(ids) == ids, do: :ok, else: invalid_request(reason)
  end

  # ============================================================================
  # Response validation and normalization
  # ============================================================================

  defp build_decision(question, by_id) do
    case Map.fetch(by_id, question.criterion.id) do
      {:ok, raw} -> normalize_decision(raw, question)
      :error -> invalid_response(:missing_criterion_decision)
    end
  end

  defp normalize_decision(raw, question) do
    classification = field(raw, :classification)

    with :ok <- check_classification(classification, question.allowed_classes),
         {:ok, evidence_ids} <- evidence_ids(field(raw, :evidence_ids), :invalid_evidence_ids),
         {:ok, rationale} <- rationale(field(raw, :rationale)),
         {:ok, actions} <- action_decisions(field(raw, :actions), question.actions),
         {:ok, answers} <- answers(field(raw, :answers), question) do
      {:ok,
       Map.merge(
         %{
           criterion_id: question.criterion.id,
           classification: classification,
           evidence_ids: evidence_ids,
           rationale: rationale,
           actions: actions
         },
         answers
       )}
    end
  end

  defp check_classification(nil, _allowed), do: invalid_response(:missing_classification)

  defp check_classification(class, allowed) when is_binary(class) do
    if class in allowed, do: :ok, else: invalid_response(:disallowed_classification)
  end

  defp check_classification(_class, _allowed), do: invalid_response(:invalid_classification_type)

  defp rationale(nil), do: {:ok, nil}
  defp rationale(rationale) when is_binary(rationale), do: {:ok, rationale}
  defp rationale(_rationale), do: invalid_response(:invalid_rationale)

  defp evidence_ids(nil, _reason), do: {:ok, []}

  defp evidence_ids(ids, reason) when is_list(ids) do
    if Enum.all?(ids, &is_binary/1), do: {:ok, ids}, else: invalid_response(reason)
  end

  defp evidence_ids(_ids, reason), do: invalid_response(reason)

  defp action_decisions(nil, []), do: {:ok, []}
  defp action_decisions([], []), do: {:ok, []}
  defp action_decisions([_ | _], []), do: invalid_response(:unexpected_action_decisions)
  defp action_decisions(nil, _authored), do: invalid_response(:missing_action_decision)

  defp action_decisions(raw_actions, authored) when is_list(raw_actions) do
    with {:ok, by_id} <- index_by_id(raw_actions, Enum.map(authored, & &1.id), @action_index) do
      map_ok(authored, &build_action_decision(&1, by_id))
    end
  end

  defp action_decisions(_raw_actions, _authored), do: malformed(:expected_actions_list)

  defp build_action_decision(action, by_id) do
    case Map.fetch(by_id, action.id) do
      {:ok, raw} -> normalize_action_decision(raw, action.id)
      :error -> invalid_response(:missing_action_decision)
    end
  end

  defp normalize_action_decision(raw, id) do
    classification = field(raw, :classification)
    raw_evidence_ids = field(raw, :evidence_ids)

    with true <- classification in @action_classes,
         {:ok, evidence_ids} <- evidence_ids(raw_evidence_ids, :invalid_action_evidence_ids) do
      {:ok, %{id: id, classification: classification, evidence_ids: evidence_ids}}
    else
      false -> invalid_response(:disallowed_action_classification)
      {:error, _reason} = error -> error
    end
  end

  # Returns the fields to add to the decision: `answers` when the question
  # requested the enumeration, and nothing otherwise.
  defp answers(raw_answers, %{enumerate_answers: true} = question) do
    case raw_answers do
      nil -> invalid_response(:missing_answers)
      list when is_list(list) -> enumerated_answers(list, Enum.map(question.actions, & &1.id))
      _other -> malformed(:expected_answers_list)
    end
  end

  defp answers(absent, _question) when absent in [nil, []], do: {:ok, %{}}
  defp answers(_raw_answers, _question), do: invalid_response(:unexpected_answers)

  defp enumerated_answers(raw_answers, action_ids) do
    with {:ok, answers} <- map_ok(raw_answers, &build_answer(&1, action_ids)),
         :ok <- distinct_answer_actions(answers) do
      {:ok, %{answers: answers}}
    end
  end

  defp build_answer(raw, action_ids) when is_map(raw) do
    evidence_id = field(raw, :evidence_id)
    action_id = field(raw, :action_id)

    cond do
      not is_binary(evidence_id) -> invalid_response(:invalid_answer_evidence_id)
      is_nil(action_id) -> {:ok, %{evidence_id: evidence_id, action_id: nil}}
      not is_binary(action_id) -> invalid_response(:invalid_answer_action_id)
      action_id not in action_ids -> invalid_response(:unknown_answer_action_id)
      true -> {:ok, %{evidence_id: evidence_id, action_id: action_id}}
    end
  end

  defp build_answer(_raw, _action_ids), do: malformed(:expected_answer_map)

  # Several answers may match no authored action; an action is one answer.
  defp distinct_answer_actions(answers) do
    matched = for %{action_id: action_id} <- answers, action_id != nil, do: action_id

    if Enum.uniq(matched) == matched, do: :ok, else: invalid_response(:duplicate_answer_action_id)
  end

  # Indexes raw decision maps by identifier, rejecting malformed, unknown and
  # repeated identifiers. Missing identifiers are detected by the caller.
  defp index_by_id(raw_items, known_ids, rules) do
    known = MapSet.new(known_ids)

    Enum.reduce_while(raw_items, {:ok, %{}}, fn raw, {:ok, acc} ->
      case index_item(raw, known, acc, rules) do
        {:ok, _acc} = indexed -> {:cont, indexed}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp index_item(raw, known, acc, rules) when is_map(raw) do
    id = field(raw, rules.key)

    cond do
      not is_binary(id) -> invalid_response(rules.invalid)
      not MapSet.member?(known, id) -> invalid_response(rules.unknown)
      Map.has_key?(acc, id) -> invalid_response(rules.duplicate)
      true -> {:ok, Map.put(acc, id, raw)}
    end
  end

  defp index_item(_raw, _known, _acc, rules), do: malformed(rules.shape)

  defp expect_list(list, _reason) when is_list(list), do: {:ok, list}
  defp expect_list(_other, reason), do: malformed(reason)

  # ============================================================================
  # Helpers
  # ============================================================================

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

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp non_blank?(value), do: is_binary(value) and String.trim(value) != ""

  defp invalid_request(reason), do: {:error, {:invalid_request, reason}}
  defp invalid_response(reason), do: {:error, {:invalid_response, reason}}
  defp malformed(reason), do: {:error, {:malformed_output, reason}}
end
