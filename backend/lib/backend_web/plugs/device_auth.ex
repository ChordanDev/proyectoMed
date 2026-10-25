defmodule BackendWeb.Plugs.DeviceAuth do
  @moduledoc """
  Bearer authentication of the Unreal client (#337): requires an
  `Authorization: Bearer <access_token>` header carrying a valid device access
  token, and assigns the learner's `:current_scope`. A missing token answers
  `401 missing_token`; an unknown, expired or revoked one `401 invalid_token`.
  """

  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Backend.Accounts
  alias Backend.Accounts.Scope

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case bearer_token(conn) do
      nil ->
        unauthorized(conn, "missing_token", "Faça login no aplicativo para continuar.")

      token ->
        case Accounts.get_user_by_device_access_token(token) do
          nil ->
            unauthorized(
              conn,
              "invalid_token",
              "Sessão do aplicativo inválida ou expirada: faça login novamente."
            )

          user ->
            conn
            |> assign(:current_scope, Scope.for_user(user))
            |> assign(:device_access_token, token)
        end
    end
  end

  defp bearer_token(conn) do
    with [header | _] <- get_req_header(conn, "authorization"),
         [scheme, token] <- String.split(header, " ", parts: 2),
         "bearer" <- String.downcase(scheme),
         token when token != "" <- String.trim(token) do
      token
    else
      _ -> nil
    end
  end

  defp unauthorized(conn, code, message) do
    conn
    |> put_resp_header("www-authenticate", ~s(Bearer error="#{code}"))
    |> put_status(:unauthorized)
    |> json(%{error: code, message: message})
    |> halt()
  end
end
