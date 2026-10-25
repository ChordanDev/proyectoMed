defmodule BackendWeb.DeviceControllerTest do
  @moduledoc """
  The device login API of the Unreal client (#337, RFC 8628 shape):
  `POST /device/start`, `POST /device/token` (poll), `POST /device/refresh`
  and `POST /device/logout`.
  """

  use BackendWeb.ConnCase, async: true

  import Backend.AccountsFixtures
  import Ecto.Query, only: [from: 2]

  alias Backend.Accounts

  defp start!(conn) do
    conn |> post(~p"/device/start") |> json_response(200)
  end

  defp tokens!(conn, user) do
    start = start!(conn)
    :ok = Accounts.approve_device_authorization(user, start["user_code"])
    conn |> post(~p"/device/token", %{device_code: start["device_code"]}) |> json_response(200)
  end

  describe "POST /device/start" do
    test "returns the codes, the verification URIs, the interval and the lifetime", %{conn: conn} do
      body = start!(conn)

      assert is_binary(body["device_code"])
      assert body["user_code"] =~ ~r/^[A-Z]{4}-[A-Z]{4}$/
      assert body["verification_uri"] == url(~p"/device")

      assert body["verification_uri_complete"] ==
               url(~p"/device?#{[user_code: body["user_code"]]}")

      assert body["interval"] == 5
      assert body["expires_in"] == 600
    end
  end

  describe "POST /device/token" do
    test "answers authorization_pending, then slow_down when polled too fast", %{conn: conn} do
      start = start!(conn)

      assert %{"error" => "authorization_pending"} =
               conn
               |> post(~p"/device/token", %{device_code: start["device_code"]})
               |> json_response(400)

      assert %{"error" => "slow_down"} =
               conn
               |> post(~p"/device/token", %{device_code: start["device_code"]})
               |> json_response(400)
    end

    test "returns the tokens after the learner approves", %{conn: conn} do
      user = user_fixture()
      body = tokens!(conn, user)

      assert body["token_type"] == "Bearer"
      assert body["expires_in"] == 900
      assert body["refresh_expires_in"] == 30 * 24 * 3600
      assert Accounts.get_user_by_device_access_token(body["access_token"]).id == user.id
    end

    test "answers access_denied after the learner denies", %{conn: conn} do
      start = start!(conn)
      :ok = Accounts.deny_device_authorization(user_fixture(), start["user_code"])

      assert %{"error" => "access_denied", "message" => message} =
               conn
               |> post(~p"/device/token", %{device_code: start["device_code"]})
               |> json_response(400)

      assert message =~ "negado"
    end

    test "answers expired_token after the code expired", %{conn: conn} do
      start = start!(conn)
      hash = :crypto.hash(:sha256, start["device_code"])

      Backend.Repo.update_all(
        from(d in Backend.Accounts.DeviceAuthorization,
          where: d.device_code_hash == ^hash
        ),
        set: [expires_at: DateTime.add(DateTime.utc_now(:second), -1)]
      )

      assert %{"error" => "expired_token"} =
               conn
               |> post(~p"/device/token", %{device_code: start["device_code"]})
               |> json_response(400)
    end

    test "answers invalid_grant for a missing or unknown device code", %{conn: conn} do
      assert %{"error" => "invalid_grant"} =
               conn |> post(~p"/device/token", %{}) |> json_response(400)

      assert %{"error" => "invalid_grant"} =
               conn |> post(~p"/device/token", %{device_code: "nope"}) |> json_response(400)
    end
  end

  describe "POST /device/refresh" do
    test "rotates the tokens", %{conn: conn} do
      user = user_fixture()
      tokens = tokens!(conn, user)

      refreshed =
        conn
        |> post(~p"/device/refresh", %{refresh_token: tokens["refresh_token"]})
        |> json_response(200)

      assert Accounts.get_user_by_device_access_token(refreshed["access_token"]).id == user.id
      refute Accounts.get_user_by_device_access_token(tokens["access_token"])
    end

    test "answers invalid_grant for a missing, unknown or rotated refresh token", %{conn: conn} do
      tokens = tokens!(conn, user_fixture())
      post(conn, ~p"/device/refresh", %{refresh_token: tokens["refresh_token"]})

      for params <- [%{}, %{refresh_token: "nope"}, %{refresh_token: tokens["refresh_token"]}] do
        assert %{"error" => "invalid_grant"} =
                 conn |> post(~p"/device/refresh", params) |> json_response(400)
      end
    end
  end

  describe "POST /device/logout" do
    test "revokes this device login", %{conn: conn} do
      user = user_fixture()
      tokens = tokens!(conn, user)
      other = tokens!(conn, user)

      conn
      |> put_req_header("authorization", "Bearer " <> tokens["access_token"])
      |> post(~p"/device/logout")
      |> response(204)

      refute Accounts.get_user_by_device_access_token(tokens["access_token"])
      assert Accounts.get_user_by_device_access_token(other["access_token"])
    end

    test "with everywhere revokes every device login of the learner", %{conn: conn} do
      user = user_fixture()
      tokens = tokens!(conn, user)
      other = tokens!(conn, user)

      conn
      |> put_req_header("authorization", "Bearer " <> tokens["access_token"])
      |> post(~p"/device/logout", %{everywhere: true})
      |> response(204)

      refute Accounts.get_user_by_device_access_token(other["access_token"])
    end

    test "requires a valid access token", %{conn: conn} do
      assert %{"error" => "missing_token"} =
               conn |> post(~p"/device/logout") |> json_response(401)

      assert %{"error" => "invalid_token"} =
               conn
               |> put_req_header("authorization", "Bearer nope")
               |> post(~p"/device/logout")
               |> json_response(401)
    end
  end
end
