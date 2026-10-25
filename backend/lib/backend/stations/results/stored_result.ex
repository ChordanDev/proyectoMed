defmodule Backend.Stations.Results.StoredResult do
  @moduledoc """
  One stored Educational Result of a learner (#338, ADR-014 #346): the
  station it was played on, when the session finished, and `result`, the v2
  Educational Result served at the end of the session.
  """

  use Ecto.Schema

  schema "educational_results" do
    belongs_to :user, Backend.Accounts.User
    belongs_to :station_version, Backend.Content.StationVersion
    field :session_id, :string
    field :case_number, :integer
    field :version_number, :integer
    field :station_slug, :string
    field :area, :string
    field :theme, :string
    field :display_title, :string
    field :finished_at, :utc_datetime_usec
    field :result, :map

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
