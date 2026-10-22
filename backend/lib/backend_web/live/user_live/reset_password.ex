defmodule BackendWeb.UserLive.ResetPassword do
  @moduledoc """
  Sets a new password from the emailed reset link (#336). Every session of the
  account is ended (copy in pt-BR).
  """

  use BackendWeb, :live_view

  alias Backend.Accounts
  alias BackendWeb.UserAuth

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>Redefinir a senha</.header>
        </div>

        <.form
          for={@form}
          id="new_password_form"
          phx-submit="reset_password"
          phx-change="validate"
        >
          <.input
            field={@form[:password]}
            type="password"
            label="Nova senha"
            autocomplete="new-password"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label="Confirme a nova senha"
            autocomplete="new-password"
            spellcheck="false"
            required
          />
          <.button phx-disable-with="Salvando..." class="btn btn-primary w-full">
            Redefinir a senha
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_reset_password_token(token) do
      changeset = Accounts.change_user_password(user, %{}, hash_password: false)
      {:ok, assign(socket, user: user, form: to_form(changeset))}
    else
      {:ok,
       socket
       |> put_flash(:error, "O link para redefinir a senha é inválido ou expirou.")
       |> redirect(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("reset_password", %{"user" => user_params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, user_params) do
      {:ok, {_user, expired_tokens}} ->
        UserAuth.disconnect_sessions(expired_tokens)

        {:noreply,
         socket
         |> put_flash(:info, "Senha redefinida. Entre com a nova senha.")
         |> redirect(to: ~p"/users/log-in")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      Accounts.change_user_password(socket.assigns.user, user_params, hash_password: false)

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end
end
