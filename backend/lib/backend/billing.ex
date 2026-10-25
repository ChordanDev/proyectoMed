defmodule Backend.Billing do
  @moduledoc """
  Billing context (ADR-007 #92 amendment, #339): the RevenueCat webhook, the
  simulator entitlement and the plans a learner can buy.

  RevenueCat runs checkout through a Web Purchase Link with the Stripe Billing
  integration, so learners pay by card (renews automatically) or by Pix
  (Brazil-domiciled accounts only get one-time Pix: each period is paid
  manually, and the entitlement lapses at the due date when unpaid). Every
  learner is identified to RevenueCat by a random UUIDv4 `app_user_id`, never
  the email.

  Plans live here, keyed by RevenueCat `product_id` (research A9): the webhook
  carries no plan metadata or payment method. The daily simulation quota of a
  product lives in the `billing_plan_quotas` table (#340), so it changes
  without a deploy; a product without a row gets `:default_daily_quota`.

  Configuration (`config :backend, Backend.Billing`): `:entitlement_id`,
  `:plans`, `:default_daily_quota`, `:purchase_links` (`%{card: url, pix: url}`, the Web Purchase
  Link without the app_user_id), `:webhook_authorization`, `:webhook_secret`,
  `:signature_tolerance_s`, `:accept_sandbox` and `:pix_reminder_days`. See
  `docs/operations/revenuecat.md`.

  May call `Backend.Accounts` only.
  """

  import Ecto.Query

  alias Backend.Accounts.User
  alias Backend.Billing.{PlanQuota, Subscription, WebhookEvents, WebhookSignature}
  alias Backend.Repo

  @type plan :: %{product_id: String.t(), name: String.t(), payment: :card | :pix}
  @type status :: %{
          state: :none | :active | :cancelled | :expired,
          product_id: String.t() | nil,
          plan: plan() | nil,
          expires_at: DateTime.t() | nil,
          auto_renews?: boolean(),
          renewal_reminder?: boolean()
        }

  @doc """
  The learner's RevenueCat app_user_id: a random UUIDv4 created on first use
  and stable afterwards.
  """
  @spec app_user_id(User.t()) :: String.t()
  def app_user_id(%User{id: user_id}), do: ensure_subscription(user_id).app_user_id

  defp ensure_subscription(user_id) do
    Repo.insert!(%Subscription{user_id: user_id, app_user_id: Ecto.UUID.generate()},
      on_conflict: :nothing,
      conflict_target: :user_id
    )

    Repo.get_by!(Subscription, user_id: user_id)
  end

  @doc """
  Whether the learner `user_id` has the simulator entitlement now: the last
  applied event granted or cancelled it and its expiration is in the future.
  """
  @spec entitled?(integer()) :: boolean()
  def entitled?(user_id) when is_integer(user_id) do
    now = DateTime.utc_now()

    Repo.exists?(
      from s in Subscription,
        where: s.user_id == ^user_id and s.status in [:active, :cancelled] and s.expires_at > ^now
    )
  end

  @doc """
  The learner's subscription as the account page shows it. `state` is
  `:expired` once the expiration has passed, even without an `EXPIRATION`
  event. `renewal_reminder?` is true for a Pix plan due within
  `:pix_reminder_days`.
  """
  @spec subscription_status(User.t()) :: status()
  def subscription_status(%User{id: user_id}) do
    case Repo.get_by(Subscription, user_id: user_id) do
      nil -> status(%Subscription{})
      sub -> status(sub)
    end
  end

  defp status(%Subscription{} = sub) do
    now = DateTime.utc_now()
    plan = plan(sub.product_id)

    lapsed? = is_nil(sub.expires_at) or DateTime.compare(sub.expires_at, now) != :gt
    state = if sub.status in [:active, :cancelled] and lapsed?, do: :expired, else: sub.status

    pix? = match?(%{payment: :pix}, plan)

    %{
      state: state,
      product_id: sub.product_id,
      plan: plan,
      expires_at: sub.expires_at,
      auto_renews?: state == :active and not pix?,
      renewal_reminder?:
        state == :active and pix? and
          DateTime.diff(sub.expires_at, now, :second) <= config(:pix_reminder_days) * 86_400
    }
  end

  @doc "The plans on sale, as configured."
  @spec plans() :: [plan()]
  def plans, do: config(:plans)

  defp plan(nil), do: nil
  defp plan(product_id), do: Enum.find(plans(), &(&1.product_id == product_id))

  # America/Sao_Paulo has kept UTC-03:00 all year since daylight saving time
  # ended in 2019, so the quota day is a fixed offset (#340).
  @quota_day_utc_offset_s -3 * 3_600

  @doc """
  The daily simulation quota of the learner `user_id` (#340): the
  `billing_plan_quotas` row of the product of their subscription, or
  `:default_daily_quota` for a product without a row or a learner without a
  product.
  """
  @spec daily_quota(integer()) :: non_neg_integer()
  def daily_quota(user_id) when is_integer(user_id) do
    query =
      from s in Subscription,
        join: q in PlanQuota,
        on: q.product_id == s.product_id,
        where: s.user_id == ^user_id,
        select: q.daily_quota

    Repo.one(query) || config(:default_daily_quota)
  end

  @doc """
  Sets the daily simulation quota of the RevenueCat `product_id`, adding the
  product when it has no quota yet. Takes effect on the next session start.
  """
  @spec set_daily_quota(String.t(), non_neg_integer()) ::
          {:ok, PlanQuota.t()} | {:error, Ecto.Changeset.t()}
  def set_daily_quota(product_id, daily_quota) do
    %PlanQuota{}
    |> PlanQuota.changeset(%{product_id: product_id, daily_quota: daily_quota})
    |> Repo.insert(
      on_conflict: {:replace, [:daily_quota, :updated_at]},
      conflict_target: :product_id,
      returning: true
    )
  end

  @doc """
  The quota day containing `now` (#340): from local midnight in
  America/Sao_Paulo (03:00 UTC) to the next one, when the quota resets.
  """
  @spec quota_day(DateTime.t()) :: %{starts_at: DateTime.t(), resets_at: DateTime.t()}
  def quota_day(%DateTime{} = now \\ DateTime.utc_now()) do
    local_date = now |> DateTime.add(@quota_day_utc_offset_s, :second) |> DateTime.to_date()

    starts_at =
      local_date
      |> DateTime.new!(~T[00:00:00.000000], "Etc/UTC")
      |> DateTime.add(-@quota_day_utc_offset_s, :second)

    %{starts_at: starts_at, resets_at: DateTime.add(starts_at, 1, :day)}
  end

  @doc """
  The Web Purchase Link of `plan` for `user`:
  `<purchase link>/<app_user_id>?email=<email>`, or `nil` when the plan's
  link is not configured.
  """
  @spec purchase_url(plan(), User.t()) :: String.t() | nil
  def purchase_url(%{payment: payment}, %User{} = user) do
    case Map.get(config(:purchase_links), payment) do
      base when is_binary(base) and base != "" ->
        String.trim_trailing(base, "/") <>
          "/" <> URI.encode(app_user_id(user)) <> "?" <> URI.encode_query(%{email: user.email})

      _missing ->
        nil
    end
  end

  @doc """
  Verifies a webhook request: the raw body, the `Authorization` header value
  and the `X-RevenueCat-Webhook-Signature` header value. Fails closed with
  `{:error, :not_configured}` when the secrets are unset.
  """
  @spec verify_webhook(binary(), String.t() | nil, String.t() | nil) ::
          :ok | {:error, :not_configured | :unauthorized | :invalid_signature}
  def verify_webhook(raw_body, authorization, signature) do
    WebhookSignature.verify(raw_body, authorization, signature,
      authorization: config(:webhook_authorization),
      secret: config(:webhook_secret),
      tolerance_s: config(:signature_tolerance_s)
    )
  end

  @doc """
  Applies a decoded webhook body (`%{"event" => event}`) atomically and
  idempotently. `:applied` changed the entitlement, `:ignored` was recorded
  without effect (a stale event, another entitlement, an unhandled type, a
  `TEST` or an unaccepted `SANDBOX` event), `:duplicate` was already
  processed. `{:error, :unknown_subscriber}` when no learner resolves, so the
  caller answers non-200 and RevenueCat retries.
  """
  @spec process_webhook_event(map()) ::
          {:ok, :applied | :ignored | :duplicate}
          | {:error, :invalid_event | :unknown_subscriber}
  def process_webhook_event(payload) when is_map(payload) do
    case WebhookEvents.process(payload,
           entitlement_id: config(:entitlement_id),
           accept_sandbox: config(:accept_sandbox)
         ) do
      {:ok, outcome} -> {:ok, outcome}
      {:error, reason} -> {:error, reason}
    end
  end

  defp config(key), do: Application.fetch_env!(:backend, __MODULE__) |> Keyword.fetch!(key)
end
