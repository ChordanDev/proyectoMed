defmodule BackendWeb.UserLive.Settings do
  @moduledoc """
  Account settings: change the email or the password (`mix phx.gen.auth`,
  copy in pt-BR) and, for a learner, delete the account (#336).
  """

  use BackendWeb, :live_view

  on_mount {BackendWeb.UserAuth, :require_sudo_mode}

  alias Backend.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="text-center">
        <.header>
          Configurações da conta
          <:subtitle>Altere o e-mail e a senha da sua conta</:subtitle>
        </.header>
      </div>

      <.form for={@email_form} id="email_form" phx-submit="update_email" phx-change="validate_email">
        <.input
          field={@email_form[:email]}
          type="email"
          label="E-mail"
          autocomplete="username"
          spellcheck="false"
          required
        />
        <.button variant="primary" phx-disable-with="Alterando...">Alterar e-mail</.button>
      </.form>

      <div class="divider" />

      <.form
        for={@password_form}
        id="password_form"
        action={~p"/users/update-password"}
        method="post"
        phx-change="validate_password"
        phx-submit="update_password"
        phx-trigger-action={@trigger_submit}
      >
        <input
          name={@password_form[:email].name}
          type="hidden"
          id="hidden_user_email"
          spellcheck="false"
          value={@current_email}
        />
        <.input
          field={@password_form[:password]}
          type="password"
          label="Nova senha"
          autocomplete="new-password"
          spellcheck="false"
          required
        />
        <.input
          field={@password_form[:password_confirmation]}
          type="password"
          label="Confirme a nova senha"
          autocomplete="new-password"
          spellcheck="false"
        />
        <.button variant="primary" phx-disable-with="Salvando...">
          Salvar senha
        </.button>
      </.form>

      <section :if={!@admin?} id="delete_account" class="space-y-2">
        <div class="divider" />
        <.header>
          Excluir conta
          <:subtitle>
            Apaga a sua conta e todos os seus dados de forma definitiva. Esta ação não pode ser desfeita.
          </:subtitle>
        </.header>

        <.form
          for={@delete_form}
          id="delete_account_form"
          action={~p"/users/delete-account"}
          method="post"
          phx-submit="delete_account"
          phx-trigger-action={@trigger_delete}
        >
          <.input
            field={@delete_form[:email]}
            id="delete_account_email"
            type="email"
            label="Digite o seu e-mail para confirmar"
            autocomplete="off"
            spellcheck="false"
            required
          />
          <p :if={@delete_error} class="mb-2 flex gap-2 items-center text-sm text-error">
            <.icon name="hero-exclamation-circle" class="size-5" />
            {@delete_error}
          </p>
          <.button class="btn btn-error w-full" phx-disable-with="Excluindo...">
            Excluir a minha conta
          </.button>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "E-mail alterado.")

        {:error, _} ->
          put_flash(socket, :error, "O link de alteração de e-mail é inválido ou expirou.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)
      |> assign(:admin?, Accounts.admin?(socket.assigns.current_scope))
      |> assign(:delete_form, to_form(%{"email" => ""}, as: "user"))
      |> assign(:delete_error, nil)
      |> assign(:trigger_delete, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "Enviamos um link para o novo endereço para confirmar a alteração do e-mail."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("delete_account", %{"user" => %{"email" => typed_email}}, socket) do
    user = socket.assigns.current_scope.user
    delete_form = to_form(%{"email" => typed_email}, as: "user")

    if Accounts.account_deletion_confirmed?(user, typed_email) do
      {:noreply,
       assign(socket, delete_form: delete_form, delete_error: nil, trigger_delete: true)}
    else
      {:noreply,
       assign(socket,
         delete_form: delete_form,
         delete_error: "Digite o seu e-mail para confirmar a exclusão da conta."
       )}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end
end
