defmodule BackendWeb.SessionAdmissionTest do
  @moduledoc """
  `POST /sessions` admission during a deploy drain and at the concurrent-session
  cap (#344).
  """

  # The drain flag, the capacity setting and the Conversation table are node-wide.
  use BackendWeb.ConnCase, async: false

  alias Backend.Content
  alias Backend.Stations

  @reference_case File.read!("priv/stations/acute-appendicitis/case.md")

  setup :register_and_log_in_device
  setup %{device_user: user}, do: %{device_user: Backend.BillingFixtures.subscribe_user(user)}

  setup do
    on_exit(&Stations.resume_sessions/0)

    admin = Backend.AccountsFixtures.admin_fixture()
    {:ok, package} = Stations.parse_case(@reference_case)

    %{rows: [[id]]} =
      Backend.Repo.query!(
        "INSERT INTO cases (area, theme, markdown) VALUES ($1, $2, $3) RETURNING id",
        ["Cirurgia Geral", "Tema", @reference_case]
      )

    {:ok, kase} =
      Content.approve_case(
        Content.get_case!(id),
        Map.put(package, "area", "Cirurgia Geral"),
        admin
      )

    %{kase: kase}
  end

  defp start(conn, kase),
    do: post(conn, ~p"/sessions", %{"station_id" => kase.number, "audio_consent" => false})

  describe "while the node drains" do
    test "POST /sessions answers 503 draining with Retry-After", %{conn: conn, kase: kase} do
      :ok = Stations.start_draining()

      conn = start(conn, kase)

      assert %{"error" => "draining", "message" => message} = json_response(conn, 503)
      assert message =~ "atualizado"
      assert [retry_after] = get_resp_header(conn, "retry-after")
      assert String.to_integer(retry_after) > 0
    end

    test "running sessions keep working", %{conn: conn, kase: kase} do
      %{"session_id" => session_id} = conn |> start(kase) |> json_response(201)
      :ok = Stations.start_draining()

      assert %{"session_id" => ^session_id, "status" => "active"} =
               conn |> get(~p"/sessions/#{session_id}") |> json_response(200)
    end

    test "a resumed node starts sessions again", %{conn: conn, kase: kase} do
      :ok = Stations.start_draining()
      :ok = Stations.resume_sessions()

      assert %{"status" => "active"} = conn |> start(kase) |> json_response(201)
    end
  end

  describe "at the concurrent-session cap" do
    setup do
      previous = Application.fetch_env(:backend, :max_concurrent_sessions)

      on_exit(fn ->
        case previous do
          {:ok, value} -> Application.put_env(:backend, :max_concurrent_sessions, value)
          :error -> Application.delete_env(:backend, :max_concurrent_sessions)
        end
      end)
    end

    test "POST /sessions answers 503 capacity_exhausted with Retry-After",
         %{conn: conn, kase: kase} do
      Application.put_env(:backend, :max_concurrent_sessions, Stations.active_session_count())

      conn = start(conn, kase)

      assert %{"error" => "capacity_exhausted", "message" => message} = json_response(conn, 503)
      assert message =~ "ocupadas"
      assert [retry_after] = get_resp_header(conn, "retry-after")
      assert String.to_integer(retry_after) > 0
    end

    test "the last free slot still starts a session", %{conn: conn, kase: kase} do
      Application.put_env(:backend, :max_concurrent_sessions, Stations.active_session_count() + 1)

      assert %{"status" => "active"} = conn |> start(kase) |> json_response(201)
    end
  end
end
