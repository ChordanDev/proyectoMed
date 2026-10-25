defmodule BackendWeb.RevenueCatWebhookControllerTest do
  @moduledoc """
  `POST /webhooks/revenuecat` (#339): verifies the `Authorization` header and
  the `X-RevenueCat-Webhook-Signature` HMAC over the raw body, then applies
  the event through `Backend.Billing`. 200 only after the event is committed;
  non-200 so RevenueCat retries when the subscriber does not resolve.
  """

  # Some tests swap the Billing application env: not async.
  use BackendWeb.ConnCase, async: false

  import Backend.AccountsFixtures
  import Backend.BillingFixtures
  import ExUnit.CaptureLog

  alias Backend.Billing
  alias BackendWeb.RevenueCatBodyReader

  @path "/webhooks/revenuecat"
  @day_ms 86_400_000

  setup do
    user = user_fixture()
    %{user: user, app_user_id: Billing.app_user_id(user)}
  end

  defp signed_post(conn, raw_body, opts \\ []) do
    t = Keyword.get(opts, :t, System.system_time(:second))
    signature = Keyword.get_lazy(opts, :signature, fn -> signature_header(raw_body, t) end)
    authorization = Keyword.get(opts, :authorization, webhook_authorization())

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", authorization)
    |> put_req_header("x-revenuecat-webhook-signature", signature)
    |> post(@path, raw_body)
  end

  defp body(type, app_user_id, opts \\ []),
    do: Jason.encode!(webhook_payload(type, app_user_id, opts))

  defp with_billing_env(overrides, fun) do
    original = Application.fetch_env!(:backend, Billing)
    Application.put_env(:backend, Billing, Keyword.merge(original, overrides))

    try do
      fun.()
    after
      Application.put_env(:backend, Billing, original)
    end
  end

  describe "a verified event" do
    test "answers 200 after granting the entitlement", %{conn: conn} = ctx do
      conn = signed_post(conn, body("INITIAL_PURCHASE", ctx.app_user_id))

      assert json_response(conn, 200) == %{"status" => "applied"}
      assert Billing.entitled?(ctx.user.id)
    end

    test "a redelivered event id answers 200 and applies once", %{conn: conn} = ctx do
      now = now_ms()

      raw =
        body("INITIAL_PURCHASE", ctx.app_user_id, id: "evt-1", expiration_at_ms: now + @day_ms)

      assert json_response(signed_post(conn, raw), 200) == %{"status" => "applied"}

      # The same id, with a later expiration: still the first effect.
      replay =
        body("INITIAL_PURCHASE", ctx.app_user_id,
          id: "evt-1",
          expiration_at_ms: now + 90 * @day_ms
        )

      assert json_response(signed_post(build_conn(), replay), 200) == %{"status" => "duplicate"}

      assert DateTime.to_unix(Billing.subscription_status(ctx.user).expires_at, :millisecond) ==
               now + @day_ms
    end

    test "an event older than the last applied one changes nothing", %{conn: conn} = ctx do
      now = now_ms()

      newer =
        body("RENEWAL", ctx.app_user_id,
          event_timestamp_ms: now,
          expiration_at_ms: now + 60 * @day_ms
        )

      older =
        body("EXPIRATION", ctx.app_user_id,
          event_timestamp_ms: now - @day_ms,
          expiration_at_ms: now - @day_ms
        )

      assert json_response(signed_post(conn, newer), 200) == %{"status" => "applied"}
      assert json_response(signed_post(build_conn(), older), 200) == %{"status" => "ignored"}
      assert Billing.entitled?(ctx.user.id)
    end

    test "an expiration never moves backwards", %{conn: conn} = ctx do
      now = now_ms()
      later = now + 60 * @day_ms

      assert signed_post(conn, body("RENEWAL", ctx.app_user_id, expiration_at_ms: later)).status ==
               200

      earlier = body("RENEWAL", ctx.app_user_id, expiration_at_ms: now + @day_ms)
      assert signed_post(build_conn(), earlier).status == 200

      assert DateTime.to_unix(Billing.subscription_status(ctx.user).expires_at, :millisecond) ==
               later
    end

    test "an unknown app_user_id answers non-200 and is retried later", %{conn: conn} = ctx do
      raw = body("INITIAL_PURCHASE", Ecto.UUID.generate(), id: "evt-unknown")

      conn = signed_post(conn, raw)
      assert %{"error" => "unknown_subscriber"} = json_response(conn, 404)

      # Not recorded: once the subscriber resolves the same id still applies.
      fixed = body("INITIAL_PURCHASE", ctx.app_user_id, id: "evt-unknown")
      assert json_response(signed_post(build_conn(), fixed), 200) == %{"status" => "applied"}
    end

    test "a body without an event answers 400", %{conn: conn} do
      assert %{"error" => "invalid_event"} = json_response(signed_post(conn, ~s({"foo":1})), 400)
    end
  end

  describe "a rejected request" do
    test "a bad signature answers 401 and changes nothing", %{conn: conn} = ctx do
      raw = body("INITIAL_PURCHASE", ctx.app_user_id)

      conn =
        signed_post(conn, raw,
          signature: signature_header(raw, System.system_time(:second), "wrong")
        )

      assert %{"error" => "invalid_signature"} = json_response(conn, 401)
      refute Billing.entitled?(ctx.user.id)
    end

    test "a signature over another body answers 401", %{conn: conn} = ctx do
      signed = body("INITIAL_PURCHASE", ctx.app_user_id)

      tampered =
        body("INITIAL_PURCHASE", ctx.app_user_id, expiration_at_ms: now_ms() + 900 * @day_ms)

      conn = signed_post(conn, tampered, signature: signature_header(signed))

      assert json_response(conn, 401)["error"] == "invalid_signature"
      refute Billing.entitled?(ctx.user.id)
    end

    test "a stale signature timestamp answers 401", %{conn: conn} = ctx do
      raw = body("INITIAL_PURCHASE", ctx.app_user_id)
      conn = signed_post(conn, raw, t: System.system_time(:second) - 301)

      assert json_response(conn, 401)["error"] == "invalid_signature"
      refute Billing.entitled?(ctx.user.id)
    end

    test "a missing signature answers 401", %{conn: conn} = ctx do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", webhook_authorization())
        |> post(@path, body("INITIAL_PURCHASE", ctx.app_user_id))

      assert json_response(conn, 401)["error"] == "invalid_signature"
    end

    test "a wrong Authorization header answers 401", %{conn: conn} = ctx do
      conn =
        signed_post(conn, body("INITIAL_PURCHASE", ctx.app_user_id), authorization: "Bearer nope")

      assert %{"error" => "unauthorized"} = json_response(conn, 401)
      refute Billing.entitled?(ctx.user.id)
    end

    test "answers 503 when the webhook secrets are not configured", %{conn: conn} = ctx do
      raw = body("INITIAL_PURCHASE", ctx.app_user_id)
      signature = signature_header(raw)

      with_billing_env([webhook_secret: nil], fn ->
        conn = signed_post(conn, raw, signature: signature)

        assert %{"error" => "webhook_not_configured"} = json_response(conn, 503)
      end)

      refute Billing.entitled?(ctx.user.id)
    end

    test "a body over the cap answers 413", %{conn: conn} = ctx do
      padding = String.duplicate("a", RevenueCatBodyReader.max_length() + 1)

      raw =
        Jason.encode!(
          Map.put(webhook_payload("INITIAL_PURCHASE", ctx.app_user_id), "pad", padding)
        )

      assert_error_sent 413, fn -> signed_post(conn, raw) end
      refute Billing.entitled?(ctx.user.id)
    end
  end

  test "logs neither the payload nor the signature", %{conn: conn} = ctx do
    raw = body("INITIAL_PURCHASE", ctx.app_user_id)
    signature = signature_header(raw)
    level = Logger.level()
    Logger.configure(level: :debug)

    log =
      try do
        capture_log([level: :debug], fn ->
          assert signed_post(conn, raw, signature: signature).status == 200
        end)
      after
        Logger.configure(level: level)
      end

    # The request itself is logged; its parameters and headers are not, even
    # at :debug (Ecto's own :debug query lines aside, off in production).
    assert log =~ "POST /webhooks/revenuecat"
    refute log =~ "Parameters:"
    refute log =~ raw
    refute log =~ signature
    refute log =~ webhook_authorization()
  end

  describe "RevenueCatBodyReader" do
    test "keeps the raw body only for the webhook path" do
      webhook =
        Plug.Test.conn(:post, @path, "{\"a\":1}")
        |> RevenueCatBodyReader.read_body(length: 1_000)
        |> elem(2)

      assert RevenueCatBodyReader.raw_body(webhook) == "{\"a\":1}"

      for {method, path} <- [
            {:post, "/sessions"},
            {:post, "/webhooks/revenuecat/x"},
            {:put, @path}
          ] do
        other =
          Plug.Test.conn(method, path, "{\"a\":1}")
          |> RevenueCatBodyReader.read_body(length: 1_000)
          |> elem(2)

        assert RevenueCatBodyReader.raw_body(other) == nil
      end
    end

    test "returns :more past the cap on the webhook path" do
      big = String.duplicate("a", RevenueCatBodyReader.max_length() + 10)

      assert {:more, _partial, _conn} =
               Plug.Test.conn(:post, @path, big)
               |> RevenueCatBodyReader.read_body(length: 20_000_000)
    end
  end
end
