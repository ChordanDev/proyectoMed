defmodule Backend.Stations.Impressos do
  @moduledoc """
  Deterministic keyword matching for learner Impresso (physical exam / labs /
  imaging / report) requests against the active Station Package.

  Matching is a normalized (downcased, accent-stripped) keyword substring
  match anchored at a word start — no LLM involved.
  """

  @combining_marks_range 0x0300..0x036F

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
  """
  @spec match([map()], String.t()) :: [String.t()]
  def match(impressos, normalized_text) when is_list(impressos) and is_binary(normalized_text) do
    impressos
    |> Enum.filter(fn impresso ->
      Enum.any?(impresso["keywords"] || [], &keyword_match?(normalized_text, &1))
    end)
    |> Enum.map(& &1["id"])
  end

  defp keyword_match?(normalized_text, keyword) do
    pattern = Regex.compile!("(?<![[:alnum:]])" <> Regex.escape(normalize(keyword)), "u")
    Regex.match?(pattern, normalized_text)
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
