defmodule BackendWeb.UserLive.Registration do
  @moduledoc """
  Learner sign-up (#336): the email and the acceptance of the terms of use and
  of the privacy policy. The account is confirmed through the emailed link; it
  is always a `student` account (copy in pt-BR).
  """

  use BackendWeb, :live_view

  alias Backend.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            Criar conta
            <:subtitle>
              Já tem uma conta?
              <.link navigate={~p"/users/log-in"} class="font-semibold text-brand hover:underline">
                Entre
              </.link>
            </:subtitle>
          </.header>
        </div>

        <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
          <.input
            field={@form[:email]}
            type="email"
            label="E-mail"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />

          <.acceptance field={@form[:terms_accepted]}>
            Li e aceito os
            <.link href={~p"/termos"} target="_blank" class="link">Termos de Uso</.link>
          </.acceptance>

          <.acceptance field={@form[:privacy_accepted]}>
            Li e aceito a
            <.link href={~p"/privacidade"} target="_blank" class="link">
              Política de Privacidade
            </.link>
          </.acceptance>

          <.button phx-disable-with="Criando a conta..." class="btn btn-primary w-full mt-2">
            Criar conta
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  slot :inner_block, required: true

  # A required checkbox whose label carries a link to the legal text, so it
  # cannot use the string label of `<.input type="checkbox">`.
  defp acceptance(assigns) do
    errors = if Phoenix.Component.used_input?(assigns.field), do: assigns.field.errors, else: []

    assigns =
      assigns
      |> assign(:errors, Enum.map(errors, &translate_error/1))
      |> assign(:checked, Phoenix.HTML.Form.normalize_value("checkbox", assigns.field.value))

    ~H"""
    <div class="fieldset mb-2">
      <label for={@field.id} class="label whitespace-normal">
        <input type="hidden" name={@field.name} value="false" />
        <input
          type="checkbox"
          id={@field.id}
          name={@field.name}
          value="true"
          checked={@checked}
          class="checkbox checkbox-sm"
        />
        <span>{render_slot(@inner_block)}</span>
      </label>
      <p :for={msg <- @errors} class="mt-1.5 flex gap-2 items-center text-sm text-error">
        <.icon name="hero-exclamation-circle" class="size-5" />
        {msg}
      </p>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%{}, validate_unique: false)

    {:ok, assign_form(socket, changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Enviamos um e-mail para #{user.email}. Acesse o link para confirmar a sua conta."
         )
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      Accounts.change_user_registration(user_params, validate_unique: false)

    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: "user"))
  end
end
