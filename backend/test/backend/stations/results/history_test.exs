defmodule Backend.Stations.Results.HistoryTest do
  @moduledoc """
  The learner's results history (#338, ADR-014 #346): one stored Educational
  Result per graded session of a learner, nothing on a technical failure, and
  deleted with the account.
  """

  # Session state lives in the shared Conversation table and the tests swap
  # the application env: not async.
  use Backend.DataCase, async: false

  import Backend.AccountsFixtures
  import Backend.ResultsFixtures

  alias Backend.Accounts
  alias Backend.Stations
  alias Backend.Stations.Results.StoredResult

  setup do
    use_jev_adapter(Backend.ResultsFixtures.UncertainDouble)
    %{kase: published_case_fixture(), user: user_fixture()}
  end

  describe "a graded session of a learner" do
    test "stores its Educational Result once, as served at the end of the session",
         %{kase: kase, user: user} do
      session_id = finished_session_fixture(user, kase)

      assert {:ok, result} = Stations.get_educational_result(session_id)
      assert {:ok, ^result} = Stations.get_educational_result(session_id)

      assert [stored] = Repo.all(StoredResult)
      assert stored.user_id == user.id
      assert stored.session_id == session_id
      assert stored.case_number == kase.number
      assert stored.version_number == 1
      assert stored.area == "Cirurgia Geral"
      assert %DateTime{} = stored.finished_at
      assert stored.result == json(result)
      assert stored.result["estimates"]["total"] == nil
    end

    test "is listed and shown only to its learner", %{kase: kase, user: user} do
      session_id = finished_session_fixture(user, kase)
      {:ok, result} = Stations.get_educational_result(session_id)

      assert %{results: [summary], has_more: false} = Stations.list_results(user.id)
      assert summary.session_id == session_id

      assert {:ok, detail} = Stations.get_result(user.id, summary.id)
      assert detail.result == json(result)

      other = user_fixture()
      assert %{results: []} = Stations.list_results(other.id)
      assert {:error, :not_found} = Stations.get_result(other.id, summary.id)
    end

    test "is deleted with the learner's account", %{kase: kase, user: user} do
      {:ok, _} = Stations.get_educational_result(finished_session_fixture(user, kase))
      assert Repo.aggregate(StoredResult, :count) == 1

      {:ok, _} = Accounts.delete_user(user)
      assert Repo.aggregate(StoredResult, :count) == 0
    end
  end

  test "a technical failure stores nothing", %{kase: kase, user: user} do
    use_jev_adapter(Backend.ResultsFixtures.TechnicalFailureDouble)
    session_id = finished_session_fixture(user, kase)

    assert {:error, {:invalid_attempt, _}} = Stations.get_educational_result(session_id)
    assert Repo.aggregate(StoredResult, :count) == 0
  end

  test "a session without a learner stores nothing", %{kase: kase} do
    {:ok, _} = Stations.get_educational_result(finished_session_fixture(nil, kase))
    assert Repo.aggregate(StoredResult, :count) == 0
  end

  defp json(result), do: result |> Jason.encode!() |> Jason.decode!()
end
