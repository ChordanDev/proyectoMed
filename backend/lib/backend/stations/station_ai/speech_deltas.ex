defmodule Backend.Stations.StationAI.SpeechDeltas do
  @moduledoc """
  The speakable text of a patient reply still being generated, handed to the
  voice worker word by word (issue #313, `VOICE_TTS_STREAMING=token`).

  `settled/2` cuts the raw reply so far (after the addressee marker) at its
  last whitespace, never inside an unclosed stage direction (`*…` or `(…`): a
  word or a direction still arriving is held back until it is complete, or
  until the reply ends. `take/2` turns settled text into speakable text with
  the per-sentence rule the sentence mode uses (`Sentences.split/1`, then
  `Backend.Stations.TTS.StageDirections.strip/1` on each piece, joined by a
  space) and returns what was not handed over yet. The deltas add up to the
  spoken reply. A speakable text that would rewrite what was already handed
  over (rare: a direction that only becomes a closing one later) hands
  nothing over. The text is never logged.

  `mode/0` is `config :backend, :voice_tts_streaming`, set from
  `VOICE_TTS_STREAMING` in `config/runtime.exs`: `:sentence` (default, one
  verified sentence at a time, #271) or `:token`.
  """

  alias Backend.Stations.StationAI.Sentences
  alias Backend.Stations.TTS.StageDirections

  @modes [:sentence, :token]
  @default_mode :sentence

  @type mode :: :sentence | :token

  @doc """
  The configured voice TTS streaming mode. Raises `ArgumentError` when the
  configured value is not `:sentence` or `:token`.
  """
  @spec mode() :: mode()
  def mode do
    case Application.get_env(:backend, :voice_tts_streaming, @default_mode) do
      mode when mode in @modes ->
        mode

      other ->
        raise ArgumentError,
              "invalid :voice_tts_streaming #{inspect(other)}; expected one of #{inspect(@modes)}"
    end
  end

  @doc """
  The part of `raw` that is safe to speak: everything when `final?`, else up
  to its last whitespace outside an unclosed stage direction.
  """
  @spec settled(String.t(), boolean()) :: String.t()
  def settled(raw, true) when is_binary(raw), do: raw

  def settled(raw, false) when is_binary(raw) do
    cut =
      raw
      |> String.graphemes()
      |> Enum.reduce({0, 0, false, 0}, fn grapheme, {offset, cut, star, parens} ->
        offset = offset + byte_size(grapheme)

        {star, parens} =
          case grapheme do
            "*" -> {not star, parens}
            "(" -> {star, parens + 1}
            ")" -> {star, max(parens - 1, 0)}
            _other -> {star, parens}
          end

        open? = star or parens > 0
        cut = if not open? and String.trim(grapheme) == "", do: offset, else: cut
        {offset, cut, star, parens}
      end)
      |> elem(1)

    binary_part(raw, 0, cut)
  end

  @doc """
  The delta of `settled` after `spoken` (the speakable text already handed
  over): `{:delta, delta, spoken}` with the new speakable text, or `:none`.
  """
  @spec take(String.t(), String.t()) :: {:delta, String.t(), String.t()} | :none
  def take(spoken, settled) when is_binary(spoken) and is_binary(settled) do
    {sentences, tail} = Sentences.split(settled)

    speakable =
      (sentences ++ [tail])
      |> Enum.map(&StageDirections.strip/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")

    with true <- String.starts_with?(speakable, spoken),
         delta when delta != "" <-
           binary_part(speakable, byte_size(spoken), byte_size(speakable) - byte_size(spoken)),
         false <- String.trim(delta) == "" do
      {:delta, delta, speakable}
    else
      _nothing_new -> :none
    end
  end
end
