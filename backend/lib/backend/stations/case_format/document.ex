defmodule Backend.Stations.CaseFormat.Document do
  @moduledoc """
  Groups the tags of a tagged case (issue #330) into a document: the station
  tags, the actors with their profile tags, the facts with their topic, the
  impressos with their release and content tags, and the PEP items with their
  criteria and levels.

  It checks the shape of each tag (known name, id, attributes, flags, value)
  and its place (a child tag must follow its parent, a station tag appears
  once). Cross-references are checked later by `Backend.Stations.CaseFormat.Rules`.
  """

  alias Backend.Stations.CaseFormat.Tags

  @typedoc "A parent tag and the child tags that follow it."
  @type entry :: %{tag: Tags.tag(), children: %{String.t() => Tags.tag()}}

  @typedoc "A PEP item with its criteria and levels, in document order."
  @type item :: %{tag: Tags.tag(), criteria: [Tags.tag()], levels: [Tags.tag()]}

  @typedoc "A fact or mandatory question with the topic it was declared under."
  @type fact :: %{tag: Tags.tag(), topic: Tags.tag() | nil, kind: :fact | :question}

  @type t :: %{
          singles: %{String.t() => Tags.tag()},
          tasks: [Tags.tag()],
          expected: [Tags.tag()],
          rules: [Tags.tag()],
          actors: [entry()],
          facts: [fact()],
          impressos: [entry()],
          items: [item()]
        }

  # name => {placement, takes an id?, value required?, required attributes,
  #          optional attributes, flags}
  @specs %{
    "ESTACAO" => {:single, true, false, [], [], []},
    "AREA" => {:single, false, true, [], [], []},
    "TEMA" => {:single, false, true, [], [], []},
    "PROVISORIO" => {:single, false, true, [], [], []},
    "CENARIO" => {:single, false, true, [], [], []},
    "TAREFA" => {:tasks, true, true, [], [], []},
    "CONDUTA-ESPERADA" => {:expected, true, true, [], [], []},
    "REGRA" => {:rules, true, true, [], [], []},
    "TOPICO" => {:topic, false, true, [], [], []},
    "ATOR" => {{:parent, :actors}, true, true, ["papel", "idade", "voz"], [], []},
    "PERFIL" => {{:child, :actors}, false, true, [], [], []},
    "TOM" => {{:child, :actors}, false, true, [], [], []},
    "CONTEXTO" => {{:child, :actors}, false, true, [], [], []},
    "FATO" => {{:fact, :fact}, true, true, ["ator"], ["pep"], ["EXPLICITO"]},
    "PERGUNTA-OBRIGATORIA" => {{:fact, :question}, true, true, ["ator"], [], []},
    "IMPRESSO" => {{:parent, :impressos}, true, true, ["categoria"], [], []},
    "LIBERACAO" => {{:child, :impressos}, false, false, [], [], []},
    "CONTEUDO" => {{:child, :impressos}, false, true, [], [], []},
    "ITEM" => {{:parent, :items}, true, true, [], [], []},
    "CRITERIO" =>
      {{:list, :items, :criteria}, true, true, ["tipo"], ["impressos", "apos", "perguntas"],
       ["OBRIGATORIO", "PROIBIDO"]},
    "NIVEL" => {{:list, :items, :levels}, true, true, ["pontos", "minimo"], [], []}
  }

  @labels %{
    "ESTACAO" => "ESTAÇÃO",
    "AREA" => "ÁREA",
    "TEMA" => "TEMA",
    "PROVISORIO" => "PROVISÓRIO",
    "CENARIO" => "CENÁRIO",
    "TAREFA" => "TAREFA",
    "CONDUTA-ESPERADA" => "CONDUTA-ESPERADA",
    "REGRA" => "REGRA",
    "TOPICO" => "TÓPICO",
    "ATOR" => "ATOR",
    "PERFIL" => "PERFIL",
    "TOM" => "TOM",
    "CONTEXTO" => "CONTEXTO",
    "FATO" => "FATO",
    "PERGUNTA-OBRIGATORIA" => "PERGUNTA-OBRIGATÓRIA",
    "IMPRESSO" => "IMPRESSO",
    "LIBERACAO" => "LIBERAÇÃO",
    "CONTEUDO" => "CONTEÚDO",
    "ITEM" => "ITEM",
    "CRITERIO" => "CRITÉRIO",
    "NIVEL" => "NÍVEL"
  }

  @parents %{actors: "ATOR", impressos: "IMPRESSO", items: "ITEM"}

  @doc "The canonical, accented label of a tag name (`ESTACAO` is `ESTAÇÃO`)."
  @spec label(String.t()) :: String.t()
  def label(name), do: Map.get(@labels, name, name)

  @doc "Groups `tags` into a document and returns the shape and placement errors."
  @spec collect([Tags.tag()]) :: {t(), [Tags.error()]}
  def collect(tags) do
    empty = %{
      singles: %{},
      tasks: [],
      expected: [],
      rules: [],
      actors: [],
      facts: [],
      impressos: [],
      items: []
    }

    state =
      tags
      |> Enum.reduce(%{doc: empty, errors: [], open: nil, topic: nil}, &collect_tag/2)
      |> flush()

    {finalize(state.doc), Enum.reverse(state.errors)}
  end

  defp collect_tag(tag, state) do
    case Map.fetch(@specs, tag.name) do
      {:ok, {placement, id?, value?, required, optional, flags}} ->
        state
        |> check_id(tag, id?)
        |> check_value(tag, value?)
        |> check_attrs(tag, required, optional)
        |> check_flags(tag, flags)
        |> place(tag, placement)

      :error ->
        error(state, tag.line, "unknown tag [#{tag.label}]")
    end
  end

  defp check_id(state, %{id: nil} = tag, true),
    do: error(state, tag.line, "[#{label(tag.name)}] requires an id")

  defp check_id(state, %{id: id} = tag, false) when is_binary(id),
    do: error(state, tag.line, "[#{label(tag.name)}] takes no id, found #{id}")

  defp check_id(state, _tag, _id?), do: state

  defp check_value(state, %{value: ""} = tag, true),
    do: error(state, tag.line, "[#{label(tag.name)}] requires a value")

  defp check_value(state, _tag, _value?), do: state

  defp check_attrs(state, tag, required, optional) do
    state =
      Enum.reduce(required, state, fn key, state ->
        if Map.has_key?(tag.attrs, key),
          do: state,
          else: error(state, tag.line, "[#{label(tag.name)}] requires the attribute #{key}=")
      end)

    tag.attrs
    |> Map.keys()
    |> Enum.sort()
    |> Enum.reject(&(&1 in required or &1 in optional))
    |> Enum.reduce(state, fn key, state ->
      error(state, tag.line, "unknown attribute #{key}= on [#{label(tag.name)}]")
    end)
  end

  defp check_flags(state, tag, allowed) do
    tag.flags
    |> Enum.reject(&(&1 in allowed))
    |> Enum.reduce(state, fn flag, state ->
      error(state, tag.line, "unknown flag #{flag} on [#{label(tag.name)}]")
    end)
  end

  defp place(state, tag, :single) do
    state = flush(state)
    name = tag.name

    case state.doc.singles do
      %{^name => first} ->
        error(state, tag.line, "duplicate [#{label(tag.name)}] (first on line #{first.line})")

      singles ->
        put_doc(state, :singles, Map.put(singles, tag.name, tag))
    end
  end

  defp place(state, tag, :topic), do: %{flush(state) | topic: tag}

  defp place(state, tag, {:fact, kind}) do
    state = flush(state)
    fact = %{tag: tag, topic: state.topic, kind: kind}
    state = prepend(state, :facts, fact)

    if state.topic == nil,
      do: error(state, tag.line, "[#{label(tag.name)}] requires a preceding [TÓPICO]"),
      else: state
  end

  defp place(state, tag, {:parent, key}) do
    entry =
      if key == :items,
        do: %{tag: tag, criteria: [], levels: []},
        else: %{tag: tag, children: %{}}

    %{flush(state) | open: {key, entry}}
  end

  defp place(%{open: {key, entry}} = state, %{name: name} = tag, {:child, key}) do
    case entry.children do
      %{^name => first} ->
        error(state, tag.line, "duplicate [#{label(tag.name)}] (first on line #{first.line})")

      children ->
        %{state | open: {key, %{entry | children: Map.put(children, tag.name, tag)}}}
    end
  end

  defp place(%{open: {key, entry}} = state, tag, {:list, key, field}),
    do: %{state | open: {key, Map.update!(entry, field, &[tag | &1])}}

  defp place(state, tag, {:child, key}), do: misplaced(state, tag, key)
  defp place(state, tag, {:list, key, _field}), do: misplaced(state, tag, key)

  defp place(state, tag, key), do: state |> flush() |> prepend(key, tag)

  defp misplaced(state, tag, key) do
    error(
      state,
      tag.line,
      "[#{label(tag.name)}] must follow an [#{label(@parents[key])}]"
    )
  end

  defp flush(%{open: nil} = state), do: state
  defp flush(%{open: {key, entry}} = state), do: %{prepend(state, key, entry) | open: nil}

  defp prepend(state, key, value), do: put_doc(state, key, [value | Map.fetch!(state.doc, key)])

  defp put_doc(state, key, value), do: %{state | doc: Map.put(state.doc, key, value)}

  defp finalize(doc) do
    doc
    |> Map.new(fn
      {:singles, singles} -> {:singles, singles}
      {key, list} -> {key, Enum.reverse(list)}
    end)
    |> Map.update!(:items, fn items ->
      Enum.map(
        items,
        &%{&1 | criteria: Enum.reverse(&1.criteria), levels: Enum.reverse(&1.levels)}
      )
    end)
  end

  defp error(state, line, message),
    do: %{state | errors: [%{line: line, message: message} | state.errors]}
end
