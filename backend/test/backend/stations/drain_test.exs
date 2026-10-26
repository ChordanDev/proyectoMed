defmodule Backend.Stations.DrainTest do
  @moduledoc """
  The pre-deploy drain gate (#344): an operator switches the node to "no new
  sessions" and watches its active sessions reach zero before `fly deploy`.
  """

  # The drain flag and the Conversation table are node-wide.
  use Backend.DataCase, async: false

  import ExUnit.CaptureIO

  alias Backend.Release
  alias Backend.Stations

  setup do
    on_exit(&Stations.resume_sessions/0)
    :ok
  end

  test "a node starts accepting sessions" do
    refute Stations.draining?()
    assert %{draining: false, active_sessions: count} = Stations.drain_status()
    assert is_integer(count)
  end

  test "draining refuses new sessions until resumed" do
    assert :ok = Stations.start_draining()
    assert Stations.draining?()

    assert {:error, :draining} =
             Stations.start_station_session({:station, 1}, %{audio_consent: false})

    assert :ok = Stations.resume_sessions()
    refute Stations.draining?()

    assert {:error, :station_not_found} =
             Stations.start_station_session({:station, 999_999_999}, %{audio_consent: false})
  end

  test "active sessions count running sessions only" do
    before = Stations.active_session_count()
    session = Stations.create_session(audio_consent: false)
    assert Stations.active_session_count() == before + 1
    assert Stations.drain_status().active_sessions == before + 1

    {:ok, _completed} = Stations.finish_session(session.session_id)
    assert Stations.active_session_count() == before
  end

  describe "operator release commands (bin/drain)" do
    test "drain/0, drain_status/0 and resume/0 print the node state" do
      drain = capture_io(fn -> assert :ok = Release.drain() end)
      assert drain =~ ~r/^draining=true active_sessions=\d+/
      assert Stations.draining?()

      status = capture_io(fn -> assert :ok = Release.drain_status() end)
      assert status =~ ~r/^draining=true active_sessions=\d+/

      resume = capture_io(fn -> assert :ok = Release.resume() end)
      assert resume =~ ~r/^draining=false active_sessions=\d+/
      refute Stations.draining?()
    end
  end
end
