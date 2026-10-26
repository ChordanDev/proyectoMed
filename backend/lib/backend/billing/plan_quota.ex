defmodule Backend.Billing.PlanQuota do
  @moduledoc """
  The daily simulation quota of a RevenueCat product (#340): how many graded
  sessions a learner on `product_id` may play per day. Stored in the database,
  so it changes without a deploy.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "billing_plan_quotas" do
    field :product_id, :string
    field :daily_quota, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(quota, attrs) do
    quota
    |> cast(attrs, [:product_id, :daily_quota])
    |> validate_required([:product_id, :daily_quota])
    |> validate_number(:daily_quota, greater_than_or_equal_to: 0)
    |> unique_constraint(:product_id)
    |> check_constraint(:daily_quota, name: :daily_quota_non_negative)
  end
end
