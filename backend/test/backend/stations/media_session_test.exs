defmodule Backend.Stations.MediaSessionTest do
  use ExUnit.Case, async: false

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
end
