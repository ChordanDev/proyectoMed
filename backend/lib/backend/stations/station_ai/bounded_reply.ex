defmodule Backend.Stations.StationAI.BoundedReply do
  @moduledoc """
  Enforces the bounded reply policy for every StationAI adapter output.

  `Backend.StationAI.next_reply/2` funnels the adapter's text through
  `bound/2` before returning it to the caller. If any rule fires, the
  canonical refusal text (`Backend.StationAI.refusal_text/0`) replaces the
  adapter's text and the bounded reply is what the caller sees.

  Rules are applied in order, first match wins:

    1. **Malformed** — text is not a binary, blank, or longer than 2000 chars.
    2. **Out-of-scope / roleplay leakage** — text matches one of six
       case-insensitive regexes that catch the adapter breaking character,
       refusing to answer, or identifying itself as a model.
    3. **Language containment** — when the package language is `"pt-BR"`,
       a reply containing any of the configured English markers and none
       of the pt-BR diacritics is refused.
    4. **`response_rules` enforcement** — known rule ids (`length-cap`,
       `max-length`, `polite`) are applied. Unknown ids are ignored.

  The canonical refusal text is always allowed through: if the adapter
  already returned it verbatim, every other check is skipped.
  """

  @max_length 2000

  # Patterns are case-insensitive and Unicode-aware so they catch both
  # diacritic ("inteligência") and non-diacritic ("inteligencia") forms.
  @roleplay_patterns [
    ~r/\bsou\s+(?:um|uma)\s+(?:modelo|ia|intelig[êe]ncia\s+artificial)\b/iu,
    ~r/\bcomo\s+(?:uma?\s+)?(?:ia|intelig[êe]ncia\s+artificial|modelo\s+de\s+linguagem)\b/iu,
    ~r/\bnão\s+posso\s+ajudar\b/iu,
    ~r/\bminhas\s+limita[çc][õo]es\b/iu,
    ~r/\bi\s+am\s+(?:an?\s+ai|a\s+language\s+model)\b/iu,
    ~r/\b(sure|certainly)[,]?\s+(?:i\s+can|i'?d\s+be\s+happy)\b/iu
  ]

  # English-only markers used by the language containment check. The list
  # extends the spec's 15 markers with the standalone pronoun `I ` (capital
  # I followed by a space) so a short English reply such as "No, I don't
  # think so." is correctly caught. All other markers are taken verbatim
  # from the issue spec.
  @english_markers [
    "the ",
    "this ",
    "that ",
    "your ",
    "I ",
    " was ",
    " were ",
    " have ",
    " has ",
    " had ",
    " and ",
    " will ",
    " would ",
    " should ",
    " yes,",
    " sure,"
  ]

  @pt_br_diacritics "áéíóúãõçÁÉÍÓÚÃÕÇ"

  @polite_insults [
    "idiota",
    "burro",
    "imbecil",
    "estúpido",
    "estupido",
    "animal",
    "verme",
    "lixo"
  ]

  @doc """
  Runs deterministic deny checks on `text` against `package`.

  Returns `:ok` if no rule fires.
  Returns `{:error, {:denied, reason}}` if any rule fires:
    * `:malformed` - text is non-binary, blank/empty, or exceeds 2000 chars.
    * `:roleplay_leakage` - text matches roleplay leakage regexes.
    * `:language_containment` - text violates pt-BR language containment.
    * `:response_rules` - text violates package response rules (length-cap, max-length, polite).

  Does not substitute clinical refusal text or fabricate fallbacks.
  """
  @spec check_violations(term(), map()) :: :ok | {:error, {:denied, atom()}}
  def check_violations(text, package) do
    cond do
      not is_binary(text) or malformed?(text) ->
        {:error, {:denied, :malformed}}

      roleplay_leakage?(text) ->
        {:error, {:denied, :roleplay_leakage}}

      language_violation?(text, package) ->
        {:error, {:denied, :language_containment}}

      violates_response_rules?(text, package) ->
        {:error, {:denied, :response_rules}}

      true ->
        :ok
    end
  end

  @doc """
  Returns a bounded version of `text` according to the Station Package
  contract.

  If any rule fires, returns `Backend.StationAI.refusal_text/0`. Otherwise
  returns `text` unchanged. The canonical refusal text is always allowed
  through unchanged, even when it would otherwise look malformed.
  """
  @spec bound(String.t() | term(), map()) :: String.t()
  def bound(text, package) do
    refusal = Backend.Stations.StationAI.refusal_text()

    cond do
      # The canonical refusal is always allowed through verbatim, so it
      # short-circuits every other rule.
      text == refusal ->
        text

      match?({:error, {:denied, _}}, check_violations(text, package)) ->
        refusal

      true ->
        text
    end
  end

  defp malformed?(text) do
    String.trim(text) == "" or String.length(text) > @max_length
  end

  defp roleplay_leakage?(text) do
    Enum.any?(@roleplay_patterns, fn pattern ->
      Regex.match?(pattern, text)
    end)
  end

  defp language_violation?(text, package) when is_map(package) do
    lang = Map.get(package, "language") || Map.get(package, :language)
    lang == "pt-BR" and english_only?(text)
  end

  defp language_violation?(_text, _package), do: false

  defp english_only?(text) do
    has_english_marker = Enum.any?(@english_markers, &String.contains?(text, &1))
    no_pt_br_diacritics = not String.contains?(text, @pt_br_diacritics)
    has_english_marker and no_pt_br_diacritics
  end

  defp violates_response_rules?(text, package) when is_map(package) do
    rules = Map.get(package, "response_rules") || Map.get(package, :response_rules) || []
    Enum.any?(rules, &rule_violates?(&1, text))
  end

  defp violates_response_rules?(_text, _package), do: false

  defp rule_violates?(%{"id" => "length-cap", "max_length" => max}, text)
       when is_integer(max) do
    String.length(text) > max
  end

  defp rule_violates?(%{id: "length-cap", max_length: max}, text)
       when is_integer(max) do
    String.length(text) > max
  end

  defp rule_violates?(%{"id" => "max-length", "max_length" => max}, text)
       when is_integer(max) do
    String.length(text) > max
  end

  defp rule_violates?(%{id: "max-length", max_length: max}, text)
       when is_integer(max) do
    String.length(text) > max
  end

  defp rule_violates?(%{"id" => "polite"}, text) do
    polite_violation?(text)
  end

  defp rule_violates?(%{id: "polite"}, text) do
    polite_violation?(text)
  end

  defp rule_violates?(_rule, _text), do: false

  defp polite_violation?(text) do
    downcased = String.downcase(text)
    Enum.any?(@polite_insults, &String.contains?(downcased, &1))
  end
end

defmodule Backend.StationAI.BoundedReply do
  @moduledoc false
  defdelegate bound(text, package), to: Backend.Stations.StationAI.BoundedReply
  defdelegate check_violations(text, package), to: Backend.Stations.StationAI.BoundedReply
end
