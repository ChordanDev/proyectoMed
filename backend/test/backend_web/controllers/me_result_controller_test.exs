defmodule BackendWeb.MeResultControllerTest do
  @moduledoc """
  The learner's results history API (#338): `GET /me/results` lists the
  learner's stored Educational Results newest first, filterable by area and
  paginated; `GET /me/results/:id` shows one exactly as served at the end of
  the session. Another learner's result is 404 and nothing is aggregated
  across sessions.
  """

  # Session state lives in the shared Conversation table and the tests swap
  # the application env: not async.
  use BackendWeb.ConnCase, async: false

  import Backend.AccountsFixtures
  import Backend.ResultsFixtures

  @disclaimer "Estimativa educacional gerada por IA. Não é nota oficial do Revalida. " <>
                "Não indica aprovação, reprovação, certificação ou prontidão para o exame."

  setup :register_and_log_in_device

  setup do
    use_jev_adapter(Backend.ResultsFixtures.UncertainDouble)
    %{kase: published_case_fixture()}
  end

  # Plays a session of the learner on `kase` and fetches its end-of-session
  # result through the API, which stores it.
  defp graded_session!(conn, user, kase) do
    session_id = finished_session_fixture(user, kase)
    result = conn |> recycle() |> get(~p"/sessions/#{session_id}/result") |> json_response(200)
    {session_id, result}
  end

  defp get_json(conn, path, status), do: conn |> recycle() |> get(path) |> json_response(status)

  test "requires a device access token" do
    for path <- ["/me/results", "/me/results/1"] do
      assert %{"error" => "missing_token"} = build_conn() |> get(path) |> json_response(401)
    end
  end

  test "a finished session appears in the history and its detail matches the result",
       %{conn: conn, device_user: user, kase: kase} do
    {session_id, result} = graded_session!(conn, user, kase)

    body = get_json(conn, ~p"/me/results", 200)

    assert Map.keys(body) |> Enum.sort() ==
             ["educational_disclaimer", "has_more", "page", "page_size", "results"]

    assert body["educational_disclaimer"] == @disclaimer
    assert %{"page" => 1, "page_size" => 20, "has_more" => false} = body
    assert [summary] = body["results"]
    assert summary["session_id"] == session_id
    assert {:ok, _, _} = DateTime.from_iso8601(summary["finished_at"])

    assert summary["station"] == %{
             "id" => kase.number,
             "version" => 1,
             "slug" => "acute-appendicitis",
             "area" => "Cirurgia Geral",
             "theme" => "Abdome agudo inflamatório — apendicite aguda",
             "display_title" => summary["station"]["display_title"]
           }

    assert is_binary(summary["station"]["display_title"])

    detail = get_json(conn, ~p"/me/results/#{summary["id"]}", 200)
    assert detail["result"] == result
    assert detail["result"]["estimates"]["total"] == nil
    assert Map.take(detail, Map.keys(summary)) == summary
    assert detail["educational_disclaimer"] == @disclaimer
  end

  test "another learner's result is 404 and absent from their list",
       %{conn: conn, device_user: user, kase: kase} do
    graded_session!(conn, user, kase)
    [%{"id" => id}] = get_json(conn, ~p"/me/results", 200)["results"]

    other = log_in_device(build_conn(), user_fixture())

    assert %{"error" => "result_not_found", "message" => "Resultado não encontrado."} =
             get_json(other, ~p"/me/results/#{id}", 404)

    assert get_json(other, ~p"/me/results", 200)["results"] == []
  end

  test "an unknown or malformed id is 404", %{conn: conn} do
    for id <- ["999999", "abc", "-1", "99999999999999999999"] do
      assert %{"error" => "result_not_found"} = get_json(conn, "/me/results/#{id}", 404)
    end
  end

  test "lists newest first, filters by area and paginates",
       %{conn: conn, device_user: user, kase: kase} do
    pediatrics = published_case_fixture("Pediatria")
    {first, _} = graded_session!(conn, user, kase)
    {second, _} = graded_session!(conn, user, pediatrics)
    {third, _} = graded_session!(conn, user, kase)

    ids = fn body -> Enum.map(body["results"], & &1["session_id"]) end

    assert ids.(get_json(conn, ~p"/me/results", 200)) == [third, second, first]

    assert ids.(get_json(conn, ~p"/me/results?area=Pediatria", 200)) == [second]
    assert ids.(get_json(conn, ~p"/me/results?area=Cirurgia Geral", 200)) == [third, first]

    page_one = get_json(conn, ~p"/me/results?page_size=2", 200)
    assert ids.(page_one) == [third, second]
    assert %{"page" => 1, "page_size" => 2, "has_more" => true} = page_one

    page_two = get_json(conn, ~p"/me/results?page_size=2&page=2", 200)
    assert ids.(page_two) == [first]
    assert page_two["has_more"] == false
  end

  test "invalid pagination is 400 invalid_parameters", %{conn: conn} do
    for query <- ["page=0", "page=x", "page_size=0", "page_size=101", "page_size=2.5"] do
      assert %{"error" => "invalid_parameters"} = get_json(conn, "/me/results?#{query}", 400)
    end
  end

  test "a technical failure leaves the history empty", %{
    conn: conn,
    device_user: user,
    kase: kase
  } do
    use_jev_adapter(Backend.ResultsFixtures.TechnicalFailureDouble)
    session_id = finished_session_fixture(user, kase)
    get_json(conn, ~p"/sessions/#{session_id}/result", 502)

    assert get_json(conn, ~p"/me/results", 200)["results"] == []
  end
end
