defmodule Backend.BillingTest do
  @moduledoc """
  The Billing context (#339): RevenueCat webhook events grant, renew, cancel
  and expire the simulator entitlement of a learner, identified by a random
  UUIDv4 app_user_id; replays and stale events change nothing; the webhook
  signature and `Authorization` header are verified.
  """

  # Some tests swap the Billing application env: not async.
  use Backend.DataCase, async: false

  import Backend.AccountsFixtures
  import Backend.BillingFixtures

  alias Backend.Billing

  @day_ms 86_400_000

  setup do
    user = user_fixture()
    %{user: user, app_user_id: Billing.app_user_id(user)}
  end

  defp process(type, app_user_id, opts \\ []),
    do: Billing.process_webhook_event(webhook_payload(type, app_user_id, opts))

  defp expires_at(user), do: Billing.subscription_status(user).expires_at

  describe "app_user_id/1" do
    test "is a random UUIDv4, stable per user and never the email", %{user: user} = ctx do
      assert {:ok, _uuid} = Ecto.UUID.cast(ctx.app_user_id)
      assert String.at(ctx.app_user_id, 14) == "4"
      assert Billing.app_user_id(user) == ctx.app_user_id
      refute ctx.app_user_id =~ user.email
      refute Billing.app_user_id(user_fixture()) == ctx.app_user_id
    end
  end

  describe "process_webhook_event/1" do
    test "a learner without events has no entitlement", %{user: user} do
      refute Billing.entitled?(user.id)
      assert Billing.subscription_status(user).state == :none
    end

    test "INITIAL_PURCHASE activates the entitlement with plan and expiration",
         %{user: user} = ctx do
      expiration = now_ms() + 30 * @day_ms

      assert {:ok, :applied} =
               process("INITIAL_PURCHASE", ctx.app_user_id, expiration_at_ms: expiration)

      assert Billing.entitled?(user.id)
      status = Billing.subscription_status(user)
      assert status.state == :active
      assert status.product_id == card_product_id()
      assert status.plan.payment == :card
      assert status.auto_renews?
      assert DateTime.to_unix(status.expires_at, :millisecond) == expiration
    end

    test "RENEWAL extends the expiration", %{user: user} = ctx do
      t0 = now_ms()
      {:ok, :applied} = process("INITIAL_PURCHASE", ctx.app_user_id, event_timestamp_ms: t0)

      later = t0 + 60 * @day_ms

      assert {:ok, :applied} =
               process("RENEWAL", ctx.app_user_id,
                 event_timestamp_ms: t0 + 1,
                 expiration_at_ms: later
               )

      assert DateTime.to_unix(expires_at(user), :millisecond) == later
      assert Billing.entitled?(user.id)
    end

    test "CANCELLATION keeps access until the expiration and stops auto-renewal",
         %{user: user} = ctx do
      t0 = now_ms()
      {:ok, :applied} = process("INITIAL_PURCHASE", ctx.app_user_id, event_timestamp_ms: t0)

      assert {:ok, :applied} =
               process("CANCELLATION", ctx.app_user_id, event_timestamp_ms: t0 + 1)

      assert Billing.entitled?(user.id)
      status = Billing.subscription_status(user)
      assert status.state == :cancelled
      refute status.auto_renews?

      assert {:ok, :applied} =
               process("UNCANCELLATION", ctx.app_user_id, event_timestamp_ms: t0 + 2)

      assert Billing.subscription_status(user).state == :active
    end

    test "EXPIRATION removes the entitlement", %{user: user} = ctx do
      t0 = now_ms()
      {:ok, :applied} = process("INITIAL_PURCHASE", ctx.app_user_id, event_timestamp_ms: t0)
      assert {:ok, :applied} = process("EXPIRATION", ctx.app_user_id, event_timestamp_ms: t0 + 1)

      refute Billing.entitled?(user.id)
      assert Billing.subscription_status(user).state == :expired
    end

    test "a lapsed period expires cleanly without an EXPIRATION event", %{user: user} = ctx do
      past = now_ms() - 1_000

      {:ok, :applied} =
        process("NON_RENEWING_PURCHASE", ctx.app_user_id,
          product_id: pix_product_id(),
          event_timestamp_ms: past - 30 * @day_ms,
          expiration_at_ms: past
        )

      refute Billing.entitled?(user.id)
      assert Billing.subscription_status(user).state == :expired
    end

    test "a replayed event id is ignored", %{user: user} = ctx do
      t0 = now_ms()
      {:ok, :applied} = process("INITIAL_PURCHASE", ctx.app_user_id, event_timestamp_ms: t0)
      expiration = expires_at(user)

      {:ok, :applied} =
        process("EXPIRATION", ctx.app_user_id, id: "evt-1", event_timestamp_ms: t0 + 1)

      {:ok, :applied} =
        process("RENEWAL", ctx.app_user_id,
          event_timestamp_ms: t0 + 2,
          expiration_at_ms: DateTime.to_unix(expiration, :millisecond)
        )

      assert {:ok, :duplicate} =
               process("EXPIRATION", ctx.app_user_id, id: "evt-1", event_timestamp_ms: t0 + 3)

      assert Billing.entitled?(user.id)
    end

    test "an event older than the last applied one is ignored", %{user: user} = ctx do
      t0 = now_ms()
      {:ok, :applied} = process("RENEWAL", ctx.app_user_id, event_timestamp_ms: t0)
      assert {:ok, :ignored} = process("EXPIRATION", ctx.app_user_id, event_timestamp_ms: t0 - 1)
      assert Billing.entitled?(user.id)
    end

    test "an expiration never moves backwards", %{user: user} = ctx do
      t0 = now_ms()
      far = t0 + 60 * @day_ms

      {:ok, :applied} =
        process("RENEWAL", ctx.app_user_id, event_timestamp_ms: t0, expiration_at_ms: far)

      {:ok, :applied} =
        process("PRODUCT_CHANGE", ctx.app_user_id,
          event_timestamp_ms: t0 + 1,
          expiration_at_ms: t0 + 10 * @day_ms
        )

      assert DateTime.to_unix(expires_at(user), :millisecond) == far
    end

    test "a user is resolved by original_app_user_id, then aliases", %{user: user} = ctx do
      assert {:ok, :applied} =
               process("INITIAL_PURCHASE", "$RCAnonymousID:abc",
                 original_app_user_id: "$RCAnonymousID:def",
                 aliases: ["$RCAnonymousID:abc", ctx.app_user_id]
               )

      assert Billing.entitled?(user.id)

      other = user_fixture()
      other_id = Billing.app_user_id(other)

      assert {:ok, :applied} =
               process("INITIAL_PURCHASE", "$RCAnonymousID:x", original_app_user_id: other_id)

      assert Billing.entitled?(other.id)
    end

    test "an unknown subscriber is an error and records nothing", ctx do
      payload = webhook_payload("INITIAL_PURCHASE", Ecto.UUID.generate(), id: "evt-unknown")
      assert {:error, :unknown_subscriber} = Billing.process_webhook_event(payload)

      # The id was not kept: the retry, once the user resolves, still applies.
      retry = put_in(payload, ["event", "app_user_id"], ctx.app_user_id)
      assert {:ok, :applied} = Billing.process_webhook_event(retry)
    end

    test "events for another entitlement, TEST and unhandled types change nothing",
         %{user: user} = ctx do
      assert {:ok, :ignored} =
               process("INITIAL_PURCHASE", ctx.app_user_id, entitlement_ids: ["other"])

      assert {:ok, :ignored} = process("TEST", ctx.app_user_id)
      assert {:ok, :ignored} = process("BILLING_ISSUE", ctx.app_user_id)
      refute Billing.entitled?(user.id)
    end

    test "SANDBOX events are ignored when sandbox is not accepted", %{user: user} = ctx do
      previous = Application.fetch_env!(:backend, Billing)
      Application.put_env(:backend, Billing, Keyword.put(previous, :accept_sandbox, false))
      on_exit(fn -> Application.put_env(:backend, Billing, previous) end)

      assert {:ok, :ignored} =
               process("INITIAL_PURCHASE", ctx.app_user_id, environment: "SANDBOX")

      refute Billing.entitled?(user.id)
    end

    test "a malformed event is rejected" do
      assert {:error, :invalid_event} =
               Billing.process_webhook_event(%{"event" => %{"type" => "RENEWAL"}})

      assert {:error, :invalid_event} = Billing.process_webhook_event(%{})
    end
  end

  describe "Pix plans" do
    test "a Pix purchase does not auto-renew and shows a reminder near the due date",
         %{user: user} = ctx do
      {:ok, :applied} =
        process("NON_RENEWING_PURCHASE", ctx.app_user_id,
          product_id: pix_product_id(),
          expiration_at_ms: now_ms() + 2 * @day_ms
        )

      status = Billing.subscription_status(user)
      assert status.state == :active
      assert status.plan.payment == :pix
      refute status.auto_renews?
      assert status.renewal_reminder?
    end

    test "no reminder far from the due date", %{user: user} = ctx do
      {:ok, :applied} =
        process("NON_RENEWING_PURCHASE", ctx.app_user_id, product_id: pix_product_id())

      refute Billing.subscription_status(user).renewal_reminder?
    end
  end

  describe "verify_webhook/3" do
    @body ~s({"event":{"id":"1"}})

    test "accepts the configured Authorization and a fresh valid signature" do
      assert :ok = Billing.verify_webhook(@body, webhook_authorization(), signature_header(@body))
    end

    test "rejects a wrong Authorization value" do
      assert {:error, :unauthorized} =
               Billing.verify_webhook(@body, "nope", signature_header(@body))

      assert {:error, :unauthorized} = Billing.verify_webhook(@body, nil, signature_header(@body))
    end

    test "rejects a bad, missing, stale or tampered signature" do
      now = System.system_time(:second)
      auth = webhook_authorization()

      assert {:error, :invalid_signature} = Billing.verify_webhook(@body, auth, nil)
      assert {:error, :invalid_signature} = Billing.verify_webhook(@body, auth, "garbage")

      assert {:error, :invalid_signature} =
               Billing.verify_webhook(@body, auth, signature_header(@body, now, "wrong-secret"))

      assert {:error, :invalid_signature} =
               Billing.verify_webhook(@body <> " ", auth, signature_header(@body, now))

      assert {:error, :invalid_signature} =
               Billing.verify_webhook(@body, auth, signature_header(@body, now - 301))
    end

    test "fails closed when the secrets are not configured" do
      signature = signature_header(@body)
      previous = Application.fetch_env!(:backend, Billing)
      Application.put_env(:backend, Billing, Keyword.put(previous, :webhook_secret, nil))
      on_exit(fn -> Application.put_env(:backend, Billing, previous) end)

      assert {:error, :not_configured} =
               Billing.verify_webhook(@body, webhook_authorization(), signature)
    end
  end

  describe "plans/0 and purchase_url/3" do
    test "lists the card and Pix plans" do
      assert [%{payment: :card}, %{payment: :pix}] = Enum.sort_by(Billing.plans(), & &1.payment)
    end

    test "the Web Purchase Link carries the app_user_id and the email", %{user: user} = ctx do
      plan = Enum.find(Billing.plans(), &(&1.payment == :card))
      url = Billing.purchase_url(plan, user)

      assert url =~ "/" <> ctx.app_user_id <> "?"
      assert URI.parse(url).query |> URI.decode_query() == %{"email" => user.email}
    end

    test "is nil when the purchase link is not configured", %{user: user} do
      previous = Application.fetch_env!(:backend, Billing)
      Application.put_env(:backend, Billing, Keyword.put(previous, :purchase_links, %{}))
      on_exit(fn -> Application.put_env(:backend, Billing, previous) end)

      plan = Enum.find(Billing.plans(), &(&1.payment == :card))
      assert Billing.purchase_url(plan, user) == nil
    end
  end

  describe "daily_quota/1 (#340)" do
    test "is the quota of the learner's product, seeded per plan", %{user: user} do
      subscribe_user(user)
      assert Billing.daily_quota(user.id) == 10

      pix_user = user_fixture()
      subscribe_user(pix_user, product_id: pix_product_id())
      assert Billing.daily_quota(pix_user.id) == 10
    end

    test "changes in the database without a deploy", %{user: user} do
      subscribe_user(user)

      assert {:ok, %{product_id: "revalida_mensal_cartao", daily_quota: 2}} =
               Billing.set_daily_quota(card_product_id(), 2)

      assert Billing.daily_quota(user.id) == 2
    end

    test "a product without a quota row gets the configured default", %{user: user} do
      subscribe_user(user, product_id: "produto_desconhecido")
      default = Application.fetch_env!(:backend, Billing)[:default_daily_quota]

      assert default == 3
      assert Billing.daily_quota(user.id) == default
    end

    test "a learner without a subscription gets the configured default" do
      assert Billing.daily_quota(user_fixture().id) == 3
    end

    test "a new product's quota can be added" do
      assert {:ok, _quota} = Billing.set_daily_quota("revalida_anual_cartao", 25)
      user = user_fixture()
      subscribe_user(user, product_id: "revalida_anual_cartao")
      assert Billing.daily_quota(user.id) == 25
    end

    test "rejects a negative or non-integer quota" do
      assert {:error, %Ecto.Changeset{}} = Billing.set_daily_quota(card_product_id(), -1)
      assert {:error, %Ecto.Changeset{}} = Billing.set_daily_quota("", 5)
    end
  end

  describe "quota_day/1 (#340)" do
    test "starts at local midnight in America/Sao_Paulo (03:00 UTC)" do
      assert Billing.quota_day(~U[2026-10-25 02:59:59.999999Z]) == %{
               starts_at: ~U[2026-10-24 03:00:00.000000Z],
               resets_at: ~U[2026-10-25 03:00:00.000000Z]
             }

      assert Billing.quota_day(~U[2026-10-25 03:00:00.000000Z]) == %{
               starts_at: ~U[2026-10-25 03:00:00.000000Z],
               resets_at: ~U[2026-10-26 03:00:00.000000Z]
             }

      assert Billing.quota_day(~U[2026-12-31 23:30:00Z]) == %{
               starts_at: ~U[2026-12-31 03:00:00.000000Z],
               resets_at: ~U[2027-01-01 03:00:00.000000Z]
             }
    end
  end
end
