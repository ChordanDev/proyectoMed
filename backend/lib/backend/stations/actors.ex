defmodule Backend.Stations.Actors do
  @moduledoc """
  The actors of a Station Package (issue #341): the patient and, in some
  stations, one companion. The case format (#330) declares them in the
  package's `actors`, each with its profile, voice key and the ids of its facts
  and mandatory questions.

  A package without a companion (every package before #341, and every JSON
  package) is a single-actor station: every function here then leaves it as it
  is, so its prompt, markers, verification and events are unchanged.

  A speaker is the actor a reply comes from: `:patient` or `:companion`.
  """

  @type speaker :: :patient | :companion

  @doc "The package's companion actor, or `nil` for a single-actor station."
  @spec companion(map()) :: map() | nil
  def companion(package), do: find(package, "companion")

  @doc "The package's patient actor, or `nil` when the package declares no actors."
  @spec patient(map()) :: map() | nil
  def patient(package), do: find(package, "patient")

  @doc "Whether the station has a companion besides the patient."
  @spec companion?(map()) :: boolean()
  def companion?(package), do: companion(package) != nil

  @doc "The `Backend.Stations.StationAI.Addressee` options for the package's markers."
  @spec addressee_opts(map()) :: keyword()
  def addressee_opts(package), do: [companion: companion?(package)]

  @doc """
  The revealable facts and mandatory questions of `actor`, in package order:
  the facts whose id the actor owns (`fact_ids` and `mandatory_question_ids`).
  """
  @spec facts(map(), map() | nil) :: [map()]
  def facts(package, %{} = actor) do
    ids = MapSet.new(List.wrap(actor["fact_ids"]) ++ List.wrap(actor["mandatory_question_ids"]))
    Enum.filter(package["revealable_facts"] || [], &(is_map(&1) and &1["id"] in ids))
  end

  def facts(_package, nil), do: []

  @doc """
  The package as one speaker sees it, for checking that speaker's reply: in a
  station with a companion, `revealable_facts` keeps only the speaker's facts,
  and for the companion `patient_profile` is the companion's own profile. A
  single-actor package is returned unchanged.
  """
  @spec speaker_package(map(), speaker()) :: map()
  def speaker_package(package, speaker) do
    case {companion(package), speaker} do
      {nil, _speaker} ->
        package

      {companion, :companion} ->
        package
        |> Map.put("patient_profile", profile(companion))
        |> Map.put("revealable_facts", facts(package, companion))

      {_companion, :patient} ->
        Map.put(package, "revealable_facts", facts(package, patient(package)))
    end
  end

  @doc """
  The voice key (`voz=`) of the speaker in a station with a companion, else `nil`.
  """
  @spec voice(map(), speaker()) :: String.t() | nil
  def voice(package, speaker) do
    if companion?(package), do: actor(package, speaker)["voice"]
  end

  @doc "The actor of `speaker`, or `nil`."
  @spec actor(map(), speaker()) :: map() | nil
  def actor(package, :patient), do: patient(package)
  def actor(package, :companion), do: companion(package)

  # The companion's profile in the shape of `patient_profile`: it has no
  # `[CONTEXTO]`, so its context is its name.
  defp profile(actor) do
    %{
      "persona" => actor["persona"],
      "age" => actor["age"],
      "tone" => actor["tone"],
      "presenting_context" => actor["presenting_context"] || actor["name"]
    }
  end

  defp find(package, role) do
    case package do
      %{"actors" => actors} when is_list(actors) ->
        Enum.find(actors, &(is_map(&1) and &1["role"] == role))

      _other ->
        nil
    end
  end
end
