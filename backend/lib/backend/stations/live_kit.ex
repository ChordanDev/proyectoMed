defmodule Backend.Stations.LiveKit do
  @moduledoc """
  LiveKit configuration and JWT access-token signing.

  Tokens are signed with `:crypto` HMAC-SHA256 (no JWT dependency): stdlib +
  `Jason` are enough for LiveKit's HS256 access tokens. Two token shapes are
  built here:

    * `learner_token/3` — a browser-facing join token scoped to exactly one
      session's room, with only publish/subscribe grants (no room
      administration).
    * `server_token/1` — a short-lived, backend-only token carrying
      `roomCreate`/`roomList` grants for the RoomService adapter. It is never
      sent to a client.
    * `room_admin_token/2` — a short-lived, backend-only token that administers
      exactly one room, so the RoomService adapter can send data into it (#325).
      It is never sent to a client.
  """

  @default_join_ttl_ms :timer.seconds(120)
  # Short enough that a leaked server token is useless within minutes.
  @server_token_ttl_seconds 30

  @type config :: %{url: String.t(), api_key: String.t(), api_secret: String.t()}

  @spec configured?() :: boolean()
  def configured?, do: match?({:ok, _config}, config())

  @spec config() :: {:ok, config()} | {:error, :not_configured}
  def config do
    url = Application.get_env(:backend, :livekit_url)
    api_key = Application.get_env(:backend, :livekit_api_key)
    api_secret = Application.get_env(:backend, :livekit_api_secret)

    if present?(url) and present?(api_key) and present?(api_secret) do
      {:ok, %{url: url, api_key: api_key, api_secret: api_secret}}
    else
      {:error, :not_configured}
    end
  end

  @spec room_name(String.t()) :: String.t()
  def room_name(session_id), do: "station-session-" <> session_id

  @spec identity(String.t()) :: String.t()
  def identity(session_id), do: "learner-" <> session_id

  @doc """
  Builds and signs a learner join token bound to `session_id`'s room, with an
  expiry capped by `session_expires_at`. Returns the signed token and the
  `DateTime` it actually expires at.
  """
  @spec learner_token(config(), String.t(), DateTime.t()) :: {String.t(), DateTime.t()}
  def learner_token(%{api_key: api_key, api_secret: api_secret}, session_id, session_expires_at) do
    now = DateTime.utc_now()
    ttl_candidate = DateTime.add(now, join_ttl_ms(), :millisecond)

    exp =
      if DateTime.compare(ttl_candidate, session_expires_at) == :lt,
        do: ttl_candidate,
        else: session_expires_at

    video = %{
      "room" => room_name(session_id),
      "roomJoin" => true,
      "canPublish" => true,
      "canSubscribe" => true,
      "canPublishData" => false,
      "canPublishSources" => ["microphone"],
      "canUpdateOwnMetadata" => false
    }

    identity = identity(session_id)
    token = sign(api_key, api_secret, identity, video, now, exp)
    {token, exp}
  end

  @doc """
  Builds and signs a server-side RoomService token (`roomCreate`, `roomList`
  only). Never exposed to a client; used solely by the RoomService adapter.
  """
  @spec server_token(config()) :: String.t()
  def server_token(%{api_key: api_key, api_secret: api_secret}) do
    now = DateTime.utc_now()
    exp = DateTime.add(now, @server_token_ttl_seconds, :second)
    video = %{"roomCreate" => true, "roomList" => true}
    sign(api_key, api_secret, "backend-room-service", video, now, exp)
  end

  @doc """
  Builds and signs a server-side token that administers only `room` (#325):
  no join, no other room, no room creation or listing. Never exposed to a
  client; used solely by the RoomService adapter to send data into that room.
  """
  @spec room_admin_token(config(), String.t()) :: String.t()
  def room_admin_token(%{api_key: api_key, api_secret: api_secret}, room) do
    now = DateTime.utc_now()
    exp = DateTime.add(now, @server_token_ttl_seconds, :second)
    video = %{"roomAdmin" => true, "room" => room}
    sign(api_key, api_secret, "backend-room-service", video, now, exp)
  end

  @spec join_ttl_ms() :: pos_integer()
  defp join_ttl_ms do
    Application.get_env(:backend, :livekit_join_ttl_ms, @default_join_ttl_ms)
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp sign(api_key, api_secret, identity, video, now, exp) do
    header = %{"alg" => "HS256", "typ" => "JWT"}

    claims = %{
      "iss" => api_key,
      "sub" => identity,
      "name" => identity,
      "nbf" => DateTime.to_unix(now),
      "exp" => DateTime.to_unix(exp),
      "jti" => random_jti(),
      "video" => video
    }

    header_b64 = encode_segment(header)
    claims_b64 = encode_segment(claims)
    signing_input = header_b64 <> "." <> claims_b64

    signature =
      :hmac
      |> :crypto.mac(:sha256, api_secret, signing_input)
      |> Base.url_encode64(padding: false)

    signing_input <> "." <> signature
  end

  defp encode_segment(map), do: map |> Jason.encode!() |> Base.url_encode64(padding: false)

  defp random_jti, do: :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
end
