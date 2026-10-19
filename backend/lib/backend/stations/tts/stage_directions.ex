defmodule Backend.Stations.TTS.StageDirections do
  @moduledoc """
  Removes the patient's nonverbal stage directions from the text sent to a voice
  provider, so "Ouvir resposta" speaks only the patient's words.

  The rule, applied in order:

    1. Every `*…*` span is removed, e.g. `*(curvado, com a mão na barriga)*` or `*suspira*`.
    2. A parenthesized group at the very start of the reply is removed,
       e.g. `(evitando mexer o tronco) Começou ontem.`
    3. A parenthesized group at the very end of the reply is removed only when it
       stands alone: it is the whole reply or follows sentence-ending punctuation,
       e.g. `Começou ontem. (geme baixinho)`.

  Parentheses inside a sentence (`Tomei dipirona (500 mg) ontem.`) or closing a
  sentence without punctuation before them (`Tomo losartana (para pressão)`) are kept.
  Whitespace left behind is collapsed. Only the synthesized text changes: the
  transcript keeps the full reply. The text is never logged.
  """

  @star_span ~r/\*[^*]*\*/u
  @leading_action ~r/\A\s*\([^()]*\)/u
  @closing_action ~r/(\A|[.!?…])\s*\([^()]*\)\s*\z/u
  @space_runs ~r/[ \t]{2,}/u
  @space_before_punctuation ~r/[ \t]+([.,!?;:…])/u

  @doc "Returns `text` without stage directions, trimmed; `\"\"` when nothing speakable remains."
  @spec strip(String.t()) :: String.t()
  def strip(text) when is_binary(text) do
    trimmed = String.trim(text)

    stripped =
      trimmed
      |> String.replace(@star_span, " ")
      |> String.replace(@leading_action, "")
      |> String.trim()
      |> String.replace(@closing_action, "\\1")

    if stripped == trimmed, do: trimmed, else: tidy(stripped)
  end

  # Only text that lost a stage direction is tidied; other replies pass through as-is.
  defp tidy(text) do
    text
    |> String.replace(@space_runs, " ")
    |> String.replace(@space_before_punctuation, "\\1")
    |> String.trim()
  end
end
