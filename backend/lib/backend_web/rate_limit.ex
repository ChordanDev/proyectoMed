defmodule BackendWeb.RateLimit do
  @moduledoc """
  In-memory throttling of the public authentication and device-login
  endpoints (#380): unauthenticated `POST /device/start`, user-code lookups on
  `/device`, login, sign-up, and the password-reset and login-link emails; and
  of the learner session routes that call paid providers (#395, the
  `session_*` actions, through `BackendWeb.Plugs.SessionRateLimit`).

  Each `{action, kind}` pair has a limit of `count` requests per `window_ms`,
  counted per key (`:ip` the client IP, `:email` the normalized email, `:user`
  the logged-in user id, `:session` the station session id, `:learner` the
  device access token's user id). A window opens on a key's first request; a request
  beyond the limit is refused until the window ends. Counters live in a public
  ETS table owned by this process: one Phoenix node at launch (ADR-014 #346),
  so no shared store is needed. A restart forgets every counter.

  Configuration (`config :backend, BackendWeb.RateLimit`):

    * `:enabled` - `false` allows every request (the test config, since every
      test conn comes from the same IP);
    * `:limits` - `[action: [kind: {count, window_ms}]]`, merged over the
      defaults below; `config/runtime.exs` reads the `RATE_LIMIT_*` variables.

  Emails are hashed before they become keys, and a throttled request logs only
  the action and the key kinds, never an IP, email, code or token.
  """

  use GenServer

  require Logger

  @table __MODULE__
  @sweep_interval_ms 60_000

  @minute 60_000
  @hour 60 * @minute

  @default_limits [
    device_start: [ip: {10, @minute}],
    device_lookup: [ip: {30, @minute}, user: {10, @minute}],
    login: [ip: {20, 5 * @minute}, email: {10, 5 * @minute}],
    magic_link_email: [ip: {20, @hour}, email: {5, @hour}],
    reset_password_email: [ip: {20, @hour}, email: {5, @hour}],
    sign_up: [ip: {10, @hour}],
    # Learner session routes that call paid providers (#395). A human-paced
    # station sends a turn every few seconds at most: these sit well above it.
    session_message: [session: {20, @minute}, learner: {40, @minute}],
    session_transcribe: [session: {20, @minute}, learner: {40, @minute}],
    session_synthesize: [session: {30, @minute}, learner: {60, @minute}],
    session_voice: [session: {10, @minute}, learner: {20, @minute}],
    session_impresso: [session: {15, @minute}, learner: {30, @minute}],
    session_exam_mode: [session: {20, @minute}, learner: {40, @minute}],
    session_result: [session: {20, @minute}, learner: {40, @minute}]
  ]

  @typedoc "A throttled endpoint."
  @type action ::
          :device_start
          | :device_lookup
          | :login
          | :magic_link_email
          | :reset_password_email
          | :sign_up
          | :session_message
          | :session_transcribe
          | :session_synthesize
          | :session_voice
          | :session_impresso
          | :session_exam_mode
          | :session_result

  @doc "The pt-BR flash of a throttled browser page."
  def flash_message, do: "Muitas tentativas. Aguarde alguns minutos e tente novamente."

  @doc "The default limits, `[action: [kind: {count, window_ms}]]`."
  def default_limits, do: @default_limits

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Counts one request of `action` for every `{kind, value}` key and answers
  `:ok`, or `{:error, :rate_limited, retry_after_seconds}` when any key is
  beyond its limit. A key whose value is `nil` or that has no limit is skipped.
  """
  @spec check(action(), keyword()) :: :ok | {:error, :rate_limited, pos_integer()}
  def check(action, keys) do
    if enabled?(), do: count(action, keys), else: :ok
  end

  @doc """
  The client IP of a browser request, as a string, for the LiveView session
  (`live_session ..., session: {BackendWeb.RateLimit, :live_session, []}`).
  It is signed into the LiveView session, never stored in the session cookie.
  """
  def live_session(%Plug.Conn{remote_ip: remote_ip}) do
    %{"client_ip" => remote_ip |> :inet.ntoa() |> to_string()}
  end

  @doc "Deletes every expired window and answers how many were deleted."
  def sweep do
    now = now_ms()
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:"=<", :"$1", now}], [true]}])
  end

  @doc "Forgets every counter (tests)."
  def reset do
    :ets.delete_all_objects(@table)
    :ok
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    schedule_sweep()
    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep()
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_interval_ms)

  defp count(action, keys) do
    now = now_ms()

    refused =
      Enum.flat_map(keys, fn {kind, value} ->
        with false <- is_nil(value),
             {_count, _window_ms} = limit <- limit(action, kind),
             retry_ms when is_integer(retry_ms) <-
               hit({action, kind, key(kind, value)}, limit, now) do
          [{kind, retry_ms}]
        else
          _allowed -> []
        end
      end)

    case refused do
      [] ->
        :ok

      refused ->
        kinds = refused |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.join(",")
        Logger.warning("rate limited action=#{action} keys=#{kinds}")

        retry_ms = refused |> Enum.map(&elem(&1, 1)) |> Enum.max()
        {:error, :rate_limited, max(div(retry_ms + 999, 1000), 1)}
    end
  end

  # Answers `nil` when the request is allowed, or the milliseconds left in
  # the window when it is refused.
  defp hit(key, {limit, window_ms}, now) do
    [count, expires_at] =
      :ets.update_counter(@table, key, [{2, 1}, {3, 0}], {key, 0, now + window_ms})

    cond do
      expires_at <= now ->
        :ets.insert(@table, {key, 1, now + window_ms})
        nil

      count > limit ->
        expires_at - now

      true ->
        nil
    end
  end

  defp key(:email, email) when is_binary(email),
    do: :crypto.hash(:sha256, email |> String.trim() |> String.downcase())

  defp key(_kind, value), do: value

  defp limit(action, kind) do
    configured = get_in(config(), [:limits, action, kind])
    configured || get_in(@default_limits, [action, kind])
  end

  defp enabled?, do: Keyword.get(config(), :enabled, true)

  defp config, do: Application.get_env(:backend, __MODULE__) || []

  defp now_ms, do: System.monotonic_time(:millisecond)
end
