defmodule Backend.Content.Case do
  @moduledoc """
  A generated case (issue #331): its human `number`, `area`, `theme`, tagged
  Markdown and review `status`. n8n inserts the rows (see
  `docs/case-format/README.md`); Postgres assigns `number` and the timestamps.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  @statuses [:pending, :approved, :disapproved]

  schema "cases" do
    field :number, :integer, read_after_writes: true
    field :area, :string
    field :theme, :string
    field :markdown, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending

    timestamps(type: :utc_datetime)
  end

  @doc "The review statuses, in workflow order."
  @spec statuses() :: [atom()]
  def statuses, do: @statuses
end
