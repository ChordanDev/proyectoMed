defmodule Backend.Stations.Results.DailyQuota do
  @moduledoc """
  Daily simulation quotas (#340). A learner may use their plan's quota of
  sessions per quota day (`Backend.Billing.quota_day/1`, from local midnight
  in America/Sao_Paulo).

  A day's use is:

    * every Educational Result stored for the learner (`Results.History`)
      that finished since the start of the day: only graded sessions count;
    * plus every session in flight: started, not graded yet, and not expired.

  Starting a session reserves its slot (`reserve/4`) under a per-learner
  Postgres advisory lock, so two starts at the same moment at quota-1 are
  serialized: the first reserves the last slot and the second is refused.
  Counting only graded results at start would let both through and exceed the
  quota. A reservation stops counting when its session is graded (its result
  counts instead) or expires; an abandoned or technically failed session is
  never graded, so it releases its slot at expiry and never consumes quota.
  """

  import Ecto.Query

  alias Backend.Repo
  alias Backend.Stations.Results.{QuotaReservation, StoredResult}

  # The advisory lock key space of daily quotas: (namespace, user id).
  @lock_namespace 340

  @type day :: %{starts_at: DateTime.t(), resets_at: DateTime.t()}

  @doc """
  Starts a session for `user_id` with `start_fun` when the learner has used
  fewer than `quota` sessions in `day`, and reserves its slot until the
  session's `expires_at`. Otherwise `start_fun` is not called and the result
  is `{:error, {:daily_quota_exhausted, day.resets_at}}`.
  """
  @spec reserve(pos_integer(), non_neg_integer(), day(), (-> map())) ::
          {:ok, map()} | {:error, {:daily_quota_exhausted, DateTime.t()}}
  def reserve(user_id, quota, %{resets_at: resets_at} = day, start_fun)
      when is_integer(user_id) and is_integer(quota) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock($1, $2)", [@lock_namespace, lock_key(user_id)])

      if used(user_id, day) >= quota do
        Repo.rollback({:daily_quota_exhausted, resets_at})
      else
        session = start_fun.()

        Repo.insert!(%QuotaReservation{
          user_id: user_id,
          session_id: session.session_id,
          expires_at: session.expires_at
        })

        session
      end
    end)
  end

  @doc """
  How many sessions `user_id` used in `day`: graded results that finished
  since the start of the day plus sessions in flight.
  """
  @spec used(pos_integer(), day()) :: non_neg_integer()
  def used(user_id, %{starts_at: starts_at}) do
    now = DateTime.utc_now()

    graded =
      Repo.aggregate(
        from(r in StoredResult, where: r.user_id == ^user_id and r.finished_at >= ^starts_at),
        :count
      )

    in_flight =
      Repo.aggregate(
        from(q in QuotaReservation,
          as: :q,
          where: q.user_id == ^user_id and q.expires_at > ^now,
          where:
            not exists(from r in StoredResult, where: r.session_id == parent_as(:q).session_id)
        ),
        :count
      )

    graded + in_flight
  end

  # pg_advisory_xact_lock(int4, int4): fold the bigint user id into int4.
  defp lock_key(user_id), do: rem(user_id, 2_147_483_647)
end
