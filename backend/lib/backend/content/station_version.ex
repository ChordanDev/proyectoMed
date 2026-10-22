defmodule Backend.Content.StationVersion do
  @moduledoc """
  An immutable published version of a case (issue #333, spec #326).

  Created whenever an admin approves a case. It stores the full validated
  Station Package, the case Markdown at approval time, sequential version
  number for that case, and references to its case and revision (if edited).
  Published station versions are never updated.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "station_versions" do
    field :version_number, :integer
    field :station_id, :string
    field :area, :string
    field :theme, :string
    field :markdown, :string
    field :package, :map
    field :approved_by_id, :id
    field :approved_by_email, :string
    field :approved_at, :utc_datetime

    belongs_to :case, Backend.Content.Case
    belongs_to :case_revision, Backend.Content.CaseRevision

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
