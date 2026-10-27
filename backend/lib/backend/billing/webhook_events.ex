defmodule Backend.Billing.WebhookEvents do
  @moduledoc """
  Applies one RevenueCat webhook event to the simulator entitlement (#339,
  research A7 and A8).

  The event id is inserted under a unique index and the effect applied in one
  transaction: a redelivered id is `:duplicate`, and a failed effect (an
  unknown subscriber included) rolls the id back so RevenueCat's retry still
  applies. The subscription row is locked while the event applies. An event
  generated before the last applied one (`event_timestamp_ms`) is ignored,
  and an expiration never moves backwards, except on a refund or chargeback
  (#388): a `CANCELLATION` or `EXPIRATION` whose `cancel_reason` or
  `expiration_reason` is `CUSTOMER_SUPPORT`, or whose `price` is negative, ends
  access at the event time. A later plain `CANCELLATION` does not reopen it;
  a later granting event (a new purchase) does.
  """

  import Ecto.Query

  alias Backend.Billing.{Subscription, WebhookEvent}
  alias Backend.Repo

  @granting ~w(INITIAL_PURCHASE RENEWAL UNCANCELLATION PRODUCT_CHANGE SUBSCRIPTION_EXTENDED NON_RENEWING_PURCHASE)
  @refundable ~w(CANCELLATION EXPIRATION)
  @handled @granting ++ @refundable

  @doc """
  `{:ok, :applied | :ignored | :duplicate}` or
  `{:error, :invalid_event | :unknown_subscriber}`. `opts` takes
  `:entitlement_id` and `:accept_sandbox`.
  """
  def process(%{"event" => %{"id" => id, "type" => type} = event}, opts)
      when is_binary(id) and id != "" and is_binary(type) do
    cond do
      type == "TEST" ->
        {:ok, :ignored}

      event["environment"] == "SANDBOX" and not Keyword.fetch!(opts, :accept_sandbox) ->
        {:ok, :ignored}

      true ->
        transact(id, type, event, opts)
    end
  end

  def process(_payload, _opts), do: {:error, :invalid_event}

  defp transact(id, type, event, opts) do
    Repo.transaction(fn ->
      case Repo.insert(%WebhookEvent{event_id: id, type: type, outcome: "applied"},
             on_conflict: :nothing,
             conflict_target: :event_id
           ) do
        {:ok, %WebhookEvent{id: nil}} ->
          :duplicate

        {:ok, recorded} ->
          type |> apply_event(event, opts) |> record_outcome(recorded)
      end
    end)
  end

  defp record_outcome(:ignored, recorded) do
    Repo.update!(Ecto.Changeset.change(recorded, outcome: "ignored"))
    :ignored
  end

  defp record_outcome(outcome, _recorded), do: outcome

  defp apply_event(type, event, opts) do
    cond do
      type not in @handled -> :ignored
      Keyword.fetch!(opts, :entitlement_id) not in List.wrap(event["entitlement_ids"]) -> :ignored
      true -> apply_to(resolve(event), type, event)
    end
  end

  defp apply_to(nil, _type, _event), do: Repo.rollback(:unknown_subscriber)

  defp apply_to(%Subscription{} = sub, type, event) do
    event_at = from_ms(event["event_timestamp_ms"]) || DateTime.utc_now()

    if sub.last_event_at && DateTime.compare(event_at, sub.last_event_at) == :lt do
      :ignored
    else
      sub
      |> Ecto.Changeset.change(changes(type, event, sub, event_at))
      |> Ecto.Changeset.put_change(:last_event_at, event_at)
      |> Repo.update!()

      :applied
    end
  end

  defp changes(type, event, sub, event_at) do
    if type in @refundable and refund?(event),
      do: refund(event_at),
      else: plain_changes(type, event, sub)
  end

  # A refund or chargeback is the only exception to "an expiration never
  # moves backwards" (#388): access ends at the event time.
  defp refund(event_at), do: %{status: :expired, expires_at: event_at, refunded_at: event_at}

  # RevenueCat signals a refund with cancel_reason (CANCELLATION) or
  # expiration_reason (EXPIRATION) CUSTOMER_SUPPORT, or with a negative price.
  defp refund?(event) do
    "CUSTOMER_SUPPORT" in [event["cancel_reason"], event["expiration_reason"]] or
      (is_number(event["price"]) and event["price"] < 0)
  end

  defp plain_changes(type, event, sub) when type in @granting do
    %{
      status: :active,
      product_id: event["product_id"] || sub.product_id,
      store: event["store"] || sub.store,
      environment: event["environment"] || sub.environment,
      expires_at: latest(sub.expires_at, from_ms(event["expiration_at_ms"])),
      refunded_at: nil
    }
  end

  # A plain cancellation never reopens a refunded subscription.
  defp plain_changes("CANCELLATION", _event, %Subscription{refunded_at: %DateTime{}}), do: %{}

  defp plain_changes("CANCELLATION", event, sub),
    do: %{
      status: :cancelled,
      expires_at: latest(sub.expires_at, from_ms(event["expiration_at_ms"]))
    }

  defp plain_changes("EXPIRATION", _event, _sub), do: %{status: :expired}

  # Lookup order of research A7: app_user_id, original_app_user_id, aliases.
  defp resolve(event) do
    candidates =
      [event["app_user_id"], event["original_app_user_id"] | List.wrap(event["aliases"])]
      |> Enum.filter(&(is_binary(&1) and &1 != ""))
      |> Enum.uniq()

    found =
      Repo.all(from s in Subscription, where: s.app_user_id in ^candidates, lock: "FOR UPDATE")

    Enum.find_value(candidates, fn id -> Enum.find(found, &(&1.app_user_id == id)) end)
  end

  defp latest(nil, new), do: new
  defp latest(old, nil), do: old
  defp latest(old, new), do: if(DateTime.compare(new, old) == :gt, do: new, else: old)

  defp from_ms(ms) when is_integer(ms), do: DateTime.from_unix!(ms * 1000, :microsecond)
  defp from_ms(_ms), do: nil
end
