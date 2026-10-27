defmodule BackendWeb.Plugs.SessionReplayTest do
  @moduledoc """
  During a deploy the Fly proxy may send a request for a running session to the
  new machine (#344): it answers with `fly-replay: instance=<owner>` so the
  proxy replays the request to the machine that holds the conversation.
  """

  # Mutates the node-wide machine id.
  use BackendWeb.ConnCase, async: false

  alias BackendWeb.Plugs.SessionReplay

  @this_machine "e2865013b45e78"
  @old_machine "3d8d9e1b2c4a77"
  @old_session "#{@old_machine}.AAAAAAAAAAAAAAAAAAAAAA"

  setup do
    previous = Application.fetch_env(:backend, :machine_id)
    Application.put_env(:backend, :machine_id, @this_machine)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:backend, :machine_id, value)
        :error -> Application.delete_env(:backend, :machine_id)
      end
    end)

    :ok
  end

  defp call(conn, session_id) do
    conn
    |> Map.put(:path_params, %{"id" => session_id})
    |> SessionReplay.call(SessionReplay.init([]))
  end

  test "replays a session of another machine to it", %{conn: conn} do
    conn = call(conn, @old_session)

    assert conn.halted
    assert conn.status == 409
    assert get_resp_header(conn, "fly-replay") == ["instance=#{@old_machine}"]
  end

  test "passes this machine's sessions and unprefixed ids through", %{conn: conn} do
    for id <- ["#{@this_machine}.AAAA", "AAAAAAAAAAAAAAAAAAAAAA"] do
      conn = call(conn, id)
      refute conn.halted
      assert get_resp_header(conn, "fly-replay") == []
    end
  end

  test "never replays a request the proxy already replayed", %{conn: conn} do
    conn =
      conn
      |> put_req_header("fly-replay-src", "instance=#{@old_machine};state=")
      |> call(@old_session)

    refute conn.halted
  end

  test "a route without a session passes through", %{conn: conn} do
    conn = SessionReplay.call(conn, SessionReplay.init([]))
    refute conn.halted
  end

  describe "routes" do
    test "the learner, legacy and voice-worker session routes replay before authenticating",
         %{conn: conn} do
      for path <- [
            ~p"/sessions/#{@old_session}",
            ~p"/sessions/#{@old_session}/result",
            ~p"/api/stations/active/sessions/#{@old_session}",
            ~p"/api/v2/stations/active/sessions/#{@old_session}/result",
            ~p"/api/internal/voice/sessions/#{@old_session}"
          ] do
        conn = get(conn, path)
        assert conn.status == 409, "expected #{path} to replay"
        assert get_resp_header(conn, "fly-replay") == ["instance=#{@old_machine}"]
      end
    end

    test "session routes of this machine still require authentication", %{conn: conn} do
      conn = get(conn, "/sessions/#{@this_machine}.AAAA")
      assert conn.status == 401
    end
  end
end
