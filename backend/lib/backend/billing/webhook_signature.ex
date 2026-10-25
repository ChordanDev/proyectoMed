defmodule Backend.Billing.WebhookSignature do
  @moduledoc """
  Verifies a RevenueCat webhook request (#339, research A8): the
  `Authorization` header must equal the value set in the RevenueCat dashboard,
  and `X-RevenueCat-Webhook-Signature: t=<unix>,v1=<hex>` must be the
  HMAC-SHA256, hex encoded, of `"<t>.<raw body>"` with the signing secret,
  with `t` within the tolerance window. Comparisons are constant time.
  """

  @doc """
  `:ok`, or `{:error, :not_configured | :unauthorized | :invalid_signature}`.
  `opts` takes `:authorization`, `:secret`, `:tolerance_s` and `:now` (unix
  seconds).
  """
  def verify(raw_body, authorization, signature, opts) when is_binary(raw_body) do
    expected_auth = Keyword.get(opts, :authorization)
    secret = Keyword.get(opts, :secret)

    cond do
      blank?(expected_auth) or blank?(secret) -> {:error, :not_configured}
      not equal?(authorization, expected_auth) -> {:error, :unauthorized}
      true -> verify_signature(raw_body, signature, secret, opts)
    end
  end

  defp verify_signature(raw_body, signature, secret, opts) do
    tolerance = Keyword.get(opts, :tolerance_s, 300)
    now = Keyword.get_lazy(opts, :now, fn -> System.system_time(:second) end)

    with {:ok, t, candidates} <- parse(signature),
         true <- abs(now - t) <= tolerance,
         expected = hmac(secret, "#{t}.#{raw_body}"),
         true <- Enum.any?(candidates, &equal?(&1, expected)) do
      :ok
    else
      _invalid -> {:error, :invalid_signature}
    end
  end

  defp parse(signature) when is_binary(signature) do
    pairs =
      for part <- String.split(signature, ","),
          [key, value] <- [String.split(String.trim(part), "=", parts: 2)],
          do: {key, value}

    with {"t", raw_t} <- List.keyfind(pairs, "t", 0),
         {t, ""} <- Integer.parse(raw_t),
         [_ | _] = candidates <- for({"v1", v} <- pairs, do: String.downcase(v)) do
      {:ok, t, candidates}
    else
      _invalid -> :error
    end
  end

  defp parse(_signature), do: :error

  defp hmac(secret, data),
    do: :crypto.mac(:hmac, :sha256, secret, data) |> Base.encode16(case: :lower)

  defp equal?(a, b) when is_binary(a) and is_binary(b), do: Plug.Crypto.secure_compare(a, b)
  defp equal?(_a, _b), do: false

  defp blank?(value), do: not is_binary(value) or value == ""
end
