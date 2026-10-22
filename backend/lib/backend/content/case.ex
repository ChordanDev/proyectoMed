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

    timestamps(type: :utc_datetime)
  end

  @doc "The review statuses, in workflow order."
  @spec statuses() :: [atom()]
  def statuses, do: @statuses

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
