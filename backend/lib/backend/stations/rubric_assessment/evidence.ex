defmodule Backend.Stations.RubricAssessment.Evidence do
  @moduledoc """
  The evidence pool of a completed session and the fail-closed validation of
  the evidence a rubric decision cites (issue #128, ADR-012).

  The pool is shared by every rubric question of an attempt. It holds every
  transcript turn and every Impressos request event, in chronological order,
  under identifiers derived from the immutable session:

    * `"turn-N"`, with `N` the 1-based position in the session `messages`;
    * `"impresso-<request_id>"` for an `impresso_requests` event.

  Each item is labelled with its role, channel and provenance. A turn's channel
  is its modality and its provenance is `:transcript`. An event is attributed
  to the learner, its channel is `:impressos`, and its provenance is
  `:impressos` only under the rule the legacy evaluator already applies: the
  event was recorded for the package's version and every impresso it released
  is authored in the package. Any other event stays in the pool as
  `:unverified`, so that citing it is rejected with a reason instead of
  looking like an identifier that never existed.

  Validation is stateless and consumes nothing: the same learner turn may back
  any number of criteria. It only ever looks identifiers up. It never
  substitutes, guesses, fuzzy-matches or aligns evidence by text.

  The module is pure: no processes, no I/O and no decision provider.
  """

  @learner_roles [:learner, :student, "learner", "student"]
  @impresso_categories ~w(physical_exam laboratory imaging report)

  @typedoc "Whether an item is a transcript turn or an Impressos request event."
  @type kind :: :turn | :impresso_event

  @typedoc """
  How the evidence entered the session: `:transcript` for a turn, `:impressos`
  for a verified request event, `:unverified` for a request event that fails
  the version or authorship rule.
  """
  @type provenance :: :transcript | :impressos | :unverified

  @typedoc """
  One piece of evidence. `:role` and, for turns, `:channel` are kept as stored
  in the session. `:released_ids` and `:categories` are empty for turns; for an
  event, `:categories` holds the distinct authored categories of the impressos
  it released. `:at` is `nil` when the session carries no `DateTime`.
  """
  @type item :: %{
          id: String.t(),
          kind: kind(),
          role: term(),
          channel: term(),
          provenance: provenance(),
          text: String.t(),
          at: DateTime.t() | nil,
          released_ids: [term()],
          categories: [String.t()]
        }

  @typedoc "The ordered evidence pool of one session."
  @type pool :: [item()]

  @typedoc """
  What a criterion's `"modality_requirement"` demands of its evidence:

    * `:any` - a learner transcript turn or a verified impresso event;
    * `:verbal` - a learner transcript turn, typed or spoken;
    * `:impressos` - a verified impresso event;
    * `{:impressos_category, category}` - a verified impresso event that
      released an impresso of that category;
    * `{:unknown_modality, authored}` - a modality this module does not know;
      nothing satisfies it.
  """
  @type requirement ::
          :any
          | :verbal
          | :impressos
          | {:impressos_category, String.t()}
          | {:unknown_modality, term()}

  @typedoc "Why a station cannot provide a required modality."
  @type providability_error :: :unknown_modality | :no_authored_impresso

  @typedoc "Why a cited evidence identifier is rejected."
  @type rejection ::
          :nonexistent_evidence_id | :wrong_role | :wrong_channel | :wrong_provenance

  @typedoc "The minimized evidence item sent to the decision provider."
  @type jev_item :: %{id: String.t(), role: String.t(), text: String.t()}

  @doc """
  Builds the evidence pool of a session against its Station Package.

  `session` is the session map (atom or string keys); a missing
  `impresso_requests` key means no events. `package` is the decoded v2 package
  (string keys).

  Items are ordered by `at`. On an exact tie turns keep message order, events
  keep their `order`, and turns come before events. Items without a `DateTime`
  come last under the same tie rules. Never raises on a map.
  """
  @spec build(map(), map()) :: pool()
  def build(session, package) when is_map(session) and is_map(package) do
    authored = authored_categories(package)
    version = Map.get(package, "version")

    turns = session |> list_field(:messages) |> indexed(&turn/2)

    events =
      session |> list_field(:impresso_requests) |> indexed(&event(&1, &2, version, authored))

    (turns ++ events)
    |> Enum.sort_by(fn {sort_key, _item} -> sort_key end)
    |> Enum.map(fn {_sort_key, item} -> item end)
  end

  @doc "Returns every evidence identifier of the pool, in pool order."
  @spec ids(pool()) :: [String.t()]
  def ids(pool) when is_list(pool), do: Enum.map(pool, & &1.id)

  @doc """
  Returns the pool minimized to the `id`, `role` and `text` of each item, in
  pool order, as the `evidence_pool` of a `Backend.Stations.JevDecision` rubric
  request. The role is rendered as a string.
  """
  @spec jev_view(pool()) :: [jev_item()]
  def jev_view(pool) when is_list(pool) do
    Enum.map(pool, &%{id: &1.id, role: to_string(&1.role), text: &1.text})
  end

  @doc """
  Maps the `"modality_requirement"` of a v2 package criterion (string keys) to
  an evidence requirement. An absent or `nil` value accepts any learner
  evidence; a value that is neither `"verbal"`, `"impressos"` nor an Impressos
  category is an unknown modality.
  """
  @spec requirement(map()) :: requirement()
  def requirement(criterion) when is_map(criterion) do
    case Map.get(criterion, "modality_requirement") do
      nil -> :any
      "verbal" -> :verbal
      "impressos" -> :impressos
      category when category in @impresso_categories -> {:impressos_category, category}
      other -> {:unknown_modality, other}
    end
  end

  @doc """
  Says whether the station described by `package` can provide the modality a
  requirement names at all.

  Transcript requirements are always providable. An Impressos requirement is
  providable only when the package authors a matching impresso. An unknown
  modality is never providable.
  """
  @spec providability(requirement(), map()) :: :ok | {:error, providability_error()}
  def providability(requirement, package) when is_map(package) do
    providable(requirement, authored_categories(package))
  end

  @doc """
  Validates the evidence identifiers cited for one criterion.

  Returns the cited items in pool order, without duplicates, or the first
  offending identifier in citation order with its reason:

    * `:nonexistent_evidence_id` - not an identifier of the pool, including any
      non-binary value;
    * `:wrong_role` - not authored by the learner, such as a patient turn;
    * `:wrong_provenance` - an unverified impresso event;
    * `:wrong_channel` - learner evidence that does not satisfy the
      requirement, such as a turn cited for an Impressos criterion, an event of
      another category, or an event that released nothing.

  An empty list is valid. The pool is never modified.
  """
  @spec validate(pool(), term(), requirement()) ::
          {:ok, [item()]} | {:error, {rejection(), term()}}
  def validate(pool, evidence_ids, requirement) when is_list(pool) and is_list(evidence_ids) do
    by_id = Map.new(pool, &{&1.id, &1})

    case Enum.find_value(evidence_ids, &rejection(by_id, &1, requirement)) do
      nil -> {:ok, Enum.filter(pool, &(&1.id in evidence_ids))}
      rejection -> {:error, rejection}
    end
  end

  def validate(pool, evidence_ids, _requirement) when is_list(pool) do
    {:error, {:nonexistent_evidence_id, evidence_ids}}
  end

  defp rejection(by_id, id, requirement) do
    case Map.fetch(by_id, id) do
      {:ok, item} -> item |> reject_reason(requirement) |> tag(id)
      :error -> {:nonexistent_evidence_id, id}
    end
  end

  defp tag(nil, _id), do: nil
  defp tag(reason, id), do: {reason, id}

  defp reject_reason(%{role: role}, _requirement) when role not in @learner_roles,
    do: :wrong_role

  defp reject_reason(%{provenance: :unverified}, _requirement), do: :wrong_provenance

  defp reject_reason(item, requirement) do
    if satisfies?(item, requirement), do: nil, else: :wrong_channel
  end

  # An event that released nothing (an unavailable or repeated request) never
  # counts as evidence, as in the legacy evaluator.
  defp satisfies?(%{kind: :turn}, requirement), do: requirement in [:any, :verbal]
  defp satisfies?(%{released_ids: []}, _requirement), do: false
  defp satisfies?(_event, requirement) when requirement in [:any, :impressos], do: true
  defp satisfies?(event, {:impressos_category, category}), do: category in event.categories
  defp satisfies?(_event, _requirement), do: false

  defp providable(requirement, _authored) when requirement in [:any, :verbal], do: :ok

  defp providable({:unknown_modality, _authored_value}, _authored),
    do: {:error, :unknown_modality}

  defp providable(:impressos, authored) do
    authored_or_error(map_size(authored) > 0)
  end

  defp providable({:impressos_category, category}, authored) do
    authored_or_error(category in Map.values(authored))
  end

  defp providable(_requirement, _authored), do: {:error, :unknown_modality}

  defp authored_or_error(true), do: :ok
  defp authored_or_error(false), do: {:error, :no_authored_impresso}

  defp turn(message, index) do
    at = timestamp(message)

    item = %{
      id: "turn-#{index}",
      kind: :turn,
      role: field(message, :role),
      channel: field(message, :modality),
      provenance: :transcript,
      text: text(message),
      at: at,
      released_ids: [],
      categories: []
    }

    {{sort_time(at), 0, index, index}, item}
  end

  defp event(event, index, version, authored) do
    at = timestamp(event)
    request_id = field(event, :request_id)
    released_ids = released_ids(event)

    item = %{
      id: "impresso-#{event_reference(request_id, index)}",
      kind: :impresso_event,
      role: :learner,
      channel: :impressos,
      provenance: event_provenance(event, request_id, released_ids, version, authored),
      text: text(event),
      at: at,
      released_ids: released_ids,
      categories: released_ids |> Enum.flat_map(&List.wrap(authored[&1])) |> Enum.uniq()
    }

    {{sort_time(at), 1, event_order(event, index), index}, item}
  end

  # An event without a usable request id is addressed by its position and can
  # never be verified.
  defp event_reference(request_id, _index) when is_binary(request_id), do: request_id
  defp event_reference(_request_id, index), do: index

  defp event_provenance(event, request_id, released_ids, version, authored) do
    verified? =
      is_binary(request_id) and is_binary(version) and
        field(event, :station_version) == version and
        Enum.all?(released_ids, &is_map_key(authored, &1))

    if verified?, do: :impressos, else: :unverified
  end

  defp event_order(event, index) do
    case field(event, :order) do
      order when is_integer(order) -> order
      _missing -> index
    end
  end

  # Integers sort before atoms in the Erlang term order, so items without a
  # timestamp come after every timed item.
  defp sort_time(%DateTime{} = at), do: DateTime.to_unix(at, :microsecond)
  defp sort_time(nil), do: :untimed

  defp timestamp(entry) do
    case field(entry, :at) do
      %DateTime{} = at -> at
      _missing -> nil
    end
  end

  defp text(entry) do
    case field(entry, :text) do
      text when is_binary(text) -> text
      _missing -> ""
    end
  end

  defp released_ids(event) do
    case field(event, :released_ids) do
      ids when is_list(ids) -> ids
      _missing -> []
    end
  end

  # Maps each authored impresso id to its category.
  defp authored_categories(package) do
    for %{"id" => id} = impresso <- List.wrap(Map.get(package, "impressos")),
        is_binary(id),
        into: %{} do
      {id, Map.get(impresso, "category")}
    end
  end

  defp indexed(entries, build) do
    entries
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, index} -> build.(entry, index) end)
  end

  defp list_field(session, key) do
    case field(session, key) do
      entries when is_list(entries) -> entries
      _missing -> []
    end
  end

  defp field(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end

  defp field(_not_a_map, _key), do: nil
end
