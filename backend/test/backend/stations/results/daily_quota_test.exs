defmodule Backend.Stations.Results.DailyQuotaTest do
  @moduledoc """
  Daily simulation quotas (#340): a learner starts at most their plan's daily
  quota of sessions per America/Sao_Paulo day. Graded sessions count; a
  session in flight holds its slot until it is graded or expires; a technical
  failure releases its slot at expiry and never consumes quota.
  """

  # Session state lives in the shared Conversation table and the tests swap
  # the application env: not async.
  use Backend.DataCase, async: false

  import Backend.AccountsFixtures
  import Backend.BillingFixtures
  import Backend.ResultsFixtures

  alias Backend.Billing
  alias Backend.Stations
  alias Backend.Stations.Results.{DailyQuota, QuotaReservation, StoredResult}

  setup do
    use_jev_adapter(Backend.ResultsFixtures.UncertainDouble)
    {:ok, _quota} = Billing.set_daily_quota(card_product_id(), 2)
    %{kase: published_case_fixture(), user: subscribe_user(user_fixture())}
  end

  defp start(user, kase) do
    with {:ok, session} <-
           Stations.start_station_session({:station, kase.number}, %{
             audio_consent: false,
             user_id: user.id
           }) do
      on_exit(fn -> Stations.discard_session(session.session_id) end)
      {:ok, session}
    end
  end

  defp graded_session(user, kase) do
    session_id = finished_session_fixture(user, kase)
    {:ok, _result} = Stations.get_educational_result(session_id)
    session_id
  end

  defp expire_reservations(user) do
    past = DateTime.add(DateTime.utc_now(), -1, :second)
    Repo.update_all(where(QuotaReservation, user_id: ^user.id), set: [expires_at: past])
  end

  describe "starting a session" do
    test "the quota+1th session of the day is refused with the reset time",
         %{kase: kase, user: user} do
      assert {:ok, _first} = start(user, kase)
      assert {:ok, _second} = start(user, kase)

      resets_at = Billing.quota_day().resets_at
      assert {:error, {:daily_quota_exhausted, ^resets_at}} = start(user, kase)
    end

    test "graded sessions of today count", %{kase: kase, user: user} do
      graded_session(user, kase)
      graded_session(user, kase)
      expire_reservations(user)

      assert {:error, {:daily_quota_exhausted, _resets_at}} = start(user, kase)
    end

    test "graded sessions before local midnight do not count", %{kase: kase, user: user} do
      graded_session(user, kase)
      graded_session(user, kase)
      expire_reservations(user)

      yesterday = DateTime.add(Billing.quota_day().starts_at, -1, :second)
      Repo.update_all(where(StoredResult, user_id: ^user.id), set: [finished_at: yesterday])

      assert {:ok, _session} = start(user, kase)
    end

    test "a technical failure never consumes quota", %{kase: kase, user: user} do
      graded_session(user, kase)

      use_jev_adapter(Backend.ResultsFixtures.TechnicalFailureDouble)
      failed = finished_session_fixture(user, kase)
      assert {:error, _technical_failure} = Stations.get_educational_result(failed)

      # The failed session holds its slot until it expires, then releases it.
      assert {:error, {:daily_quota_exhausted, _resets_at}} = start(user, kase)
      expire_reservations(user)
      assert {:ok, _session} = start(user, kase)
      assert Repo.aggregate(where(StoredResult, user_id: ^user.id), :count) == 1
    end

    test "a quota change applies to the next start without a deploy", %{kase: kase, user: user} do
      {:ok, _quota} = Billing.set_daily_quota(card_product_id(), 0)
      assert {:error, {:daily_quota_exhausted, _resets_at}} = start(user, kase)

      {:ok, _quota} = Billing.set_daily_quota(card_product_id(), 1)
      assert {:ok, _session} = start(user, kase)
    end

    test "quotas are per learner", %{kase: kase, user: user} do
      {:ok, _} = start(user, kase)
      {:ok, _} = start(user, kase)

      other = subscribe_user(user_fixture())
      assert {:ok, _session} = start(other, kase)
    end

    test "an unknown station still answers station_not_found and reserves nothing",
         %{user: user} do
      assert {:error, :station_not_found} =
               Stations.start_station_session({:station, 999_999}, %{
                 audio_consent: false,
                 user_id: user.id
               })

      assert Repo.aggregate(QuotaReservation, :count) == 0
    end
  end

  describe "daily_quota_status/1" do
    test "reports today's quota, used and remaining simulations", %{kase: kase, user: user} do
      %{resets_at: resets_at} = Billing.quota_day()

      assert Stations.daily_quota_status(user.id) == %{
               daily_quota: 2,
               used: 0,
               remaining: 2,
               resets_at: resets_at
             }

      graded_session(user, kase)
      assert %{used: 1, remaining: 1} = Stations.daily_quota_status(user.id)

      {:ok, _in_flight} = start(user, kase)
      assert %{used: 2, remaining: 0} = Stations.daily_quota_status(user.id)
    end

    test "remaining never goes below zero", %{kase: kase, user: user} do
      graded_session(user, kase)
      graded_session(user, kase)
      {:ok, _quota} = Billing.set_daily_quota(card_product_id(), 1)

      assert %{used: 2, remaining: 0} = Stations.daily_quota_status(user.id)
    end
  end

  describe "two starts at the same moment at quota-1" do
    # Each start runs on its own database connection, outside the sandbox, so
    # the per-learner advisory lock is what serializes them.
    test "exactly one starts; the other is refused" do
      %{rows: [[user_id]]} =
        Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
          Repo.query!(
            "INSERT INTO users (email, hashed_password, inserted_at, updated_at) " <>
              "VALUES ($1, 'x', now(), now()) RETURNING id",
            ["race-#{System.unique_integer([:positive])}@example.com"]
          )
        end)

      on_exit(fn ->
        Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
          Repo.query!("DELETE FROM users WHERE id = $1", [user_id])
        end)
      end)

      %{resets_at: resets_at} = day = Billing.quota_day()
      test_pid = self()

      start = fn ->
        send(test_pid, {:started, self()})
        Process.sleep(200)
        %{session_id: Ecto.UUID.generate(), expires_at: DateTime.add(DateTime.utc_now(), 60)}
      end

      outcomes =
        [1, 2]
        |> Enum.map(fn _ ->
          Task.async(fn ->
            Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
              DailyQuota.reserve(user_id, 1, day, start)
            end)
          end)
        end)
        |> Task.await_many(5_000)

      assert [{:error, {:daily_quota_exhausted, ^resets_at}}, {:ok, %{session_id: _}}] =
               Enum.sort_by(outcomes, &elem(&1, 0))

      assert_received {:started, _pid}
      refute_received {:started, _pid}
    end
  end
end
