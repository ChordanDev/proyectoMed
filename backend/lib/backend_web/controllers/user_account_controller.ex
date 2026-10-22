defmodule BackendWeb.UserAccountController do
  @moduledoc """
  Deletes the logged-in learner's account (#336) and ends the browser session.
  The settings page posts here once the learner typed their email; the check
  is repeated here, together with sudo mode.
  """

  use BackendWeb, :controller

  alias Backend.Accounts
  alias BackendWeb.UserAuth

  @confirmation_error "Digite o seu e-mail para confirmar a exclusão da conta."

  def delete(conn, params) do
    user = conn.assigns.current_scope.user
    typed_email = get_in(params, ["user", "email"])

    cond do
      not Accounts.sudo_mode?(user) ->
        conn
        |> put_flash(:error, "Entre novamente para excluir a sua conta.")
        |> redirect(to: ~p"/users/log-in")

      not Accounts.account_deletion_confirmed?(user, typed_email) ->
        conn
        |> put_flash(:error, @confirmation_error)
        |> redirect(to: ~p"/users/settings")

      true ->
        case Accounts.delete_user(user) do
          {:ok, expired_tokens} ->
            UserAuth.disconnect_sessions(expired_tokens)

            conn
            |> put_flash(:info, "Sua conta foi excluída.")
            |> UserAuth.log_out_user()

          {:error, :admin_account} ->
            conn
            |> put_flash(:error, "Contas de administrador não podem ser excluídas aqui.")
            |> redirect(to: ~p"/users/settings")
        end
    end
  end
end
