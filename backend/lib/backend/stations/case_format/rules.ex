defmodule Backend.Stations.CaseFormat.Rules do
  @moduledoc """
  Cross-tag rules of a tagged case (issue #330), each reported as an error
  located at the line of the tag that breaks it:

  - required tags (station, area, theme, scenario, a task, an actor, an item);
  - exactly one patient actor;
  - unique ids, and links that resolve to existing actors, PEP criteria,
    impressos and mandatory questions;
  - criterion types and the attributes each type requires or forbids;
  - points in multiples of 0,025 whose item maximums sum to 10,0;
  - levels with numeric thresholds (`mínimo`) that a learner can reach.
  """

  alias Backend.Stations.CaseFormat.Document
  alias Backend.Stations.CaseFormat.Values

  @required_singles ["ESTACAO", "AREA", "TEMA", "CENARIO"]
  @level_labels ["inadequado", "parcialmente_adequado", "adequado"]
  @station_total 400

  # type => {required attributes, forbidden attributes}
  @type_attrs %{
    "question" => {[], ["impressos", "apos", "perguntas"]},
    "request" => {["impressos"], ["apos", "perguntas"]},
    "verbalization" => {["apos"], ["impressos", "perguntas"]},
    "communication" => {[], ["impressos", "apos"]}
  }

  @doc "Returns every rule error of `doc`, in no particular order."
  @spec check(Document.t()) :: [%{line: pos_integer(), message: String.t()}]
  def check(doc) do
    index = index(doc)

    List.flatten([
      required_tags(doc),
      unique_ids(doc),
      placeholder(doc),
      Enum.map(doc.actors, &actor/1),
      patients(doc),
      companions(doc),
      Enum.map(doc.facts, &fact(&1, index)),
      Enum.map(doc.impressos, &impresso/1),
      Enum.map(doc.items, &item(&1, index)),
      total(doc)
    ])
  end

  @doc "The fortieths of each level whose pontos and mínimo are valid, or `:error`."
  @spec thresholds(Document.item()) ::
          {:ok, [{map(), non_neg_integer(), non_neg_integer()}]} | :error
  def thresholds(%{levels: levels}) do
    Enum.reduce_while(levels, {:ok, []}, fn level, {:ok, acc} ->
      with {:ok, points} <- fetch(level, "pontos"),
           {:ok, _number, fortieths} <- Values.points(points),
           {:ok, minimum} <- fetch(level, "minimo"),
           {:ok, minimum} <- Values.non_negative_integer(minimum) do
        {:cont, {:ok, acc ++ [{level, fortieths, minimum}]}}
      else
        _invalid -> {:halt, :error}
      end
    end)
  end

  defp fetch(tag, key), do: Map.fetch(tag.attrs, key)

  defp error(line, message), do: %{line: line, message: message}

  # ---------------------------------------------------------------------------
  # Index of the declared ids
  # ---------------------------------------------------------------------------

  defp index(doc) do
    criteria =
      for %{tag: item, criteria: criteria} <- doc.items,
          criterion <- criteria,
          is_binary(criterion.id),
          into: %{} do
        {{item.id, criterion.id}, criterion_type(criterion)}
      end

    %{
      actors: ids(Enum.map(doc.actors, & &1.tag)),
      impressos: ids(Enum.map(doc.impressos, & &1.tag)),
      questions: ids(for %{kind: :question, tag: tag} <- doc.facts, do: tag),
      criteria: criteria,
      linked: linked_criteria(doc.facts)
    }
  end

  defp ids(tags), do: MapSet.new(for %{id: id} when is_binary(id) <- tags, do: id)

  defp linked_criteria(facts) do
    for %{tag: %{attrs: %{"pep" => pep}}} <- facts,
        {:ok, item, criterion} <- [Values.pep(pep)],
        into: MapSet.new(),
        do: {item, criterion}
  end

  defp criterion_type(criterion) do
    with {:ok, tipo} <- fetch(criterion, "tipo"),
         {:ok, type} <- Values.type(tipo) do
      type
    else
      _invalid -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # Station
  # ---------------------------------------------------------------------------

  defp required_tags(doc) do
    singles =
      for name <- @required_singles, not Map.has_key?(doc.singles, name) do
        error(1, "missing [#{Document.label(name)}] tag")
      end

    [
      singles,
      if(doc.tasks == [], do: error(1, "missing [TAREFA] tag"), else: []),
      if(doc.actors == [], do: error(1, "missing actor: the case declares no [ATOR]"), else: []),
      if(doc.items == [], do: error(1, "missing [ITEM] tag"), else: [])
    ]
  end

  defp unique_ids(doc) do
    tags =
      doc.tasks ++
        doc.expected ++
        doc.rules ++
        Enum.map(doc.actors ++ doc.impressos ++ doc.items ++ doc.facts, & &1.tag)

    tags |> Enum.filter(&is_binary(&1.id)) |> Enum.sort_by(& &1.line) |> duplicates("id")
  end

  # The errors for every tag whose id an earlier tag of `tags` already took.
  defp duplicates(tags, what) do
    {errors, _first} =
      Enum.reduce(tags, {[], %{}}, fn %{id: id} = tag, {errors, first} ->
        case first do
          %{^id => line} ->
            {[
               error(tag.line, "duplicate #{what} #{tag.id} (first defined on line #{line})")
               | errors
             ], first}

          _new ->
            {errors, Map.put(first, tag.id, tag.line)}
        end
      end)

    errors
  end

  defp placeholder(%{singles: %{"PROVISORIO" => tag}}) do
    case Values.boolean(tag.value) do
      {:ok, _placeholder} -> []
      :error -> error(tag.line, "[PROVISÓRIO] must be sim or não, found #{tag.value}")
    end
  end

  defp placeholder(_doc), do: []

  # ---------------------------------------------------------------------------
  # Actors and facts
  # ---------------------------------------------------------------------------

  defp actor(%{tag: tag, children: children}) do
    role = actor_role(tag)
    required = if role == "patient", do: ["PERFIL", "TOM", "CONTEXTO"], else: ["PERFIL", "TOM"]

    [
      role_error(tag),
      age_error(tag),
      for name <- required, not Map.has_key?(children, name) do
        error(tag.line, "missing [#{Document.label(name)}] for actor #{tag.id}")
      end
    ]
  end

  defp actor_role(tag) do
    with {:ok, papel} <- fetch(tag, "papel"),
         {:ok, role} <- Values.role(papel) do
      role
    else
      _invalid -> nil
    end
  end

  defp role_error(%{attrs: %{"papel" => papel}} = tag) do
    case Values.role(papel) do
      {:ok, _role} -> []
      :error -> error(tag.line, "invalid papel=#{papel}; expected paciente or acompanhante")
    end
  end

  defp role_error(_tag), do: []

  defp age_error(%{attrs: %{"idade" => idade}} = tag) do
    case Values.non_negative_integer(idade) do
      {:ok, _age} -> []
      :error -> error(tag.line, "idade must be a non-negative integer, found #{idade}")
    end
  end

  defp age_error(_tag), do: []

  defp patients(doc) do
    case Enum.filter(doc.actors, &(actor_role(&1.tag) == "patient")) do
      [] when doc.actors != [] ->
        error(1, "missing actor: no [ATOR] has papel=paciente")

      [_first | others] ->
        for %{tag: tag} <- others, do: error(tag.line, "only one [ATOR] may have papel=paciente")

      [] ->
        []
    end
  end

  # Issue #341: one `[ACOMPANHANTE]` marker cannot tell two companions apart.
  defp companions(doc) do
    case Enum.filter(doc.actors, &(actor_role(&1.tag) == "companion")) do
      [_first | others] ->
        for %{tag: tag} <- others,
            do: error(tag.line, "only one [ATOR] may have papel=acompanhante")

      [] ->
        []
    end
  end

  defp fact(%{tag: tag}, index) do
    [actor_link(tag, index), pep_link(tag, index)]
  end

  defp actor_link(%{attrs: %{"ator" => actor}} = tag, index) do
    if MapSet.member?(index.actors, actor),
      do: [],
      else: error(tag.line, "unknown actor #{actor}")
  end

  defp actor_link(_tag, _index), do: []

  defp pep_link(%{attrs: %{"pep" => pep}} = tag, index) do
    with {:ok, item, criterion} <- Values.pep(pep),
         {:ok, type} <- Map.fetch(index.criteria, {item, criterion}) do
      if type in ["question", nil],
        do: [],
        else: error(tag.line, "pep=#{pep} must name a PERGUNTA criterion")
    else
      :error -> error(tag.line, "unknown PEP criterion #{pep}; expected pep=item-id.criterion-id")
    end
  end

  defp pep_link(_tag, _index), do: []

  # ---------------------------------------------------------------------------
  # Impressos
  # ---------------------------------------------------------------------------

  defp impresso(%{tag: tag, children: children}) do
    [
      category_error(tag),
      for name <- ["LIBERACAO", "CONTEUDO"], not Map.has_key?(children, name) do
        error(tag.line, "missing [#{Document.label(name)}] for impresso #{tag.id}")
      end
    ]
  end

  defp category_error(%{attrs: %{"categoria" => category}} = tag) do
    case Values.category(category) do
      {:ok, _category} ->
        []

      :error ->
        error(
          tag.line,
          "invalid categoria=#{category}; expected exame-fisico, laboratorio, imagem or registro"
        )
    end
  end

  defp category_error(_tag), do: []

  # ---------------------------------------------------------------------------
  # PEP items
  # ---------------------------------------------------------------------------

  defp item(%{tag: tag, criteria: criteria, levels: levels} = item, index) do
    [
      if(criteria == [], do: error(tag.line, "missing [CRITÉRIO] for item #{tag.id}"), else: []),
      if(levels == [], do: error(tag.line, "missing [NÍVEL] for item #{tag.id}"), else: []),
      criteria |> Enum.filter(&is_binary(&1.id)) |> duplicates("criterion id"),
      Enum.map(criteria, &criterion(&1, tag.id, index)),
      Enum.map(levels, &level/1),
      levels |> Enum.filter(&is_binary(&1.id)) |> duplicates("level"),
      threshold_errors(item)
    ]
  end

  defp criterion(tag, item_id, index) do
    case criterion_type(tag) do
      nil ->
        type_error(tag)

      type ->
        [
          type_attrs(tag, type),
          links(tag, index),
          roles(tag),
          question(tag, type, item_id, index)
        ]
    end
  end

  defp type_error(%{attrs: %{"tipo" => tipo}} = tag) do
    error(
      tag.line,
      "invalid tipo=#{tipo}; expected PERGUNTA, SOLICITAÇÃO, VERBALIZAÇÃO or COMUNICAÇÃO"
    )
  end

  defp type_error(_tag), do: []

  defp type_attrs(tag, type) do
    {required, forbidden} = Map.fetch!(@type_attrs, type)
    tipo = tag.attrs["tipo"]

    [
      for key <- required, not Map.has_key?(tag.attrs, key) do
        error(tag.line, "tipo=#{tipo} requires the attribute #{key}=")
      end,
      for key <- forbidden, Map.has_key?(tag.attrs, key) do
        error(tag.line, "tipo=#{tipo} does not allow the attribute #{key}=")
      end
    ]
  end

  defp links(tag, index) do
    [
      for key <- ["impressos", "apos", "perguntas"],
          Map.has_key?(tag.attrs, key),
          Values.ids(tag.attrs[key]) == [] do
        error(tag.line, "#{key}= must list at least one id")
      end,
      for key <- ["impressos", "apos"],
          id <- Values.ids(Map.get(tag.attrs, key, "")),
          not MapSet.member?(index.impressos, id) do
        error(tag.line, "unknown impresso #{id}")
      end,
      for id <- Values.ids(Map.get(tag.attrs, "perguntas", "")),
          not MapSet.member?(index.questions, id) do
        error(tag.line, "unknown mandatory question #{id}")
      end
    ]
  end

  defp roles(tag) do
    if "OBRIGATORIO" in tag.flags and "PROIBIDO" in tag.flags,
      do: error(tag.line, "a criterion cannot be both OBRIGATÓRIO and PROIBIDO"),
      else: []
  end

  defp question(tag, "question", item_id, index) do
    if MapSet.member?(index.linked, {item_id, tag.id}),
      do: [],
      else:
        error(
          tag.line,
          "PERGUNTA criterion #{item_id}.#{tag.id} has no [FATO] with pep=#{item_id}.#{tag.id}"
        )
  end

  defp question(_tag, _type, _item_id, _index), do: []

  defp level(tag) do
    [level_label(tag), level_points(tag), level_minimum(tag)]
  end

  defp level_label(%{id: label} = tag) when is_binary(label) and label not in @level_labels do
    error(
      tag.line,
      "invalid level #{label}; expected adequado, parcialmente_adequado or inadequado"
    )
  end

  defp level_label(_tag), do: []

  defp level_points(%{attrs: %{"pontos" => points}} = tag) do
    case Values.points(points) do
      {:ok, _number, _fortieths} ->
        []

      {:error, :invalid} ->
        error(tag.line, "pontos must be a non-negative number, found #{points}")

      {:error, :not_a_multiple} ->
        error(tag.line, "pontos=#{points} is not a multiple of 0,025")
    end
  end

  defp level_points(_tag), do: []

  defp level_minimum(%{attrs: %{"minimo" => minimum}} = tag) do
    case Values.non_negative_integer(minimum) do
      {:ok, _minimum} -> []
      :error -> error(tag.line, "mínimo must be a non-negative integer, found #{minimum}")
    end
  end

  defp level_minimum(_tag), do: []

  # Threshold consistency is checked only on a complete, well-typed set of
  # levels, so each defect is reported once.
  defp threshold_errors(%{tag: tag, criteria: criteria} = item) do
    case thresholds(item) do
      {:ok, [_ | _] = levels} -> reachable(tag, levels, countable(criteria))
      _invalid -> []
    end
  end

  defp countable(criteria), do: Enum.count(criteria, &("PROIBIDO" not in &1.flags))

  defp reachable(tag, levels, countable) do
    highest = levels |> Enum.map(&elem(&1, 2)) |> Enum.max()

    [
      if(Enum.any?(levels, &(elem(&1, 1) == 0)),
        do: [],
        else: error(tag.line, "item #{tag.id} requires a [NÍVEL] with pontos=0")
      ),
      for {level, 0, minimum} <- levels, minimum != 0 do
        error(level.line, "a level with pontos=0 must set mínimo=0")
      end,
      for {level, points, 0} <- levels, points > 0 do
        error(level.line, "a level with pontos above zero must set mínimo to at least 1")
      end,
      order_error(tag, levels),
      if(highest > countable,
        do:
          error(
            tag.line,
            "mínimo=#{highest} exceeds the #{countable} criteria that are not PROIBIDO"
          ),
        else: []
      )
    ]
  end

  defp order_error(tag, levels) do
    minimums = levels |> Enum.sort_by(&{elem(&1, 1), elem(&1, 2)}) |> Enum.map(&elem(&1, 2))

    if minimums == Enum.sort(minimums),
      do: [],
      else: error(tag.line, "mínimo must not decrease as pontos increase in item #{tag.id}")
  end

  # The total is checked only when every item has valid levels, so a broken
  # level is not reported twice.
  defp total(%{items: [first | _] = items}) do
    maximums = Enum.map(items, &thresholds/1)

    if Enum.all?(maximums, &match?({:ok, [_ | _]}, &1)) do
      total = maximums |> Enum.map(&item_maximum/1) |> Enum.sum()

      if total == @station_total,
        do: [],
        else:
          error(
            first.tag.line,
            "the item maximums sum to #{Values.format_points(total)}; the PEP must total 10,0"
          )
    else
      []
    end
  end

  defp total(_doc), do: []

  defp item_maximum({:ok, levels}), do: levels |> Enum.map(&elem(&1, 1)) |> Enum.max()
end
