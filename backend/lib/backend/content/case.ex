defmodule Backend.Content.Case do
  @moduledoc """
  A generated case (issue #331): its human `number`, `area`, `theme`, tagged
  Markdown and review `status`. n8n inserts the rows (see
  `docs/case-format/README.md`); Postgres assigns `number` and the timestamps.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @statuses [:pending, :approved, :disapproved]

  schema "cases" do
    field :number, :integer, read_after_writes: true
    field :area, :string
    field :theme, :string
    field :markdown, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :lock_version, :integer, default: 1
    field :approved_by_id, :id
    field :approved_by_email, :string
    field :approved_at, :utc_datetime

    has_many :revisions, Backend.Content.CaseRevision
    has_many :station_versions, Backend.Content.StationVersion

    timestamps(type: :utc_datetime)
  end

  @doc "The review statuses, in workflow order."
  @spec statuses() :: [atom()]
  def statuses, do: @statuses

  @doc """
  Approving a case (issue #333): records the approver, timestamp, and sets status to :approved.
  Optimistic locking increments lock_version.
  """
  @spec approve_changeset(t(), map()) :: Ecto.Changeset.t()
  def approve_changeset(kase, attrs) do
    kase
    |> cast(attrs, [:status, :area, :theme, :approved_by_id, :approved_by_email, :approved_at])
    |> validate_required([:status, :area, :theme, :approved_by_email, :approved_at])
    |> optimistic_lock(:lock_version)
  end

  @doc """
  Disapproving a case (issue #333): sets status to :disapproved with optimistic locking.
  """
  @spec disapprove_changeset(t()) :: Ecto.Changeset.t()
  def disapprove_changeset(kase) do
    kase
    |> change(%{status: :disapproved})
    |> optimistic_lock(:lock_version)
  end

  @doc """
  An admin edit of the Markdown (issue #332): Markdown must not be blank, and
  the update only applies over the `lock_version` the case was loaded with
  (optimistic lock), incrementing it.
  """
  @spec markdown_changeset(t(), String.t()) :: Ecto.Changeset.t()
  def markdown_changeset(kase, markdown) do
    kase
    |> cast(%{markdown: markdown}, [:markdown])
    |> validate_required([:markdown])
    |> optimistic_lock(:lock_version)
  end
end
