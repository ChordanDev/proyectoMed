defmodule Backend.Repo.Migrations.CreateBillingPlanQuotas do
  use Ecto.Migration

  # Daily simulation quotas per plan (#340). RevenueCat webhooks carry no plan
  # metadata (research A9), so the quota lives here, keyed by RevenueCat
  # `product_id`, and changes without a deploy. The two plans on sale are
  # seeded; a product without a row gets `:default_daily_quota` from config.
  def up do
    create table(:billing_plan_quotas) do
      add :product_id, :string, null: false
      add :daily_quota, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:billing_plan_quotas, [:product_id])
    create constraint(:billing_plan_quotas, :daily_quota_non_negative, check: "daily_quota >= 0")

    execute """
    INSERT INTO billing_plan_quotas (product_id, daily_quota, inserted_at, updated_at)
    VALUES ('revalida_mensal_cartao', 10, now(), now()),
           ('revalida_mensal_pix', 10, now(), now())
    """
  end

  def down do
    drop table(:billing_plan_quotas)
  end
end
