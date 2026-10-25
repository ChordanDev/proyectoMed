defmodule BackendWeb.DeviceController do
  @moduledoc """
  The device login API of the Unreal client (#337, RFC 8628 shape). The client
  starts a login, shows the user code and the verification URI, and polls
  until the learner approves it in the browser (`BackendWeb.DeviceLive`).
  Errors answer `400` with an RFC 8628 / RFC 6749 `error` code.
  """

  use BackendWeb, :controller

  alias Backend.Accounts

  def start(conn, _params) do
    {:ok, start} = Accounts.start_device_authorization()

    json(conn, %{
      device_code: start.device_code,
      user_code: start.user_code,
      verification_uri: url(~p"/device"),
      verification_uri_complete: url(~p"/device?#{[user_code: start.user_code]}"),
      interval: start.interval,
      expires_in: start.expires_in
    })
  end

  def token(conn, params) do
    case Accounts.poll_device_authorization(params["device_code"]) do
      {:ok, tokens} -> tokens_json(conn, tokens)
      {:error, reason} -> grant_error(conn, reason)
    end
  end

  def refresh(conn, params) do
    case Accounts.refresh_device_token(params["refresh_token"]) do
      {:ok, tokens} -> tokens_json(conn, tokens)
      {:error, reason} -> grant_error(conn, reason)
    end
  end

  # Behind `BackendWeb.Plugs.DeviceAuth`: the access token is valid.
  def logout(conn, params) do
    :ok =
      if params["everywhere"] in [true, "true"],
        do: Accounts.revoke_all_device_tokens(conn.assigns.current_scope.user),
        else: Accounts.revoke_device_token(conn.assigns.device_access_token)

    send_resp(conn, :no_content, "")
  end

  defp tokens_json(conn, tokens) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> json(tokens)
  end

  defp grant_error(conn, reason) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(:bad_request)
    |> json(%{error: Atom.to_string(reason), message: message(reason)})
  end

  defp message(:authorization_pending), do: "Aguardando a confirmação no navegador."
  defp message(:slow_down), do: "Aguarde mais entre as consultas."
  defp message(:expired_token), do: "O código expirou: inicie o login novamente."
  defp message(:access_denied), do: "O acesso foi negado no navegador."
  defp message(:invalid_grant), do: "Credencial inválida: inicie o login novamente."
end
