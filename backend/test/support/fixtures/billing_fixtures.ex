defmodule Backend.BillingFixtures do
  @moduledoc """
  RevenueCat webhook fixtures (#339): event payloads shaped like RevenueCat's
  webhook body, and the signed headers the webhook endpoint verifies. Nothing
  here calls RevenueCat; entitlements are seeded through the same public
  `Backend.Billing.process_webhook_event/1` the webhook uses.
  """

  alias Backend.Billing

  @day_ms 86_400_000

  def card_product_id, do: "revalida_mensal_cartao"
  def pix_product_id, do: "revalida_mensal_pix"
  def entitlement_id, do: "simulador"

  @doc "The webhook signing secret and `Authorization` value set in `config/test.exs`."
  def webhook_secret, do: Application.fetch_env!(:backend, Billing)[:webhook_secret]
  def webhook_authorization, do: Application.fetch_env!(:backend, Billing)[:webhook_authorization]

  def now_ms, do: System.system_time(:millisecond)

  @doc """
  A webhook body (`%{"api_version" => "1.0", "event" => event}`) for `type`
  and `app_user_id`. Options override event fields: `:id`, `:product_id`,
  `:event_timestamp_ms`, `:expiration_at_ms`, `:environment`, `:entitlement_ids`,
  `:original_app_user_id`, `:aliases`, `:store`, `:price`, and `:cancel_reason`
  or `:expiration_reason` (added only when given, as RevenueCat sends them only
  on `CANCELLATION` and `EXPIRATION`).
  """
  def webhook_payload(type, app_user_id, opts \\ []) do
    now = now_ms()

    event = %{
      "id" => Keyword.get(opts, :id, Ecto.UUID.generate()),
      "type" => type,
      "app_user_id" => app_user_id,
      "original_app_user_id" => Keyword.get(opts, :original_app_user_id, app_user_id),
      "aliases" => Keyword.get(opts, :aliases, [app_user_id]),
      "entitlement_ids" => Keyword.get(opts, :entitlement_ids, [entitlement_id()]),
      "product_id" => Keyword.get(opts, :product_id, card_product_id()),
      "event_timestamp_ms" => Keyword.get(opts, :event_timestamp_ms, now),
      "purchased_at_ms" => now,
      "expiration_at_ms" => Keyword.get(opts, :expiration_at_ms, now + 30 * @day_ms),
      "environment" => Keyword.get(opts, :environment, "PRODUCTION"),
      "store" => Keyword.get(opts, :store, "STRIPE"),
      "period_type" => "NORMAL",
      "currency" => "BRL",
      "price" => Keyword.get(opts, :price, 99.9)
    }

    event =
      opts
      |> Keyword.take([:cancel_reason, :expiration_reason])
      |> Enum.reduce(event, fn {key, value}, acc -> Map.put(acc, Atom.to_string(key), value) end)

    %{"api_version" => "1.0", "event" => event}
  end

  @doc """
  Gives `user` an active entitlement through an `INITIAL_PURCHASE` webhook
  event. Options as in `webhook_payload/3`.
  """
  def subscribe_user(user, opts \\ []) do
    app_user_id = Billing.app_user_id(user)

    {:ok, :applied} =
      Billing.process_webhook_event(webhook_payload("INITIAL_PURCHASE", app_user_id, opts))

    user
  end

  @doc """
  The `X-RevenueCat-Webhook-Signature` value for `raw_body` signed at the unix
  time `t` with `secret`.
  """
  def signature_header(raw_body, t \\ System.system_time(:second), secret \\ webhook_secret()) do
    hex = :crypto.mac(:hmac, :sha256, secret, "#{t}.#{raw_body}") |> Base.encode16(case: :lower)
    "t=#{t},v1=#{hex}"
  end
end
