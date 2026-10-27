defmodule BackendWeb.RevenueCatWebhookController do
  @moduledoc """
  RevenueCat webhook (#339): `POST /webhooks/revenuecat`.

  Verifies the `Authorization` header and the
  `X-RevenueCat-Webhook-Signature` HMAC over the raw body kept by
  `BackendWeb.RevenueCatBodyReader`, then applies the event through
  `Backend.Billing`. Answers 200 only once the event is committed (applied,
  ignored or a duplicate); 401 for a bad `Authorization` or signature, 503
  when the secrets are not configured, 400 for a body without an event and
  404 when no learner resolves, so RevenueCat retries. Neither the payload
  nor the headers are logged (the route sets `log: false`).
  """

  use BackendWeb, :controller

  alias Backend.Billing
  alias BackendWeb.RevenueCatBodyReader

  def create(conn, _params) do
    raw_body = RevenueCatBodyReader.raw_body(conn) || ""
    authorization = header(conn, "authorization")
    signature = header(conn, "x-revenuecat-webhook-signature")

    with :ok <- Billing.verify_webhook(raw_body, authorization, signature),
         {:ok, outcome} <- Billing.process_webhook_event(conn.body_params) do
      json(conn, %{status: outcome})
    else
      {:error, :not_configured} ->
        error(conn, :service_unavailable, "webhook_not_configured", "Webhook não configurado.")

      {:error, :unauthorized} ->
        error(conn, :unauthorized, "unauthorized", "Autorização inválida.")

      {:error, :invalid_signature} ->
        error(conn, :unauthorized, "invalid_signature", "Assinatura inválida.")

      {:error, :invalid_event} ->
        error(conn, :bad_request, "invalid_event", "Evento inválido.")

      {:error, :unknown_subscriber} ->
        error(conn, :not_found, "unknown_subscriber", "Assinante desconhecido.")
    end
  end

  defp header(conn, name) do
    case get_req_header(conn, name) do
      [value | _] -> value
      [] -> nil
    end
  end

  defp error(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{error: code, message: message})
  end
end
