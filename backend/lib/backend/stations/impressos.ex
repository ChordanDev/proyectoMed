defmodule Backend.Stations.Impressos do
  @moduledoc """
  Deterministic keyword matching for learner Impresso (physical exam / labs /
  imaging / report) requests against the active Station Package.

  Matching is a normalized (downcased, accent-stripped) keyword substring
  match anchored at a word start — no LLM involved.
  """

  @combining_marks_range 0x0300..0x036F

  # Word-start anchors: a cue or connector must be a whole word.
  @clause_boundary ~r/[.!?;,]|(?<![[:alnum:]])(?:mas|porem)(?![[:alnum:]])|(?<![[:alnum:]])e(?=\s+(?:solicito|peco)(?![[:alnum:]]))/u
  @leading_negation ~r/(?<![[:alnum:]])(?:nao|nem|sem|dispenso|dispensa)(?![[:alnum:]])/u
  @trailing_negation ~r/(?<![[:alnum:]])nao(?:\s+(?:e\s+necessari[oa]s?|sera\s+necessari[oa]s?|precisa))?\s*$/u

  @doc """
  Downcases `text` and strips diacritics via NFD decomposition, so
  "Crânio" and "cranio" compare equal.
  """
  @spec normalize(String.t()) :: String.t()
  def normalize(text) when is_binary(text) do
    text
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> strip_combining_marks()
  end

  defp strip_combining_marks(binary) do
    binary
    |> String.to_charlist()
    |> Enum.reject(&(&1 in @combining_marks_range))
    |> List.to_string()
  end

  @doc """
  Returns the ids of every impresso (in authored order) whose keywords occur
  in `normalized_text` starting at a word boundary. `impressos` is the raw
  package `impressos` list (string-keyed maps).

  A keyword may end inside a longer word ("eletrocardiograma" matches
  "eletrocardiogramas"), but must not start inside one, so short authored
  abbreviations such as "EAS", "TC" or "sódio" do not match inside "áreas",
  "etc" or "episódio".

  A keyword occurrence the learner names only to decline it does not match
  (#305). The text is split into clauses at sentence punctuation, ";", ",",
  "mas", "porém", or an "e" that starts a new request ("e solicito",
  "e peço"). Within a clause, an occurrence is declined when a negation cue
  ("não", "nem", "sem", "dispenso", "dispensa", which also cover "não
  preciso", "não vou pedir", "não é necessário"...) precedes it, or when the
  clause ends in a trailing "não" / "não é necessário(a)" / "não precisa"
  ("tomografia não é necessária"). An impresso matches when any occurrence of
  any of its keywords is not declined.
  """
  @spec match([map()], String.t()) :: [String.t()]
  def match(impressos, normalized_text) when is_list(impressos) and is_binary(normalized_text) do
    clauses = Regex.split(@clause_boundary, normalized_text)

    impressos
    |> Enum.filter(fn impresso ->
      Enum.any?(impresso["keywords"] || [], &requested?(clauses, &1))
    end)
    |> Enum.map(& &1["id"])
  end

  defp requested?(clauses, keyword) do
    pattern = Regex.compile!("(?<![[:alnum:]])" <> Regex.escape(normalize(keyword)), "u")

    Enum.any?(clauses, fn clause ->
      pattern
      |> Regex.scan(clause, return: :index)
      |> Enum.any?(fn [{start, length}] -> not declined?(clause, start, length) end)
    end)
  end

  defp declined?(clause, start, length) do
    before = binary_part(clause, 0, start)
    rest = binary_part(clause, start + length, byte_size(clause) - start - length)

    Regex.match?(@leading_negation, before) or Regex.match?(@trailing_negation, rest)
  end

  @doc """
  Decides the release outcome for a request given its matched impresso ids
  and the ids already released for the session.

  Returns `{:unavailable, []}` when nothing matched, `{:already_released, []}`
  when every matched id was already released, or `{:released, newly_released}`
  with the subset of `matched_ids` (in authored order) that is newly released.
  """
  @spec decide([String.t()], [String.t()]) ::
          {:unavailable | :already_released | :released, [String.t()]}
  def decide([], _previously_released), do: {:unavailable, []}

  def decide(matched_ids, previously_released) do
    case Enum.reject(matched_ids, &(&1 in previously_released)) do
      [] -> {:already_released, []}
      newly_released -> {:released, newly_released}
    end
  end

  @doc """
  Generates a server-side request id when the client omits one, using the
  same url-safe random scheme as session ids.
  """
  @spec generate_request_id() :: String.t()
  def generate_request_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
