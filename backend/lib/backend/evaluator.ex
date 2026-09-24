defmodule Backend.Evaluator do
  @moduledoc """
  Produces rubric-bound feedback comparing a completed station transcript
  against the active Station Package.

  In alignment with ADR-005:
    * Feedback is reported per-criterion only.
    * Each criterion receives a status of `:met`, `:omitted`, or `:uncertain`.
    * Evidence is a list of transcript excerpts (`%{role, text}`) that grounded
      the decision. Omitted criteria strictly return an empty list `[]`.
    * Uncertain status is assigned when evidence is ambiguous, partial, or
      tentative. The recommendation field provides what to practice next.
    * No global score, no readiness verdict, and no Revalida-readiness claims
      appear anywhere in the output.
  """

  @type criterion_status :: :met | :omitted | :uncertain

  @type transcript_excerpt :: %{
          role: term(),
          text: String.t()
        }

  @type criterion_result :: %{
          id: String.t(),
          status: criterion_status(),
          evidence: [transcript_excerpt()],
          recommendation: String.t()
        }

  @type evaluation_result :: %{
          criteria: [criterion_result()]
        }

  @type package :: %{required(String.t() | atom()) => term()}
  @type message :: %{required(String.t() | atom()) => term()}
  @type transcript :: [message()] | %{optional(atom() | String.t()) => term()}

  @doc """
  Evaluator behaviour for custom or LLM-backed evaluation adapters.
  """
  @callback evaluate(package(), transcript(), keyword()) :: evaluation_result()

  @ambiguity_markers [
    "talvez",
    "não tenho certeza",
    "nao tenho certeza",
    "acho que",
    "possivelmente",
    "será que",
    "sera que",
    "parece que",
    "mais ou menos",
    "incompleto",
    "vago",
    "ambíguo",
    "ambiguo",
    "não ficou claro",
    "nao ficou claro",
    "uncertain",
    "ambiguous",
    "maybe",
    "not sure",
    "perhaps"
  ]

  @known_domain_terms %{
    "onset" => %{
      inquiry: [
        "quando começou",
        "quando comecou",
        "quando iniciou",
        "desde quando",
        "que horas começou",
        "quando a dor começou",
        "a dor começou quando",
        "quando começou a dor",
        "iniciou quando",
        "começou há quanto tempo",
        "comecou ha quanto tempo",
        "iniciou há quanto tempo",
        "how long ago",
        "when did",
        "when started",
        "onset"
      ],
      context: [
        "agora",
        "hoje",
        "tempo",
        "duração",
        "duracao",
        "momento",
        "recente",
        "começo",
        "comeco",
        "começou",
        "início",
        "inicio",
        "iniciou",
        "surgimento",
        "caminhada",
        "desencadeou",
        "desencadeante",
        "timing",
        "started"
      ]
    },
    "radiation" => %{
      inquiry: [
        "irradia",
        "irradiação",
        "irradiacao",
        "irradiava",
        "irradiando",
        "espalha",
        "espalhando",
        "radiat",
        "radiates",
        "radiating",
        "radiation"
      ],
      context: [
        "braço",
        "braco",
        "mandíbula",
        "mandibula",
        "costas",
        "pescoço",
        "pescoco",
        "ombro",
        "arm",
        "jaw",
        "back",
        "neck",
        "shoulder"
      ]
    },
    "character" => %{
      inquiry: [
        "característica",
        "caracteristica",
        "tipo de dor",
        "qualidade da dor",
        "como é a dor",
        "como e a dor",
        "quality of pain",
        "what kind of pain"
      ],
      context: [
        "aperto",
        "queimação",
        "queimacao",
        "pressão",
        "pressao",
        "pontada",
        "pesado",
        "burning",
        "pressure",
        "sharp",
        "crushing"
      ]
    }
  }

  @doc """
  Evaluates a station transcript against the package rubric.

  Returns `%{criteria: [%{id, status, evidence, recommendation}]}`.
  """
  @spec evaluate(package(), transcript()) :: evaluation_result()
  def evaluate(package, transcript) do
    evaluate(package, transcript, [])
  end

  @doc """
  Evaluates a station transcript against the package rubric with options.

  Accepts `:adapter` to delegate evaluation to a custom module implementing
  `Backend.Evaluator`.
  """
  @spec evaluate(package(), transcript(), keyword()) :: evaluation_result()
  def evaluate(package, transcript, opts) do
    case get_adapter(opts) do
      nil ->
        evaluate_built_in(package, transcript, opts)

      adapter_module when is_atom(adapter_module) ->
        adapter_module.evaluate(package, transcript, opts)
    end
  end

  defp get_adapter(opts) do
    opts[:adapter] || Application.get_env(:backend, :evaluator_adapter)
  end

  defp evaluate_built_in(package, transcript, _opts) do
    rubric = get_rubric(package)
    normalized_messages = normalize_transcript(transcript)

    criteria =
      Enum.map(rubric, fn criterion ->
        evaluate_criterion(criterion, package, normalized_messages)
      end)

    %{criteria: criteria}
  end

  defp get_rubric(package) when is_map(package) do
    package["rubric"] || package[:rubric] || []
  end

  defp get_rubric(_), do: []

  defp evaluate_criterion(criterion, package, messages) do
    id = get_field(criterion, "id") || ""

    recommendation =
      get_field(criterion, "practice_recommendation") || get_field(criterion, "recommendation") ||
        ""

    {inquiry_terms, context_terms} = extract_criterion_terms(criterion, package)

    classified_excerpts =
      Enum.map(messages, fn msg ->
        classify_message(msg, inquiry_terms, context_terms)
      end)

    decisive_matches = for {:decisive, excerpt} <- classified_excerpts, do: excerpt
    ambiguous_matches = for {:ambiguous, excerpt} <- classified_excerpts, do: excerpt
    passive_matches = for {:passive, excerpt} <- classified_excerpts, do: excerpt
    partial_matches = for {:partial, excerpt} <- classified_excerpts, do: excerpt

    cond do
      decisive_matches != [] ->
        %{
          id: id,
          status: :met,
          evidence: decisive_matches,
          recommendation: recommendation
        }

      ambiguous_matches != [] or passive_matches != [] or partial_matches != [] ->
        evidence =
          case ambiguous_matches ++ passive_matches ++ partial_matches do
            [] -> []
            matches -> matches
          end

        %{
          id: id,
          status: :uncertain,
          evidence: evidence,
          recommendation: recommendation
        }

      true ->
        %{
          id: id,
          status: :omitted,
          evidence: [],
          recommendation: recommendation
        }
    end
  end

  defp classify_message(%{text: text} = msg, inquiry_terms, context_terms) do
    downcased = String.downcase(text)

    has_inquiry = contains_any?(downcased, inquiry_terms)
    has_context = contains_any?(downcased, context_terms)
    has_ambiguity = contains_any?(downcased, @ambiguity_markers)
    learner_role? = learner_role?(msg.role)

    cond do
      has_inquiry and has_ambiguity ->
        {:ambiguous, msg}

      has_inquiry and learner_role? ->
        {:decisive, msg}

      has_inquiry and not learner_role? ->
        {:passive, msg}

      has_context and not has_inquiry and learner_role? ->
        {:partial, msg}

      true ->
        {:none, msg}
    end
  end

  defp extract_criterion_terms(criterion, package) do
    id = String.downcase(to_string(get_field(criterion, "id") || ""))
    description = String.downcase(to_string(get_field(criterion, "description") || ""))
    evidence_questions = get_field(criterion, "evidence_questions") || []

    explicit_inquiry =
      (get_field(criterion, "keywords") || get_field(criterion, "inquiry_keywords") || [])
      |> Enum.map(&String.downcase/1)

    explicit_context =
      (get_field(criterion, "context_keywords") || [])
      |> Enum.map(&String.downcase/1)

    domain_match = find_domain_terms(id, description)

    derived_inquiry =
      evidence_questions
      |> Enum.flat_map(&tokenize_meaningful/1)

    expected_actions = get_field(package, "expected_actions") || []
    action_terms = extract_matching_action_terms(id, expected_actions)

    inquiry_terms =
      (explicit_inquiry ++ domain_match.inquiry ++ derived_inquiry ++ action_terms)
      |> Enum.uniq()
      |> Enum.reject(&(&1 == ""))

    context_terms =
      (explicit_context ++ domain_match.context)
      |> Enum.uniq()
      |> Enum.reject(&(&1 == ""))

    {inquiry_terms, context_terms}
  end

  defp find_domain_terms(id, description) do
    combined = id <> " " <> description

    Enum.find_value(@known_domain_terms, %{inquiry: [], context: []}, fn {topic, terms} ->
      if String.contains?(combined, topic) do
        terms
      else
        nil
      end
    end)
  end

  defp extract_matching_action_terms(criterion_id, actions) when is_list(actions) do
    topic =
      criterion_id
      |> String.split(["-", "_"])
      |> List.first() || ""

    actions
    |> Enum.filter(fn action ->
      action_id = String.downcase(to_string(get_field(action, "id") || ""))
      topic != "" and String.contains?(action_id, topic)
    end)
    |> Enum.flat_map(fn action ->
      desc = to_string(get_field(action, "description") || "")
      tokenize_meaningful(desc)
    end)
  end

  defp extract_matching_action_terms(_id, _actions), do: []

  defp tokenize_meaningful(text) when is_binary(text) do
    stop_words =
      ~w(the a an and or did does do was were is are of in on at to for with o a os as de da do em no na para com que um uma)

    text
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}\s]/u, " ")
    |> String.split()
    |> Enum.reject(&(&1 in stop_words or String.length(&1) < 3))
  end

  defp tokenize_meaningful(_), do: []

  defp contains_any?(text, terms) when is_binary(text) and is_list(terms) do
    Enum.any?(terms, fn term ->
      term != "" and String.contains?(text, term)
    end)
  end

  defp contains_any?(_text, _terms), do: false

  defp learner_role?(role) do
    role in [:learner, :student, "learner", "student"]
  end

  defp normalize_transcript(transcript) do
    cond do
      is_list(transcript) ->
        Enum.map(transcript, &normalize_message/1)

      is_map(transcript) and (is_list(transcript[:messages]) or is_list(transcript["messages"])) ->
        messages = transcript[:messages] || transcript["messages"]
        Enum.map(messages, &normalize_message/1)

      is_map(transcript) ->
        [normalize_message(transcript)]

      true ->
        []
    end
  end

  defp normalize_message(msg) when is_map(msg) do
    role = msg[:role] || msg["role"] || :unknown
    text = msg[:text] || msg["text"] || ""
    %{role: role, text: text}
  end

  defp normalize_message(_), do: %{role: :unknown, text: ""}

  defp get_field(map, field) when is_map(map) and is_binary(field) do
    case Map.fetch(map, field) do
      {:ok, val} ->
        val

      :error ->
        try do
          Map.get(map, String.to_existing_atom(field))
        rescue
          ArgumentError -> nil
        end
    end
  end

  defp get_field(_map, _field), do: nil
end
