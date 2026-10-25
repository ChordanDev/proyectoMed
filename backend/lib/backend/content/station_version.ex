defmodule Backend.Content.StationVersion do
  @moduledoc """
  An immutable published version of a case (issue #333, spec #326).

  Created whenever an admin approves a case. It stores the full validated
  Station Package, the case Markdown at approval time, sequential version
  number for that case, and references to its case and revision (if edited).
  Published station versions are never updated.

  The approved text is `markdown` on this row. `case_revision_id` does not
  point to the approved text: a `CaseRevision` holds the Markdown that an admin
  save *replaced*, so `case_revision_id` references the latest revision at
  approval time (the edit history that led to this version), or `nil` when the
  case was never edited. `station_id` is the `[ESTAÇÃO]` slug; it may repeat
  across cases, so the catalog identity is the case number.
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
