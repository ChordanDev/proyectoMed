defmodule BackendWeb.UserLive.ForgotPassword do
  @moduledoc """
  Password recovery (#336): asks for the email and sends a reset link without
  disclosing whether the email is registered (copy in pt-BR).
  """

  use BackendWeb, :live_view

  alias Backend.Accounts
  alias BackendWeb.RateLimit

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            Esqueceu a senha?
            <:subtitle>Enviaremos um link para redefinir a senha no seu e-mail.</:subtitle>
          </.header>
        </div>

        <.form for={@form} id="reset_password_form" phx-submit="send_email">
          <.input
            field={@form[:email]}
            type="email"
            label="E-mail"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.button phx-disable-with="Enviando..." class="btn btn-primary w-full">
            Enviar link para redefinir a senha
          </.button>
        </.form>

        <p class="text-center text-sm">
          <.link navigate={~p"/users/log-in"} class="link">Voltar para entrar</.link>
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: "user"), client_ip: session["client_ip"])}
  end

  @impl true
  def handle_event("send_email", %{"user" => %{"email" => email}}, socket) do
    # Reset emails are throttled per client IP and per email (#380).
    case RateLimit.check(:reset_password_email, ip: socket.assigns.client_ip, email: email) do
      :ok ->
        {:noreply, send_reset_link(socket, email)}

      {:error, :rate_limited, _retry_after} ->
        {:noreply, put_flash(socket, :error, RateLimit.flash_message())}
    end
  end

  defp send_reset_link(socket, email) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/users/reset-password/#{&1}")
      )
    end

    info =
      "Se o seu e-mail estiver cadastrado, você receberá em instantes um link para redefinir a senha."

    socket
    |> put_flash(:info, info)
    |> push_navigate(to: ~p"/users/log-in")
  end
end
