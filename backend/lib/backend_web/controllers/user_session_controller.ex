defmodule BackendWeb.UserSessionController do
  @moduledoc """
  Creates and deletes the browser session (`mix phx.gen.auth`, flash messages
  in pt-BR).
  """

  use BackendWeb, :controller

  alias Backend.Accounts
  alias BackendWeb.RateLimit
  alias BackendWeb.UserAuth

  def create(conn, %{"_action" => "confirmed"} = params) do
    throttled_create(conn, params, "Conta confirmada.")
  end

  def create(conn, params) do
    throttled_create(conn, params, "Boas-vindas de volta!")
  end

  # Password and link logins are throttled per client IP and per email (#380).
  defp throttled_create(conn, params, info) do
    case RateLimit.check(:login, ip: conn.remote_ip, email: login_email(params)) do
      :ok ->
        create(conn, params, info)

      {:error, :rate_limited, _retry_after} ->
        conn
        |> put_flash(:error, RateLimit.flash_message())
        |> redirect(to: ~p"/users/log-in")
    end
  end

  defp login_email(%{"user" => %{"token" => _token}}), do: nil
  defp login_email(%{"user" => %{"email" => email}}) when is_binary(email), do: email
  defp login_email(_params), do: nil

  # magic link login
  defp create(conn, %{"user" => %{"token" => token} = user_params}, info) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)

        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)

      _ ->
        conn
        |> put_flash(:error, "O link é inválido ou expirou.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  # email + password login
  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "E-mail ou senha inválidos")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/users/log-in")
    end
  end

  def update_password(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)
    {:ok, {_user, expired_tokens}} = Accounts.update_user_password(user, user_params)

    # disconnect all existing LiveViews with old sessions
    UserAuth.disconnect_sessions(expired_tokens)

    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Senha atualizada.")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Você saiu da sua conta.")
    |> UserAuth.log_out_user()
  end
end
