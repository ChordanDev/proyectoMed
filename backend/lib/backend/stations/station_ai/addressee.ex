defmodule Backend.Stations.StationAI.Addressee do
  @moduledoc """
  The addressee marker the patient generator starts every reply with (issue
  #309, `docs/design/turn-addressee.md`): `[PACIENTE]` when the learner talks to
  the patient, `[EXAMINADOR:EXAME]` when the learner asks the examiner for an
  exam, a maneuver or a result (issue #351), `[EXAMINADOR]` for any other turn
  to the examiner (nothing else follows either examiner marker). Both examiner
  markers are examiner-addressed; the exam marker has source `:exam_marker`,
  which only flags the turn as an exam request (display-only, #351).

  The marker is read in code from the first characters of the reply and is
  never part of the text handed on: nothing of it is verified, spoken, shown or
  stored. It is read without regard to case or spaces inside the brackets. A
  reply that does not start with a known marker is patient-addressed with
  source `:missing_marker` and keeps its whole text, so an unknown bracket such
  as a stage direction is not lost.

  A station with a companion (issue #341) adds `[ACOMPANHANTE]`: the learner
  talks to the companion, whose reply follows the marker. It is read only when
  the caller passes `companion: true`; without it `[ACOMPANHANTE]` is an
  unknown marker, as before, so a station without a companion is unchanged.
  """

  @markers %{
    "PACIENTE" => {:patient, :marker},
    "EXAMINADOR" => {:examiner, :marker},
    "EXAMINADOR:EXAME" => {:examiner, :exam_marker}
  }
  @companion_markers Map.put(@markers, "ACOMPANHANTE", {:companion, :marker})

  # The longest prefix that may still be an unclosed marker; past it, an
  # opening bracket is text.
  @max_marker_bytes 24

  @type addressee :: :patient | :companion | :examiner
  @type source :: :marker | :exam_marker | :missing_marker
  @type opts :: [companion: boolean()]

  @doc """
  Reads the marker of a whole reply: `{addressee, source, text}` where `text`
  is the reply without the marker (the whole reply when it has none).
  """
  @spec split(String.t(), opts()) :: {addressee(), source(), String.t()}
  def split(text, opts \\ []) when is_binary(text) do
    case prefix(text, opts) do
      {:decided, addressee, source, rest} -> {addressee, source, rest}
      :undecided -> {:patient, :missing_marker, text}
    end
  end

  @doc """
  Reads the marker from the start of a reply still being generated:
  `:undecided` while the marker may still be arriving, else
  `{:decided, addressee, source, rest}` with the text after the marker.
  """
  @spec prefix(String.t(), opts()) ::
          :undecided | {:decided, addressee(), source(), String.t()}
  def prefix(text, opts \\ []) when is_binary(text) do
    trimmed = String.trim_leading(text)

    cond do
      trimmed == "" -> :undecided
      not String.starts_with?(trimmed, "[") -> {:decided, :patient, :missing_marker, text}
      true -> bracket_prefix(text, trimmed, markers(opts))
    end
  end

  defp markers(opts),
    do: if(Keyword.get(opts, :companion, false), do: @companion_markers, else: @markers)

  defp bracket_prefix(text, "[" <> after_bracket = trimmed, markers) do
    case String.split(after_bracket, "]", parts: 2) do
      [tag, rest] ->
        case Map.fetch(markers, normalize_tag(tag)) do
          {:ok, {addressee, source}} -> {:decided, addressee, source, String.trim_leading(rest)}
          :error -> {:decided, :patient, :missing_marker, text}
        end

      [_unclosed] ->
        if byte_size(trimmed) > @max_marker_bytes,
          do: {:decided, :patient, :missing_marker, text},
          else: :undecided
    end
  end

  # Case and spaces inside the brackets, or around the `:` of a sub-marker,
  # do not matter.
  defp normalize_tag(tag) do
    tag
    |> String.split(":")
    |> Enum.map_join(":", &(&1 |> String.trim() |> String.upcase()))
  end

  @doc """
  Wraps the `on_text` callback of a streamed generation (#271) so the marker
  is decided before any text is handed on.

  Returns `{filter, finish}`. `filter` takes each generated piece; it holds the
  pieces back until the marker is decided, then calls `on_decision` once with
  `(addressee, source)`, and only after it hands the text that follows the
  marker to `on_text`. An examiner reply hands nothing on; a patient or
  companion reply hands its text on. `opts` are those of `prefix/2`. `finish` (call it
  when the generation ends) decides a reply that ended before its marker did
  as patient-addressed, hands on what was held back, and returns the
  addressee. Both must run in the process that generates: the state lives in
  its process dictionary.
  """
  @spec stream((String.t() -> any()), (addressee(), source() -> any()), opts()) ::
          {(String.t() -> :ok), (-> addressee())}
  def stream(on_text, on_decision, opts \\ [])
      when is_function(on_text, 1) and is_function(on_decision, 2) do
    key = {__MODULE__, make_ref()}
    Process.put(key, {:pending, ""})

    filter = fn piece when is_binary(piece) ->
      Process.put(key, take(Process.get(key), piece, on_text, on_decision, opts))
      :ok
    end

    finish = fn -> finish(Process.delete(key), on_text, on_decision) end

    {filter, finish}
  end

  defp finish({:pending, held}, on_text, on_decision) do
    on_decision.(:patient, :missing_marker)
    if held != "", do: on_text.(held)
    :patient
  end

  defp finish({:decided, addressee}, _on_text, _on_decision), do: addressee

  defp take({:pending, held}, piece, on_text, on_decision, opts) do
    case prefix(held <> piece, opts) do
      :undecided ->
        {:pending, held <> piece}

      {:decided, addressee, source, rest} ->
        on_decision.(addressee, source)
        if addressee != :examiner and rest != "", do: on_text.(rest)
        {:decided, addressee}
    end
  end

  defp take({:decided, :examiner} = state, _piece, _on_text, _on_decision, _opts), do: state

  defp take({:decided, _speaker} = state, piece, on_text, _on_decision, _opts) do
    on_text.(piece)
    state
  end
end
