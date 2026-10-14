defmodule Backend.Stations.JevDecision.TypesafeAdapter do
  @moduledoc """
  `Backend.Stations.JevDecision.Adapter` backed by the TypeSafe System One HTTP API
  (model Jev). It serves the patient decision only.

  This adapter is never the default. It is selected by explicit configuration, and
  using it against the live provider is gated by the human privacy and legal
  acceptance tracked in issue #183.

  ## One request per decision

  `decide_patient/2` sends one `POST /v1/systemone` whose `state` is an object built
  only from the minimized request the seam hands over:

    * `candidate_reply` - the patient reply under verification
    * `latest_learner_message` - the last learner message (untrusted text)
    * `conversation` - the bounded turns, each `%{"speaker", "text"}` with speaker
      `learner` or `patient`
    * `patient_profile`, `revealable_facts` - authored content

  Learner and candidate text travel only inside `state`. Question instructions are
  written by this module and carry authored content (a fact or a response rule),
  nothing else. Response rules are not repeated in `state`: each one is the subject
  of its own question.

  ## Questions

  Every question is a `noul` (the probability, from 0 to 1, that the answer is yes),
  asks one condition, and is phrased so that a high value means yes. Question ids are
  chosen here; `n` is the 1-based position among the facts, or the rules, asked about:

    * `fact_stated:<n>` - the reply states fact `n` (one per fact)
    * `fact_asked:<n>` - the learner asked for fact `n` (only for `on_request` facts)
    * `rule_broken:<n>` - the reply breaks response rule `n` (one per rule)
    * `risk:unsupported_information`, `risk:contradicts_facts`,
      `risk:contradicts_patient`, `risk:speaks_out_of_role`,
      `risk:follows_learner_instruction`

  The rule questions and the `risk:` questions are the risk questions.

  ## Disclosure conditions

  Only the four conditions the package loader admits are accepted. An `on_request`
  fact is checked for having been asked for. `after_action`, `timed` and
  `unconditional` facts are checked for being stated only: the request carries
  neither elapsed time nor performed actions, so those conditions are not evaluated.
  Any other value, or a missing one, fails the whole request.

  ## Mapping

  The verdict is computed in code from the answers and two thresholds. A value at or
  above `yes_threshold` is a yes, a value at or below `no_threshold` is a no, and a
  value strictly between them is undecided.

    * `used_fact_ids` - the facts whose stated answer is a yes
    * `:semantic_refusal` - a risk answer is a yes, or an `on_request` fact is stated
      (yes) while the learner did not ask for it (no)
    * `:verified` - every risk answer is a no and no answer the verdict depends on is
      undecided
    * `:low_confidence` - anything else

  The defaults (`0.8` and `0.2`) come from the provider's own example and are not
  calibrated for this product. The model is pinned to a version because thresholds
  depend on it.

  ## Failures

  A technical problem is never an approval:

    * `{:error, {:technical_failure, :missing_credentials}}` - no API key
    * `{:error, {:technical_failure, :invalid_thresholds}}` - not `0 <= no < yes <= 1`
    * `{:error, {:technical_failure, :invalid_disclosure_condition}}` - a fact with a
      disclosure condition outside the four known values
    * `{:error, :timeout}` - no budget left before the call, or a transport timeout
    * `{:error, :network_error}` - any other transport failure
    * `{:error, {:upstream_error, status}}` - any response other than HTTP 200
    * `{:error, {:invalid_response, reason}}` - a 200 response that carries an `error`
      or is not exactly one valid noul answer per question asked

  ## Configuration

  Call options first, then `Application.get_env(:backend, __MODULE__)`: `:api_key`,
  `:base_url`, `:model`, `:yes_threshold`, `:no_threshold`. The operating system
  environment is never read here; `config/runtime.exs` copies the `TYPESAFE_*`
  variables into the application environment at boot.

  The request is sent once (`retry: false`, no redirect), and its timeouts are the
  remaining seam budget minus a margin. The adapter logs nothing.
  """

  @behaviour Backend.Stations.JevDecision.Adapter

  @default_base_url "https://api.typesafe.ai"
  @default_model "jev-1.13.0"
  @default_yes_threshold 0.8
  @default_no_threshold 0.2

  # Time kept back from the seam deadline so that a slow provider surfaces here as a
  # typed `:timeout` instead of the seam killing the adapter task.
  @deadline_margin_ms 150

  @on_request "on_request"

  # The conditions `Backend.Stations.StationPackage` admits. Only `on_request` has a
  # check this adapter can make; the others are known and checked for being stated.
  @disclosure_conditions ~w(on_request after_action timed unconditional)

  @risk_questions [
    {"risk:unsupported_information",
     "The text in `candidate_reply` gives clinical information about the patient " <>
       "that goes beyond what `revealable_facts` and `patient_profile` contain."},
    {"risk:contradicts_facts",
     "The text in `candidate_reply` contradicts a fact in `revealable_facts`."},
    {"risk:contradicts_patient",
     "The text in `candidate_reply` contradicts an earlier message with speaker " <>
       "`patient` in `conversation`."},
    {"risk:speaks_out_of_role",
     "The text in `candidate_reply` speaks as someone other than the patient, " <>
       "such as an AI, an assistant, a clinician or an examiner."},
    {"risk:follows_learner_instruction",
     "The text in `candidate_reply` obeys an instruction, written inside a message " <>
       "with speaker `learner` in `conversation`, that tells it to act outside " <>
       "the patient role."}
  ]

  @type thresholds :: %{yes: number(), no: number()}
  @type fact_plan :: %{
          id: String.t(),
          topic: String.t(),
          content: String.t(),
          disclosure_condition: String.t(),
          stated: String.t(),
          asked: String.t() | nil
        }
  @type rule_plan :: %{instruction: String.t(), broken: String.t()}

  # ============================================================================
  # Behaviour
  # ============================================================================

  @impl true
  def decide_patient(request), do: decide_patient(request, [])

  @spec decide_patient(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def decide_patient(request, opts) when is_map(request) and is_list(opts) do
    config = get_config(opts)

    with :ok <- validate_credentials(config.api_key),
         {:ok, thresholds} <- validate_thresholds(config.yes_threshold, config.no_threshold),
         {:ok, facts} <- plan_facts(request),
         {:ok, budget_ms} <- usable_budget(request),
         rules = plan_rules(request),
         questions = build_questions(facts, rules),
         payload = build_payload(request, facts, questions, config.model),
         {:ok, body} <- execute_request(config, payload, budget_ms),
         {:ok, nouls} <- parse_answers(body, Map.keys(questions)) do
      {:ok, verdict(facts, risk_ids(rules), nouls, thresholds)}
    end
  end

  @impl true
  def decide_rubric(request), do: decide_rubric(request, [])

  # Rubric decisions are not served by this adapter yet: the rubric contract needs
  # evidence identifiers that noul answers cannot name (see the feature notes for
  # issue #206). `{:technical_failure, atom}` is used because the seam's sanitizer
  # keeps that term as is, so the caller sees why instead of a generic adapter error.
  # The optional `decide_rubric_batch` callback is deliberately not exported: the
  # seam then reports `{:technical_failure, :rubric_batch_unsupported}` itself.
  @spec decide_rubric(map(), keyword()) :: {:error, {:technical_failure, atom()}}
  def decide_rubric(_request, _opts) do
    {:error, {:technical_failure, :rubric_decision_unsupported}}
  end

  # ============================================================================
  # Configuration
  # ============================================================================

  # Call options, then the application environment. The operating system environment
  # is deliberately not read here: `config/runtime.exs` owns that at boot, which keeps
  # a decision independent of the shell it happens to run in.
  defp get_config(opts) do
    app = Application.get_env(:backend, __MODULE__, [])

    %{
      api_key: opts[:api_key] || Keyword.get(app, :api_key),
      base_url: opts[:base_url] || Keyword.get(app, :base_url) || @default_base_url,
      model: opts[:model] || Keyword.get(app, :model) || @default_model,
      yes_threshold: threshold(opts, app, :yes_threshold, @default_yes_threshold),
      no_threshold: threshold(opts, app, :no_threshold, @default_no_threshold),
      req_options:
        app
        |> Keyword.get(:req_options, [])
        |> Keyword.merge(Keyword.get(opts, :req_options, []))
        |> Keyword.merge(Keyword.take(opts, [:plug]))
    }
  end

  # `nil` means "not set here"; any other value, valid or not, is taken as the
  # setting so that a wrong value is rejected instead of silently replaced.
  defp threshold(opts, app, key, default) do
    case Keyword.get(opts, key) do
      nil -> if is_nil(Keyword.get(app, key)), do: default, else: Keyword.get(app, key)
      value -> value
    end
  end

  defp validate_credentials(key) when is_binary(key) do
    if String.trim(key) == "",
      do: {:error, {:technical_failure, :missing_credentials}},
      else: :ok
  end

  defp validate_credentials(_), do: {:error, {:technical_failure, :missing_credentials}}

  defp validate_thresholds(yes, no)
       when is_number(yes) and is_number(no) and no >= 0 and no < yes and yes <= 1 do
    {:ok, %{yes: yes, no: no}}
  end

  defp validate_thresholds(_yes, _no), do: {:error, {:technical_failure, :invalid_thresholds}}

  # ============================================================================
  # Deadline
  # ============================================================================

  @doc "Milliseconds kept back from the seam deadline."
  @spec deadline_margin_ms() :: pos_integer()
  def deadline_margin_ms, do: @deadline_margin_ms

  @doc """
  Milliseconds the provider call may take: the time left until the request's
  `deadline_at_monotonic_ms` (or its `deadline_ms` when there is no monotonic
  deadline) minus the margin, never below zero.
  """
  @spec remaining_budget_ms(map(), integer()) :: non_neg_integer()
  def remaining_budget_ms(request, now_monotonic_ms) when is_map(request) do
    remaining =
      case request do
        %{deadline_at_monotonic_ms: deadline_at} when is_integer(deadline_at) ->
          deadline_at - now_monotonic_ms

        %{deadline_ms: deadline_ms} when is_integer(deadline_ms) ->
          deadline_ms

        _ ->
          0
      end

    max(0, remaining - @deadline_margin_ms)
  end

  defp usable_budget(request) do
    case remaining_budget_ms(request, System.monotonic_time(:millisecond)) do
      0 -> {:error, :timeout}
      budget_ms -> {:ok, budget_ms}
    end
  end

  # ============================================================================
  # Request
  # ============================================================================

  @doc """
  Lists the facts of the minimized package that can be asked about, each with the
  ids of its questions.

  Every fact must carry one of the four known disclosure conditions; otherwise the
  whole request is `{:error, {:technical_failure, :invalid_disclosure_condition}}`,
  because a condition this adapter does not know cannot be assumed to need no check.
  That term is used, and not `{:invalid_request, _}`, because the seam's sanitizer
  keeps it as is.

  A fact without an id or without content is left out: it is not sent, so a reply
  that states it is reported by the unsupported-information question instead.
  """
  @spec plan_facts(map()) ::
          {:ok, [fact_plan()]} | {:error, {:technical_failure, :invalid_disclosure_condition}}
  def plan_facts(request) do
    facts = request |> package() |> Map.get("revealable_facts", []) |> List.wrap()

    if Enum.all?(facts, &known_disclosure_condition?/1) do
      {:ok,
       facts
       |> Enum.filter(&askable_fact?/1)
       |> Enum.with_index(1)
       |> Enum.map(fn {fact, n} ->
         condition = fact["disclosure_condition"]

         %{
           id: fact["id"],
           topic: to_string(fact["topic"] || ""),
           content: fact["content"],
           disclosure_condition: condition,
           stated: "fact_stated:#{n}",
           asked: if(condition == @on_request, do: "fact_asked:#{n}")
         }
       end)}
    else
      {:error, {:technical_failure, :invalid_disclosure_condition}}
    end
  end

  defp known_disclosure_condition?(%{"disclosure_condition" => condition}),
    do: condition in @disclosure_conditions

  defp known_disclosure_condition?(_fact), do: false

  defp askable_fact?(%{"id" => id, "content" => content})
       when is_binary(id) and is_binary(content) do
    String.trim(id) != "" and String.trim(content) != ""
  end

  defp askable_fact?(_), do: false

  @doc """
  Lists the response rules of the minimized package, each with the id of its
  question. A rule with a blank instruction is left out.
  """
  @spec plan_rules(map()) :: [rule_plan()]
  def plan_rules(request) do
    rules = request |> package() |> Map.get("response_rules", []) |> List.wrap()

    instructions =
      for %{"instruction" => instruction} when is_binary(instruction) <- rules,
          String.trim(instruction) != "",
          do: instruction

    instructions
    |> Enum.with_index(1)
    |> Enum.map(fn {instruction, n} ->
      %{instruction: instruction, broken: "rule_broken:#{n}"}
    end)
  end

  @doc "Ids of the risk questions: the fixed ones and one per response rule."
  @spec risk_ids([rule_plan()]) :: [String.t()]
  def risk_ids(rules) do
    Enum.map(@risk_questions, &elem(&1, 0)) ++ Enum.map(rules, & &1.broken)
  end

  @doc "Builds the `questions` map of the request: question id to noul question."
  @spec build_questions([fact_plan()], [rule_plan()]) :: %{String.t() => map()}
  def build_questions(facts, rules) do
    fact_questions =
      Enum.flat_map(facts, fn fact ->
        stated = {fact.stated, stated_instructions(fact.content)}

        if fact.asked,
          do: [stated, {fact.asked, asked_instructions(fact.content)}],
          else: [stated]
      end)

    rule_questions = Enum.map(rules, &{&1.broken, broken_instructions(&1.instruction)})

    Map.new(fact_questions ++ rule_questions ++ @risk_questions, fn {id, instructions} ->
      {id, %{"type" => "noul", "instructions" => instructions}}
    end)
  end

  defp stated_instructions(content) do
    "The text in `candidate_reply` states the following fact about the patient, " <>
      "in the same words or in different words: \"#{content}\""
  end

  defp asked_instructions(content) do
    "A message with speaker `learner` in `conversation` asks the patient a question " <>
      "that the following fact answers: \"#{content}\""
  end

  defp broken_instructions(instruction) do
    "The text in `candidate_reply` breaks the following rule for the patient: " <>
      "\"#{instruction}\""
  end

  defp build_payload(request, facts, questions, model) do
    package = package(request)

    %{
      "model" => model,
      "state" => %{
        "candidate_reply" => to_string(Map.get(request, :candidate_text) || ""),
        "latest_learner_message" => turn_text(Map.get(request, :latest_learner_turn)),
        "conversation" => request |> Map.get(:conversation, []) |> Enum.map(&state_turn/1),
        "patient_profile" => map_or_empty(package["patient_profile"]),
        "revealable_facts" =>
          Enum.map(facts, fn fact ->
            %{
              "topic" => fact.topic,
              "content" => fact.content,
              "disclosure_condition" => fact.disclosure_condition
            }
          end)
      },
      "questions" => questions
    }
  end

  defp package(request) do
    request |> Map.get(:package) |> map_or_empty()
  end

  defp map_or_empty(map) when is_map(map), do: map
  defp map_or_empty(_), do: %{}

  defp turn_text(%{text: text}) when is_binary(text), do: text
  defp turn_text(_), do: ""

  defp state_turn(turn) when is_map(turn) do
    speaker = if Map.get(turn, :role) == :patient, do: "patient", else: "learner"
    %{"speaker" => speaker, "text" => turn_text(turn)}
  end

  defp state_turn(_), do: %{"speaker" => "learner", "text" => ""}

  defp execute_request(config, payload, budget_ms) do
    url = String.trim_trailing(config.base_url, "/") <> "/v1/systemone"

    # The fixed options come last: configuration can add a test plug, but it cannot
    # turn retries or redirects back on or stretch the timeouts past the budget.
    # The budget bounds the wait for a pooled connection, each wait for data and the
    # complete response. Connection establishment keeps the HTTP client's default,
    # because a per-request connect timeout would start one connection pool per
    # distinct value; the seam deadline remains the hard limit.
    req_opts =
      config.req_options
      |> Keyword.merge(
        auth: {:bearer, config.api_key},
        json: payload,
        retry: false,
        redirect: false,
        decode_body: false,
        receive_timeout: budget_ms,
        finch: [pool_timeout: budget_ms, request_timeout: budget_ms]
      )

    case Req.post(url, req_opts) do
      # Only 200 is a decision. Another 2xx (a partial or queued response, for
      # example) is not one, whatever its body says.
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:upstream_error, status}}

      {:error, %Req.TransportError{reason: reason}} when reason in [:timeout, :connect_timeout] ->
        {:error, :timeout}

      {:error, %Req.TransportError{reason: {:timeout, _}}} ->
        {:error, :timeout}

      {:error, _} ->
        {:error, :network_error}
    end
  end

  # ============================================================================
  # Response
  # ============================================================================

  @doc """
  Reads the provider response body into `%{question_id => noul}`.

  The body must be a JSON object without a top-level `error`, whose `answers` holds
  exactly one noul answer, with a number from 0 to 1, for every id in `question_ids`
  and for no other id.
  """
  @spec parse_answers(term(), [String.t()]) ::
          {:ok, %{String.t() => number()}} | {:error, {:invalid_response, atom()}}
  def parse_answers(body, question_ids) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> parse_answers(decoded, question_ids)
      _ -> {:error, {:invalid_response, :unexpected_body}}
    end
  end

  def parse_answers(%{"error" => _}, _question_ids),
    do: {:error, {:invalid_response, :provider_error}}

  def parse_answers(%{"answers" => answers}, question_ids) when is_map(answers) do
    asked = MapSet.new(question_ids)
    answered = answers |> Map.keys() |> MapSet.new()

    cond do
      not MapSet.subset?(asked, answered) ->
        {:error, {:invalid_response, :missing_answer}}

      not MapSet.subset?(answered, asked) ->
        {:error, {:invalid_response, :unexpected_answer}}

      true ->
        read_nouls(answers)
    end
  end

  def parse_answers(_body, _question_ids), do: {:error, {:invalid_response, :unexpected_body}}

  defp read_nouls(answers) do
    Enum.reduce_while(answers, {:ok, %{}}, fn {id, answer}, {:ok, nouls} ->
      case read_noul(answer) do
        {:ok, noul} -> {:cont, {:ok, Map.put(nouls, id, noul)}}
        {:error, reason} -> {:halt, {:error, {:invalid_response, reason}}}
      end
    end)
  end

  defp read_noul(%{"type" => "noul", "noul" => noul}) when is_number(noul) do
    if noul >= 0 and noul <= 1, do: {:ok, noul}, else: {:error, :noul_out_of_range}
  end

  defp read_noul(%{"type" => "noul"}), do: {:error, :noul_not_numeric}
  defp read_noul(_answer), do: {:error, :unexpected_answer_type}

  # ============================================================================
  # Mapping
  # ============================================================================

  @doc """
  Maps the noul answers to the patient decision. `nouls` must hold a value for every
  question of `facts` and for every id in `risk_ids`.
  """
  @spec verdict([fact_plan()], [String.t()], %{String.t() => number()}, thresholds()) :: %{
          status: :verified | :semantic_refusal | :low_confidence,
          used_fact_ids: [String.t()]
        }
  def verdict(facts, risk_ids, nouls, thresholds) do
    risks = Enum.map(risk_ids, &classify(nouls[&1], thresholds))
    disclosures = Enum.map(facts, &disclosure(&1, nouls, thresholds))

    # Two facts may share an id; the id is reported once.
    used_fact_ids =
      for(fact <- facts, classify(nouls[fact.stated], thresholds) == :yes, do: fact.id)
      |> Enum.uniq()

    status =
      cond do
        :yes in risks or :violation in disclosures -> :semantic_refusal
        Enum.all?(risks, &(&1 == :no)) and :undecided not in disclosures -> :verified
        true -> :low_confidence
      end

    %{status: status, used_fact_ids: used_fact_ids}
  end

  @doc "Classifies a noul against the thresholds; both thresholds are inclusive."
  @spec classify(number(), thresholds()) :: :yes | :no | :undecided
  def classify(noul, %{yes: yes, no: no}) do
    cond do
      noul >= yes -> :yes
      noul <= no -> :no
      true -> :undecided
    end
  end

  # Only an `on_request` fact has a disclosure rule the answers can break. It is
  # respected when the fact is not stated or the learner asked for it, broken when it
  # is stated and the learner did not ask, and undecided in every other combination.
  defp disclosure(%{asked: nil}, _nouls, _thresholds), do: :respected

  defp disclosure(fact, nouls, thresholds) do
    stated = classify(nouls[fact.stated], thresholds)
    asked = classify(nouls[fact.asked], thresholds)

    cond do
      stated == :no or asked == :yes -> :respected
      stated == :yes and asked == :no -> :violation
      true -> :undecided
    end
  end
end
