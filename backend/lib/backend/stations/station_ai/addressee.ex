defmodule Backend.Stations.StationAI.Addressee do
  @moduledoc """
  The addressee marker the patient generator starts every reply with (issue
  #309, `docs/design/turn-addressee.md`): `[PACIENTE]` when the learner talks to
  the patient, `[EXAMINADOR]` when the learner talks to the examiner (nothing
  else follows it).

  The marker is read in code from the first characters of the reply and is
  never part of the text handed on: nothing of it is verified, spoken, shown or
  stored. It is read without regard to case or spaces inside the brackets. A
  reply that does not start with a known marker is patient-addressed with
  source `:missing_marker` and keeps its whole text, so an unknown bracket such
  as a stage direction is not lost.
  """

  @markers %{"PACIENTE" => :patient, "EXAMINADOR" => :examiner}

  # The longest prefix that may still be an unclosed marker; past it, an
  # opening bracket is text.
  @max_marker_bytes 24

  @type addressee :: :patient | :examiner
  @type source :: :marker | :missing_marker

  @doc """
  Reads the marker of a whole reply: `{addressee, source, text}` where `text`
  is the reply without the marker (the whole reply when it has none).
  """
  @spec split(String.t()) :: {addressee(), source(), String.t()}
  def split(text) when is_binary(text) do
    case prefix(text) do
      {:decided, addressee, source, rest} -> {addressee, source, rest}
      :undecided -> {:patient, :missing_marker, text}
    end
  end

  @doc """
  Reads the marker from the start of a reply still being generated:
  `:undecided` while the marker may still be arriving, else
  `{:decided, addressee, source, rest}` with the text after the marker.
  """
  @spec prefix(String.t()) :: :undecided | {:decided, addressee(), source(), String.t()}
  def prefix(text) when is_binary(text) do
    trimmed = String.trim_leading(text)

    cond do
      trimmed == "" -> :undecided
      not String.starts_with?(trimmed, "[") -> {:decided, :patient, :missing_marker, text}
      true -> bracket_prefix(text, trimmed)
    end
  end

  defp bracket_prefix(text, "[" <> after_bracket = trimmed) do
    case String.split(after_bracket, "]", parts: 2) do
      [tag, rest] ->
        case Map.fetch(@markers, tag |> String.trim() |> String.upcase()) do
          {:ok, addressee} -> {:decided, addressee, :marker, String.trim_leading(rest)}
          :error -> {:decided, :patient, :missing_marker, text}
        end

      [_unclosed] ->
        if byte_size(trimmed) > @max_marker_bytes,
          do: {:decided, :patient, :missing_marker, text},
          else: :undecided
    end
  end

  @doc """
  Wraps the `on_text` callback of a streamed generation (#271) so the marker
  is decided before any text is handed on.

  Returns `{filter, finish}`. `filter` takes each generated piece; it holds the
  pieces back until the marker is decided, then calls `on_decision` once with
  `(addressee, source)`, and only after it hands the text that follows the
  marker to `on_text`. An examiner reply hands nothing on. `finish` (call it
  when the generation ends) decides a reply that ended before its marker did
  as patient-addressed, hands on what was held back, and returns the
  addressee. Both must run in the process that generates: the state lives in
  its process dictionary.
  """
  @spec stream((String.t() -> any()), (addressee(), source() -> any())) ::
          {(String.t() -> :ok), (-> addressee())}
  def stream(on_text, on_decision) when is_function(on_text, 1) and is_function(on_decision, 2) do
    key = {__MODULE__, make_ref()}
    Process.put(key, {:pending, ""})

    filter = fn piece when is_binary(piece) ->
      Process.put(key, take(Process.get(key), piece, on_text, on_decision))
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

  defp take({:pending, held}, piece, on_text, on_decision) do
    case prefix(held <> piece) do
      :undecided ->
        {:pending, held <> piece}

      {:decided, addressee, source, rest} ->
        on_decision.(addressee, source)
        if addressee == :patient and rest != "", do: on_text.(rest)
        {:decided, addressee}
    end
  end

  defp take({:decided, :patient} = state, piece, on_text, _on_decision) do
    on_text.(piece)
    state
  end

  defp take({:decided, :examiner} = state, _piece, _on_text, _on_decision), do: state
end
