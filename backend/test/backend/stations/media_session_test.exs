defmodule Backend.Stations.MediaSessionTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias Backend.Stations.Conversation
  alias Backend.Stations.MediaSession

  setup do
    Application.put_env(:backend, :livekit_rate_limit_max, 2)
    Application.put_env(:backend, :livekit_rate_limit_window_ms, :timer.seconds(60))

    on_exit(fn ->
      Application.delete_env(:backend, :livekit_rate_limit_max)
      Application.delete_env(:backend, :livekit_rate_limit_window_ms)
    end)

    :ok
  end

  test "allows up to the configured max tokens within the window" do
    session_id = unique_session_id()

    assert MediaSession.check_rate_limit(session_id) == :ok
    assert MediaSession.check_rate_limit(session_id) == :ok
  end

  test "rejects the (max + 1)th request within the window" do
    session_id = unique_session_id()

    assert MediaSession.check_rate_limit(session_id) == :ok
    assert MediaSession.check_rate_limit(session_id) == :ok
    assert MediaSession.check_rate_limit(session_id) == {:error, :rate_limited}
  end

  test "other sessions are unaffected by one session's token storm" do
    session_a = unique_session_id()
    session_b = unique_session_id()

    assert MediaSession.check_rate_limit(session_a) == :ok
    assert MediaSession.check_rate_limit(session_a) == :ok
    assert MediaSession.check_rate_limit(session_a) == {:error, :rate_limited}

    assert MediaSession.check_rate_limit(session_b) == :ok
    assert MediaSession.check_rate_limit(session_b) == :ok
  end

  test "clear_rate_limit/1 resets the window for a session" do
    session_id = unique_session_id()

    assert MediaSession.check_rate_limit(session_id) == :ok
    assert MediaSession.check_rate_limit(session_id) == :ok
    assert MediaSession.check_rate_limit(session_id) == {:error, :rate_limited}

    assert MediaSession.clear_rate_limit(session_id) == :ok
    assert MediaSession.check_rate_limit(session_id) == :ok
  end

  defp unique_session_id do
    "media-session-test-" <> (:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false))
  end

  describe "prune_stale_rate_limits/0" do
    test "removes rows whose newest timestamp fell outside the window, keeps fresh rows" do
      Application.put_env(:backend, :livekit_rate_limit_window_ms, 10)
      stale_id = unique_session_id()

      assert MediaSession.check_rate_limit(stale_id) == :ok
      Process.sleep(20)

      fresh_id = unique_session_id()
      assert MediaSession.check_rate_limit(fresh_id) == :ok

      assert MediaSession.prune_stale_rate_limits() == :ok

      assert :ets.lookup(MediaSession, stale_id) == []
      assert :ets.lookup(MediaSession, fresh_id) != []
    end
  end

  describe "scheduled sweep does not block the mailbox" do
    defmodule BlockingRoomService do
      @behaviour Backend.Stations.LiveKit.RoomService

      @impl true
      def delete_room(_room), do: :ok

      @impl true
      def list_rooms do
        # Simulates a slow LiveKit: long enough to prove check_rate_limit/1
        # stays fast, short enough to keep the test suite quick.
        Process.sleep(300)
        {:ok, []}
      end
    end

    test "check_rate_limit/1 returns promptly while a scheduled sweep's HTTP call is slow" do
      Application.put_env(:backend, :livekit_url, "wss://revalida.livekit.cloud")
      Application.put_env(:backend, :livekit_api_key, "test-api-key")
      Application.put_env(:backend, :livekit_api_secret, "test-api-secret")
      Application.put_env(:backend, :livekit_room_service, BlockingRoomService)
      Application.put_env(:backend, :livekit_orphan_sweep_enabled, true)

      on_exit(fn ->
        Application.delete_env(:backend, :livekit_url)
        Application.delete_env(:backend, :livekit_api_key)
        Application.delete_env(:backend, :livekit_api_secret)
        Application.delete_env(:backend, :livekit_room_service)
        Application.delete_env(:backend, :livekit_orphan_sweep_enabled)
      end)

      send(Process.whereis(MediaSession), :tick)
      # Give the scheduled sweep time to start its (now slow) list_rooms call.
      Process.sleep(20)

      {elapsed_us, result} =
        :timer.tc(fn -> MediaSession.check_rate_limit(unique_session_id()) end)

      assert result == :ok
      assert elapsed_us < 100_000
    end
  end

  describe "sweep_orphans/0" do
    defmodule ListingRoomService do
      @behaviour Backend.Stations.LiveKit.RoomService

      @impl true
      def delete_room(room) do
        send(Application.fetch_env!(:backend, :media_session_test_pid), {:deleted_room, room})
        :ok
      end

      @impl true
      def list_rooms do
        {:ok, Application.get_env(:backend, :media_session_test_rooms, [])}
      end
    end

    setup do
      Application.put_env(:backend, :livekit_url, "wss://revalida.livekit.cloud")
      Application.put_env(:backend, :livekit_api_key, "test-api-key")
      Application.put_env(:backend, :livekit_api_secret, "test-api-secret")
      Application.put_env(:backend, :livekit_room_service, ListingRoomService)
      Application.put_env(:backend, :media_session_test_pid, self())

      on_exit(fn ->
        Application.delete_env(:backend, :livekit_url)
        Application.delete_env(:backend, :livekit_api_key)
        Application.delete_env(:backend, :livekit_api_secret)
        Application.delete_env(:backend, :livekit_room_service)
        Application.delete_env(:backend, :media_session_test_pid)
        Application.delete_env(:backend, :media_session_test_rooms)
      end)

      :ok
    end

    test "deletes rooms whose session is not active and ignores non-station rooms" do
      active = Conversation.start(audio_consent: true)
      completed = Conversation.start(audio_consent: true)
      {:ok, _} = Conversation.complete(completed.session_id, :user)

      Application.put_env(:backend, :media_session_test_rooms, [
        "station-session-" <> active.session_id,
        "station-session-" <> completed.session_id,
        "station-session-does-not-exist",
        "some-other-room"
      ])

      MediaSession.sweep_orphans()

      assert_receive {:deleted_room, "station-session-" <> completed_id}
      assert completed_id == completed.session_id

      assert_receive {:deleted_room, "station-session-does-not-exist"}

      active_room = "station-session-" <> active.session_id
      refute_receive {:deleted_room, ^active_room}, 50
      refute_receive {:deleted_room, "some-other-room"}, 50
    end

    test "clears the rate-limit entry for a swept session" do
      Application.put_env(:backend, :livekit_rate_limit_max, 1)
      completed = Conversation.start(audio_consent: true)
      {:ok, _} = Conversation.complete(completed.session_id, :user)

      assert MediaSession.check_rate_limit(completed.session_id) == :ok
      assert MediaSession.check_rate_limit(completed.session_id) == {:error, :rate_limited}

      Application.put_env(:backend, :media_session_test_rooms, [
        "station-session-" <> completed.session_id
      ])

      MediaSession.sweep_orphans()
      assert_receive {:deleted_room, _room}

      Application.delete_env(:backend, :livekit_rate_limit_max)
      assert MediaSession.check_rate_limit(completed.session_id) == :ok
    end

    test "does nothing when LiveKit is not configured" do
      Application.delete_env(:backend, :livekit_url)
      Application.put_env(:backend, :media_session_test_rooms, ["station-session-anything"])

      MediaSession.sweep_orphans()
      refute_receive {:deleted_room, _room}, 50
    end

    test "logs a warning (session id + reason only) when a room delete fails" do
      defmodule FailingRoomService do
        @behaviour Backend.Stations.LiveKit.RoomService

        @impl true
        def delete_room(room) do
          send(Application.fetch_env!(:backend, :media_session_test_pid), {:deleted_room, room})
          {:error, :livekit_unavailable}
        end

        @impl true
        def list_rooms do
          {:ok, Application.get_env(:backend, :media_session_test_rooms, [])}
        end
      end

      Application.put_env(:backend, :livekit_room_service, FailingRoomService)

      orphan_id = "does-not-exist"
      Application.put_env(:backend, :media_session_test_rooms, ["station-session-" <> orphan_id])

      log = capture_log(fn -> MediaSession.sweep_orphans() end)

      assert_receive {:deleted_room, _room}
      assert log =~ orphan_id
      assert log =~ "livekit_unavailable"
    end
  end
end
