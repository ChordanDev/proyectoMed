defmodule BackendWeb.UserLive.Login do
  @moduledoc """
  Login by email link or by password (`mix phx.gen.auth`, copy in pt-BR), with
  links to learner sign-up and password recovery (#336).
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
            <p>Entrar</p>
            <:subtitle :if={@current_scope}>
              Entre novamente para fazer alterações sensíveis na sua conta.
            </:subtitle>
            <:subtitle :if={!@current_scope}>
              Ainda não tem uma conta?
              <.link navigate={~p"/users/register"} class="font-semibold text-brand hover:underline">
                Crie a sua conta
              </.link>
            </:subtitle>
          </.header>
        </div>

        <div :if={local_mail_adapter?()} class="alert alert-info">
          <.icon name="hero-information-circle" class="size-6 shrink-0" />
          <div>
            <p>Os e-mails ficam no adaptador local de desenvolvimento.</p>
            <p>
              Veja os e-mails enviados na <.link href="/dev/mailbox" class="underline">caixa de entrada local</.link>.
            </p>
          </div>
        </div>

        <.form
          :let={f}
          for={@form}
          id="login_form_magic"
          action={~p"/users/log-in"}
          phx-submit="submit_magic"
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="E-mail"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.button class="btn btn-primary w-full">
            Entrar com um link por e-mail <span aria-hidden="true">→</span>
          </.button>
        </.form>

        <div class="divider">ou</div>

        <.form
          :let={f}
          for={@form}
          id="login_form_password"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="E-mail"
            autocomplete="username"
            spellcheck="false"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Senha"
            autocomplete="current-password"
            spellcheck="false"
          />
          <p class="mb-2 text-right text-sm">
            <.link navigate={~p"/users/reset-password"} class="link">Esqueceu a senha?</.link>
          </p>
          <.button class="btn btn-primary w-full" name={@form[:remember_me].name} value="true">
            Entrar e manter conectado <span aria-hidden="true">→</span>
          </.button>
          <.button class="btn btn-primary btn-soft w-full mt-2">
            Entrar só desta vez
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false, client_ip: session["client_ip"])}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    # Login-link emails are throttled per client IP and per email (#380).
    case RateLimit.check(:magic_link_email, ip: socket.assigns.client_ip, email: email) do
      :ok ->
        {:noreply, send_login_link(socket, email)}

      {:error, :rate_limited, _retry_after} ->
        {:noreply, put_flash(socket, :error, RateLimit.flash_message())}
    end
  end

  defp send_login_link(socket, email) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      "Se o seu e-mail estiver cadastrado, você receberá em instantes um link para entrar."

    socket
    |> put_flash(:info, info)
    |> push_navigate(to: ~p"/users/log-in")
  end

  defp local_mail_adapter? do
    Application.get_env(:backend, :dev_routes, false) and
      Application.get_env(:backend, Backend.Accounts.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
