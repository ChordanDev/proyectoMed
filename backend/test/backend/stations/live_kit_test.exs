defmodule Backend.Stations.LiveKitTest do
  use ExUnit.Case, async: false

  alias Backend.Stations.LiveKit

  @api_key "test-api-key"
  @api_secret "test-api-secret"

  setup do
    Application.put_env(:backend, :livekit_url, "wss://revalida.livekit.cloud")
    Application.put_env(:backend, :livekit_api_key, @api_key)
    Application.put_env(:backend, :livekit_api_secret, @api_secret)

    on_exit(fn ->
      Application.delete_env(:backend, :livekit_url)
      Application.delete_env(:backend, :livekit_api_key)
      Application.delete_env(:backend, :livekit_api_secret)
      Application.delete_env(:backend, :livekit_join_ttl_ms)
    end)

    :ok
  end

  defp decode_and_verify(token, secret) do
    [header_b64, claims_b64, signature_b64] = String.split(token, ".")

    expected_signature =
      :hmac
      |> :crypto.mac(:sha256, secret, header_b64 <> "." <> claims_b64)
      |> Base.url_encode64(padding: false)

    assert signature_b64 == expected_signature

    header = header_b64 |> Base.url_decode64!(padding: false) |> Jason.decode!()
    claims = claims_b64 |> Base.url_decode64!(padding: false) |> Jason.decode!()
    {header, claims}
  end

  describe "configured?/0 and config/0" do
    test "configured?/0 is true when all three env vars are set" do
      assert LiveKit.configured?() == true
    end

    test "configured?/0 is false when any env var is missing" do
      Application.delete_env(:backend, :livekit_api_secret)
      assert LiveKit.configured?() == false
    end

    test "config/0 returns :not_configured when unset" do
      Application.delete_env(:backend, :livekit_url)
      assert LiveKit.config() == {:error, :not_configured}
    end
  end

  describe "room_name/1 and identity/1" do
    test "are deterministic and bound to the session id" do
      assert LiveKit.room_name("abc123") == "station-session-abc123"
      assert LiveKit.identity("abc123") == "learner-abc123"
    end
  end

  describe "learner_token/3" do
    test "signs a valid HS256 JWT with the exact learner grants" do
      {:ok, config} = LiveKit.config()
      session_expires_at = DateTime.add(DateTime.utc_now(), 1800, :second)

      {token, exp} = LiveKit.learner_token(config, "session-a", session_expires_at)

      {header, claims} = decode_and_verify(token, @api_secret)

      assert header == %{"alg" => "HS256", "typ" => "JWT"}
      assert claims["iss"] == @api_key
      assert claims["sub"] == "learner-session-a"
      assert claims["name"] == "learner-session-a"
      assert is_integer(claims["nbf"])
      assert is_integer(claims["exp"])
      assert is_binary(claims["jti"])
      assert claims["exp"] == DateTime.to_unix(exp)

      assert claims["video"] == %{
               "room" => "station-session-session-a",
               "roomJoin" => true,
               "canPublish" => true,
               "canSubscribe" => true,
               "canPublishData" => false,
               "canPublishSources" => ["microphone"],
               "canUpdateOwnMetadata" => false
             }

      refute Map.has_key?(claims["video"], "roomList")
      refute Map.has_key?(claims["video"], "roomAdmin")
      refute Map.has_key?(claims["video"], "roomCreate")
    end

    test "a token for one session never names another session's room" do
      {:ok, config} = LiveKit.config()
      far_future = DateTime.add(DateTime.utc_now(), 1800, :second)

      {token_a, _} = LiveKit.learner_token(config, "session-a", far_future)
      {token_b, _} = LiveKit.learner_token(config, "session-b", far_future)

      {_header_a, claims_a} = decode_and_verify(token_a, @api_secret)
      {_header_b, claims_b} = decode_and_verify(token_b, @api_secret)

      assert claims_a["video"]["room"] == "station-session-session-a"
      assert claims_b["video"]["room"] == "station-session-session-b"
      assert claims_a["video"]["room"] != claims_b["video"]["room"]
      assert claims_a["sub"] != claims_b["sub"]
    end

    test "exp defaults to now + join TTL when the session expires far in the future" do
      {:ok, config} = LiveKit.config()
      far_future = DateTime.add(DateTime.utc_now(), 3600, :second)

      {_token, exp} = LiveKit.learner_token(config, "session-a", far_future)

      expected = DateTime.add(DateTime.utc_now(), 120, :second)
      assert_in_delta DateTime.to_unix(exp), DateTime.to_unix(expected), 2
    end

    test "exp is capped by the session expiry when it is sooner than the join TTL" do
      {:ok, config} = LiveKit.config()
      soon = DateTime.add(DateTime.utc_now(), 30, :second)

      {_token, exp} = LiveKit.learner_token(config, "session-a", soon)

      assert DateTime.to_unix(exp) == DateTime.to_unix(soon)
    end

    test "join TTL is configurable" do
      Application.put_env(:backend, :livekit_join_ttl_ms, :timer.seconds(10))
      {:ok, config} = LiveKit.config()
      far_future = DateTime.add(DateTime.utc_now(), 3600, :second)

      {_token, exp} = LiveKit.learner_token(config, "session-a", far_future)

      expected = DateTime.add(DateTime.utc_now(), 10, :second)
      assert_in_delta DateTime.to_unix(exp), DateTime.to_unix(expected), 2
    end
  end

  describe "server_token/1" do
    test "grants only roomCreate and roomList, never roomJoin" do
      {:ok, config} = LiveKit.config()

      token = LiveKit.server_token(config)
      {header, claims} = decode_and_verify(token, @api_secret)

      assert header == %{"alg" => "HS256", "typ" => "JWT"}
      assert claims["video"] == %{"roomCreate" => true, "roomList" => true}
      refute Map.has_key?(claims["video"], "roomJoin")

      assert claims["exp"] > claims["nbf"]
      assert claims["exp"] - claims["nbf"] <= 60
    end
  end
end
