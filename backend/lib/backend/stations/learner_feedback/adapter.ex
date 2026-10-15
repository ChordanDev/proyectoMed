defmodule Backend.Stations.LearnerFeedback.Adapter do
  @moduledoc """
  External provider seam that writes per-criterion learner feedback from an
  already graded rubric assessment (issue #215).

  The request carries the graded record only: never the conversation, only
  the learner evidence the assessment already cited. The adapter returns one
  text per criterion id; `Backend.Stations.LearnerFeedback` validates each
  text and falls back to the authored recommendation on any failure.
  """

  @typedoc "An authored level as sent to the provider."
  @type level :: %{label: String.t(), description: String.t()}

  @typedoc "One graded criterion as sent to the provider. Points are decimal strings."
  @type criterion :: %{
          id: String.t(),
          description: String.t(),
          level: level(),
          next_level: level() | nil,
          points: String.t(),
          max_points: String.t(),
          performed_actions: [String.t()],
          missing_actions: [String.t()],
          evidence: [String.t()]
        }

  @typedoc "One request for every criterion that needs feedback, in the package `language`."
  @type request :: %{language: String.t() | nil, criteria: [criterion(), ...]}

  @doc "Writes one feedback text per criterion id of the request."
  @callback write_feedback(request()) :: {:ok, %{String.t() => String.t()}} | {:error, term()}
end
