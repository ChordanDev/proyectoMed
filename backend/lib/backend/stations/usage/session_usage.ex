defmodule Backend.Stations.Usage.SessionUsage do
  @moduledoc """
  The usage row of one finished station session (issue #342), keyed by the
  session id: Claude tokens per model, Jev calls, the audio usage the voice
  worker reported, and the estimated USD cost per provider and in total.

  Content-free by construction (ADR-001, ADR-009): no user id, no transcript,
  no reply, no prompt; only the station identity, timestamps and counts.
  """

  use Ecto.Schema

  @primary_key {:session_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  @type t :: %__MODULE__{}

  schema "session_usages" do
    field :station_id, :string
    field :station_version, :string
    field :station_version_id, :integer
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :claude_usage, :map, default: %{}
    field :jev_calls, :integer, default: 0
    field :deepgram_audio_seconds, :float, default: 0.0
    field :elevenlabs_characters, :integer, default: 0
    field :livekit_participant_minutes, :float, default: 0.0
    field :cost_by_provider, :map, default: %{}
    field :unpriced_models, {:array, :string}, default: []
    field :estimated_cost_usd, :decimal

    timestamps()
  end
end
