defmodule BackendWeb.Plugs.SessionRateLimit do
  @moduledoc """
  Throttles a learner session route that calls a paid provider (#395), with
  `BackendWeb.RateLimit`, per session (the route's `:id`) and per learner (the
  device access token's user). Beyond either limit it halts with `429`, a
  `retry-after` header (seconds) and the JSON error `rate_limited`:

      pipeline :limit_session_message do
        plug BackendWeb.Plugs.SessionRateLimit, :session_message
      end

  Runs after `BackendWeb.Plugs.DeviceAuth` and `BackendWeb.Plugs.SessionOwner`,
  so another learner's session id is refused before it is counted. On the
  deprecated routes that stay unauthenticated in dev and test there is no
  learner, and only the session is counted.
  """

  @behaviour Plug

  alias BackendWeb.Plugs.RateLimit, as: RateLimitPlug
  alias BackendWeb.RateLimit

  @impl true
  def init(action) when is_atom(action), do: action

  @impl true
  def call(conn, action) do
    case RateLimit.check(action, session: conn.path_params["id"], learner: learner_id(conn)) do
      :ok ->
        conn

      {:error, :rate_limited, retry_after} ->
        RateLimitPlug.too_many_requests(
          conn,
          retry_after,
          "Muitas solicitações nesta sessão. Aguarde #{retry_after} s e tente novamente."
        )
    end
  end

  defp learner_id(%{assigns: %{current_scope: %{user: %{id: id}}}}), do: id
  defp learner_id(_conn), do: nil
end
