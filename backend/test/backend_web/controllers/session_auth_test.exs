defmodule BackendWeb.SessionAuthTest do
  @moduledoc """
  The station API of the Unreal client requires a device access token (#337):
  `GET /stations`, `GET /pre-station-notice`, `POST /sessions` and every
  `/sessions/:id/...` route reject missing, expired and revoked tokens, and a
  session belongs to the learner that started it. The deprecated
  `/api/stations/active/...` routes stay unauthenticated only in dev and test.
  """

  # Session state lives in the shared Conversation table and a test swaps the
  # application env: not async.
  use BackendWeb.ConnCase, async: false

  import Backend.AccountsFixtures
  import Backend.BillingFixtures

  alias Backend.Accounts
  alias Backend.Content
  alias Backend.Stations

  @reference_case File.read!("priv/stations/acute-appendicitis/case.md")

  @session_routes [
    {:get, ""},
    {:post, "/messages"},
    {:post, "/finish"},
    {:post, "/discard"},
    {:get, "/result"},
    {:post, "/impressos/request"},
    {:get, "/impressos"},
    {:post, "/transcribe"},
    {:post, "/synthesize"},
    {:post, "/voice"}
  ]

  setup do
    admin = admin_fixture()
    {:ok, package} = Stations.parse_case(@reference_case)

    %{rows: [[id]]} =
      Backend.Repo.query!(
        "INSERT INTO cases (area, theme, markdown) VALUES ($1, $2, $3) RETURNING id",
        ["Cirurgia Geral", "Tema", @reference_case]
      )

    {:ok, kase} = Content.approve_case(Content.get_case!(id), package, admin)
    %{kase: kase}
  end

  # Starting a session requires an active entitlement (#339).
  defp subscriber_fixture, do: user_fixture() |> subscribe_user()

  defp start_session!(conn, kase) do
    conn
    |> recycle()
    |> post(~p"/sessions", %{"station_id" => kase.number, "audio_consent" => false})
    |> json_response(201)
    |> Map.fetch!("session_id")
  end

  defp protected_routes(session_id) do
    [{:get, "/stations"}, {:get, "/pre-station-notice"}, {:post, "/sessions"}] ++
      for {method, suffix} <- @session_routes, do: {method, "/sessions/#{session_id}#{suffix}"}
  end

  defp request(conn, method, path),
    do: conn |> recycle() |> dispatch(@endpoint, method, path, %{})

  describe "without a valid access token" do
    setup %{conn: conn, kase: kase} do
      owner = log_in_device(conn, subscriber_fixture())
      %{session_id: start_session!(owner, kase)}
    end

    test "every route answers 401 missing_token without a token", %{conn: conn} = ctx do
      for {method, path} <- protected_routes(ctx.session_id) do
        body = conn |> request(method, path) |> json_response(401)
        assert body["error"] == "missing_token", path
      end
    end

    test "every route answers 401 invalid_token for an unknown token", %{conn: conn} = ctx do
      conn = put_req_header(conn, "authorization", "Bearer nope")

      for {method, path} <- protected_routes(ctx.session_id) do
        assert %{"error" => "invalid_token"} = conn |> request(method, path) |> json_response(401)
      end
    end

    test "an expired access token is refused", %{conn: conn} = ctx do
      conn = log_in_device(conn, user_fixture())

      Backend.Repo.update_all(Backend.Accounts.DeviceToken,
        set: [access_expires_at: DateTime.add(DateTime.utc_now(:second), -1)]
      )

      for {method, path} <- protected_routes(ctx.session_id) do
        assert %{"error" => "invalid_token"} = conn |> request(method, path) |> json_response(401)
      end
    end

    test "a revoked access token is refused after logout, password change and deletion",
         %{conn: conn} do
      user = user_fixture()
      logged_out = log_in_device(conn, user)
      logged_out |> recycle() |> post(~p"/device/logout") |> response(204)

      password_changed = log_in_device(conn, user)
      {:ok, _} = Accounts.update_user_password(user, %{password: "a brand new password"})

      deleted_user = user_fixture()
      deleted = log_in_device(conn, deleted_user)
      {:ok, _} = Accounts.delete_user(deleted_user)

      for conn <- [logged_out, password_changed, deleted] do
        assert %{"error" => "invalid_token"} =
                 conn |> request(:get, "/stations") |> json_response(401)
      end
    end
  end

  describe "with a learner's access token" do
    setup :register_and_log_in_device
    setup %{device_user: user} = ctx, do: Map.put(ctx, :device_user, subscribe_user(user))

    test "the catalog and the notice are served", %{conn: conn} do
      assert [_station] = conn |> request(:get, "/stations") |> json_response(200)

      assert %{"providers" => _} =
               conn |> request(:get, "/pre-station-notice") |> json_response(200)
    end

    test "a started session belongs to the learner", %{conn: conn, kase: kase, device_user: user} do
      session_id = start_session!(conn, kase)

      assert {:ok, %{user_id: user_id}} = Stations.get_session(session_id)
      assert user_id == user.id

      assert %{"session_id" => ^session_id} =
               conn |> request(:get, "/sessions/#{session_id}") |> json_response(200)
    end

    test "another learner's session is session_not_found on every session route",
         %{conn: conn, kase: kase} do
      other_session = start_session!(log_in_device(build_conn(), subscriber_fixture()), kase)

      for {method, suffix} <- @session_routes do
        path = "/sessions/#{other_session}#{suffix}"
        body = conn |> request(method, path) |> json_response(404)
        assert body["error"] == "session_not_found", path
      end

      assert {:ok, %{status: :active, messages: []}} = Stations.get_session(other_session)
    end
  end

  describe "deprecated active-station routes" do
    test "stay unauthenticated in dev and test", %{conn: conn, kase: kase} do
      session_id = start_session!(log_in_device(build_conn(), subscriber_fixture()), kase)

      assert conn |> request(:get, "/api/stations") |> json_response(200)

      assert conn
             |> request(:get, "/api/stations/active/sessions/#{session_id}")
             |> json_response(200)
    end

    test "require the owner's access token when not enabled (production)", %{
      conn: conn,
      kase: kase
    } do
      previous = Application.fetch_env!(:backend, :legacy_station_api_unauthenticated)
      Application.put_env(:backend, :legacy_station_api_unauthenticated, false)

      on_exit(fn ->
        Application.put_env(:backend, :legacy_station_api_unauthenticated, previous)
      end)

      owner = log_in_device(build_conn(), subscriber_fixture())
      session_id = start_session!(owner, kase)
      stranger = log_in_device(conn, user_fixture())

      for path <- [
            "/api/stations",
            "/api/stations/active/sessions/#{session_id}",
            "/api/v2/stations/active/sessions/#{session_id}/result"
          ] do
        assert %{"error" => "missing_token"} = conn |> request(:get, path) |> json_response(401)
      end

      for method <- [:post, :delete] do
        assert %{"error" => "missing_token"} =
                 conn
                 |> request(method, "/api/stations/active/sessions/#{session_id}/exam-mode")
                 |> json_response(401)

        assert %{"error" => "session_not_found"} =
                 stranger
                 |> request(method, "/api/stations/active/sessions/#{session_id}/exam-mode")
                 |> json_response(404)
      end

      assert %{"error" => "session_not_found"} =
               stranger
               |> request(:get, "/api/stations/active/sessions/#{session_id}")
               |> json_response(404)

      assert %{"session_id" => ^session_id} =
               owner
               |> request(:get, "/api/stations/active/sessions/#{session_id}")
               |> json_response(200)
    end
  end
end
