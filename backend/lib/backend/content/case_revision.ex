defmodule Backend.Content.CaseRevision do
  @moduledoc """
  A replaced version of a case's Markdown (issue #332). Each admin save keeps
  the Markdown it replaces, the `lock_version` that Markdown had, and the
  admin whose save replaced it (`editor_id`, plus an `editor_email` snapshot
  that survives account deletion). Revisions are never updated.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "case_revisions" do
    field :markdown, :string
    field :lock_version, :integer
    field :editor_id, :id
    field :editor_email, :string
    belongs_to :case, Backend.Content.Case

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
