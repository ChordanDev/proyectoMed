defmodule Backend.Stations.CapacityTest do
  @moduledoc """
  The concurrent-session cap of a node (#344): `MAX_CONCURRENT_SESSIONS`
  refuses new sessions with `capacity_exhausted`, and a warning log and
  telemetry event fire from 80% of the cap.
  """

  # The cap and the Conversation table are node-wide.
  use Backend.DataCase, async: false

  import ExUnit.CaptureLog

  alias Backend.Stations

  @warning [:backend, :stations, :capacity, :warning]
  @exhausted [:backend, :stations, :capacity, :exhausted]

  setup do
    previous = Application.fetch_env(:backend, :max_concurrent_sessions)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:backend, :max_concurrent_sessions, value)
        :error -> Application.delete_env(:backend, :max_concurrent_sessions)
      end
    end)

    test_pid = self()
    handler = "capacity-test-#{inspect(make_ref())}"

    :telemetry.attach_many(
      handler,
      [@warning, @exhausted],
      fn event, measurements, _metadata, _config ->
        send(test_pid, {:telemetry, event, measurements})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    :ok
  end

  defp cap(limit), do: Application.put_env(:backend, :max_concurrent_sessions, limit)

  defp start, do: Stations.start_station_session({:station, 999_999_999}, %{audio_consent: false})

  test "the default cap is 200 sessions per node" do
    assert Application.get_env(:backend, :max_concurrent_sessions) == 200
  end

  test "a full node refuses new sessions with capacity_exhausted, logging and alerting" do
    active = Stations.active_session_count()
    cap(active)

    log = capture_log(fn -> assert {:error, :capacity_exhausted} = start() end)

    assert log =~ "concurrent-session cap reached"
    assert log =~ "#{active} of #{active}"
    assert_received {:telemetry, @exhausted, %{active: ^active, limit: ^active}}
  end

  test "from 80% of the cap an admitted session logs a warning and alerts" do
    active = Stations.active_session_count()
    # The admitted session fills the cap, which is above 80% of it.
    limit = active + 1
    cap(limit)

    log = capture_log(fn -> assert {:error, :station_not_found} = start() end)

    assert log =~ "concurrent sessions near the cap: #{limit} of #{limit}"
    assert_received {:telemetry, @warning, %{active: ^limit, limit: ^limit}}
    refute_received {:telemetry, @exhausted, _measurements}
  end

  test "below 80% of the cap nothing is logged" do
    active = Stations.active_session_count()
    cap(active * 10 + 100)

    log = capture_log(fn -> assert {:error, :station_not_found} = start() end)

    refute log =~ "cap"
    refute_received {:telemetry, _event, _measurements}
  end

  test "a draining node reports draining before capacity" do
    cap(0)
    :ok = Stations.start_draining()
    on_exit(&Stations.resume_sessions/0)

    assert {:error, :draining} = start()
  end
end
