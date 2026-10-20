defmodule Backend.Stations.StationAI.Sentences do
  @moduledoc """
  Splits streamed patient text into complete sentences (issue #271), so each
  sentence can be verified and spoken while the next one is generated.

  `split/1` returns the complete sentences of a buffer and the unfinished tail.
  The pieces are raw: `Enum.join(sentences) <> rest` is the buffer, so a
  sentence keeps the whitespace before it and the stored reply keeps the
  model's own spacing.

  A sentence ends at whitespace that follows `.`, `!`, `?` or `…` (a run of
  them, and closing quotes after them, stay with the sentence), or at a
  newline. It never ends inside a stage direction (`*…*` or `(…)`), so the
  per-sentence stage-direction rule (`Backend.Stations.TTS.StageDirections`)
  sees whole directions, nor after a common pt-BR abbreviation such as
  `Dr.` or `Sra.`. Punctuation not yet followed by whitespace may still be
  part of a number or a run, so it stays in the tail until more text arrives
  or the stream ends. The text is never logged.
  """

  @terminal ~w(. ! ? …)
  @closing_quotes ~w(" ' ” ’ »)
  @abbreviation ~r/(?:\A|[\s(])(?:Dr|Dra|Drs|Dras|Sr|Sra|Srs|Sras|Prof|Profa|Exmo|Exma|etc|Av|Obs)\.\z/iu

  @doc "Returns `{complete_sentences, unfinished_tail}` for `text`."
  @spec split(String.t()) :: {[String.t()], String.t()}
  def split(text) when is_binary(text) do
    text
    |> String.graphemes()
    |> scan(%{current: [], last: [], star: false, parens: 0}, [])
  end

  defp scan([], state, sentences), do: {Enum.reverse(sentences), current(state)}

  defp scan([grapheme | rest], state, sentences) do
    if boundary?(grapheme, state) do
      sentence = current(state)
      scan(rest, push(%{state | current: [], last: []}, grapheme), [sentence | sentences])
    else
      scan(rest, push(state, grapheme), sentences)
    end
  end

  defp push(state, grapheme) do
    state = %{state | current: [state.current, grapheme]}

    state =
      case grapheme do
        "*" -> %{state | star: not state.star}
        "(" -> %{state | parens: state.parens + 1}
        ")" -> %{state | parens: max(state.parens - 1, 0)}
        _other -> state
      end

    if String.trim(grapheme) == "",
      do: state,
      else: %{state | last: Enum.take([grapheme | state.last], 3)}
  end

  defp current(state), do: IO.iodata_to_binary(state.current)

  defp boundary?(grapheme, %{star: false, parens: 0} = state) do
    cond do
      String.trim(grapheme) != "" -> false
      String.trim(current(state)) == "" -> false
      grapheme in ["\n", "\r\n"] -> true
      true -> sentence_end?(state)
    end
  end

  defp boundary?(_grapheme, _state), do: false

  defp sentence_end?(%{last: last} = state) do
    last
    |> Enum.drop_while(&(&1 in @closing_quotes))
    |> List.first()
    |> Kernel.in(@terminal)
    |> Kernel.and(not Regex.match?(@abbreviation, String.trim_trailing(current(state))))
  end
end
