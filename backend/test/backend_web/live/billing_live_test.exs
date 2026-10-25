defmodule BackendWeb.BillingLiveTest do
  @moduledoc """
  The plan page `/planos` and the account page `/conta` (#339): the purchase
  flow is a RevenueCat Web Purchase Link carrying the learner's app_user_id,
  and the account page shows the plan, the renewal or due date and whether it
  is paid by card or Pix.
  """

  use BackendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Backend.BillingFixtures

  alias Backend.Billing

  @day_ms 86_400_000

  test "both pages require a logged-in user", %{conn: conn} do
    for path <- [~p"/planos", ~p"/conta"] do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, path)
    end
  end

  describe "a logged-in learner" do
    setup :register_and_log_in_user

    test "the plan page links each plan to its Web Purchase Link with the app_user_id",
         %{conn: conn, user: user} do
      {:ok, lv, html} = live(conn, ~p"/planos")

      assert html =~ "Mensal no cartão"
      assert html =~ "Mensal no Pix"
      assert html =~ "renovação automática"

      app_user_id = Billing.app_user_id(user)
      email = URI.encode_query(%{email: user.email})

      assert has_element?(
               lv,
               ~s(a#plan-card[href="https://pay.rev.cat/test-card-token/#{app_user_id}?#{email}"])
             )

      assert has_element?(
               lv,
               ~s(a#plan-pix[href="https://pay.rev.cat/test-pix-token/#{app_user_id}?#{email}"])
             )
    end

    test "the account page without a subscription points to the plans", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/conta")

      assert html =~ "Você ainda não tem uma assinatura."
      assert has_element?(lv, ~s(a[href="/planos"]))
    end

    test "the account page shows a card plan and its renewal date",
         %{conn: conn, user: user} do
      expiration = DateTime.add(DateTime.utc_now(), 20, :day)

      subscribe_user(user, expiration_at_ms: DateTime.to_unix(expiration, :millisecond))

      {:ok, _lv, html} = live(conn, ~p"/conta")

      assert html =~ "Mensal no cartão"
      assert html =~ "Cartão"
      assert html =~ "Renova automaticamente em #{Calendar.strftime(expiration, "%d/%m/%Y")}"
    end

    test "the account page shows a Pix due date and a reminder close to it",
         %{conn: conn, user: user} do
      expiration = DateTime.add(DateTime.utc_now(), 2, :day)

      subscribe_user(user,
        product_id: pix_product_id(),
        expiration_at_ms: DateTime.to_unix(expiration, :millisecond)
      )

      {:ok, lv, html} = live(conn, ~p"/conta")
      due = Calendar.strftime(expiration, "%d/%m/%Y")

      assert html =~ "Mensal no Pix"
      assert html =~ "Vence em #{due}"
      assert has_element?(lv, "#pix-reminder", "Sua assinatura Pix vence em #{due}")
      assert has_element?(lv, ~s(#pix-reminder a[href^="https://pay.rev.cat/test-pix-token/"]))
    end

    test "the account page shows a cancelled and an expired subscription",
         %{conn: conn, user: user} do
      t0 = now_ms()
      expiration = t0 + 10 * @day_ms
      subscribe_user(user, event_timestamp_ms: t0, expiration_at_ms: expiration)

      {:ok, :applied} =
        Billing.process_webhook_event(
          webhook_payload("CANCELLATION", Billing.app_user_id(user),
            event_timestamp_ms: t0 + 1,
            expiration_at_ms: expiration
          )
        )

      {:ok, _lv, html} = live(conn, ~p"/conta")
      until = expiration |> DateTime.from_unix!(:millisecond) |> Calendar.strftime("%d/%m/%Y")
      assert html =~ "Cancelada: acesso até #{until}"

      {:ok, :applied} =
        Billing.process_webhook_event(
          webhook_payload("EXPIRATION", Billing.app_user_id(user), event_timestamp_ms: t0 + 2)
        )

      {:ok, lv, html} = live(conn, ~p"/conta")
      assert html =~ "Assinatura expirada"
      assert has_element?(lv, ~s(a[href="/planos"]))
    end
  end
end
