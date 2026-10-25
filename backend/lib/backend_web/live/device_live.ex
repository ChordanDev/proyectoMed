defmodule BackendWeb.DeviceLive do
  @moduledoc """
  The browser page of the device login (#337): a logged-in learner types or
  follows the user code shown by the Unreal client, checks it, and approves
  or denies the login. Admin accounts may not use the device flow.
  """

  use BackendWeb, :live_view

  alias Backend.Accounts
  alias BackendWeb.RateLimit

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-6">
        <.header>
          Entrar no aplicativo
          <:subtitle>Confirme o código exibido no aplicativo da estação.</:subtitle>
        </.header>

        <div :if={@step == :admin} class="alert alert-warning" id="device-admin">
          <.icon name="hero-exclamation-triangle" class="size-6 shrink-0" />
          <p>Contas de administrador não podem entrar no aplicativo.</p>
        </div>

        <.form
          :if={@step == :enter}
          for={@form}
          id="device-code-form"
          phx-submit="lookup"
        >
          <.input
            field={@form[:user_code]}
            type="text"
            label="Código do aplicativo"
            placeholder="XXXX-XXXX"
            autocomplete="off"
            spellcheck="false"
            required
          />
          <p :if={@invalid?} class="mb-2 text-sm text-error" id="device-code-error">
            Código inválido ou expirado. Confira o código no aplicativo.
          </p>
          <.button class="btn btn-primary w-full">Continuar</.button>
        </.form>

        <div :if={@step == :confirm} class="space-y-4" id="device-confirm">
          <p>
            O aplicativo está pedindo acesso à conta <strong>{@current_scope.user.email}</strong>.
          </p>
          <p>Confira se este é o código exibido no aplicativo:</p>
          <p class="text-center font-mono text-3xl font-bold tracking-widest" id="device-user-code">
            {@user_code}
          </p>
          <div class="flex gap-2">
            <.button id="device-deny" phx-click="deny" class="btn btn-ghost flex-1">Negar</.button>
            <.button id="device-approve" phx-click="approve" class="btn btn-primary flex-1">
              Autorizar
            </.button>
          </div>
        </div>

        <div :if={@step == :approved} class="alert alert-success" id="device-approved">
          <.icon name="hero-check-circle" class="size-6 shrink-0" />
          <p>Pronto! Volte ao aplicativo para continuar.</p>
        </div>

        <div :if={@step == :denied} class="alert alert-info" id="device-denied">
          <.icon name="hero-information-circle" class="size-6 shrink-0" />
          <p>Acesso negado. O aplicativo não entrou na sua conta.</p>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       step: :enter,
       user_code: nil,
       invalid?: false,
       form: code_form(""),
       client_ip: session["client_ip"]
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    cond do
      Accounts.admin?(socket.assigns.current_scope) ->
        {:noreply, assign(socket, step: :admin)}

      is_binary(params["user_code"]) ->
        {:noreply, lookup(socket, params["user_code"])}

      true ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("lookup", %{"device" => %{"user_code" => user_code}}, socket) do
    {:noreply, lookup(socket, user_code)}
  end

  def handle_event("approve", _params, socket), do: decide(socket, :approve)
  def handle_event("deny", _params, socket), do: decide(socket, :deny)

  defp lookup(%{assigns: %{step: step}} = socket, _user_code) when step not in [:enter],
    do: socket

  # User-code lookups are throttled per client IP and per learner (#380), so
  # nobody can enumerate the codes of pending logins.
  defp lookup(socket, user_code) do
    keys = [ip: socket.assigns.client_ip, user: socket.assigns.current_scope.user.id]

    case RateLimit.check(:device_lookup, keys) do
      :ok ->
        check_code(socket, user_code)

      {:error, :rate_limited, _retry_after} ->
        socket
        |> put_flash(:error, RateLimit.flash_message())
        |> assign(invalid?: false, form: code_form(user_code))
    end
  end

  defp check_code(socket, user_code) do
    if Accounts.pending_device_authorization?(user_code) do
      assign(socket, step: :confirm, user_code: display_code(user_code), invalid?: false)
    else
      assign(socket, invalid?: true, form: code_form(user_code))
    end
  end

  defp decide(%{assigns: %{step: :confirm, user_code: user_code}} = socket, decision) do
    user = socket.assigns.current_scope.user

    result =
      case decision do
        :approve -> Accounts.approve_device_authorization(user, user_code)
        :deny -> Accounts.deny_device_authorization(user, user_code)
      end

    case {result, decision} do
      {:ok, :approve} ->
        {:noreply, assign(socket, step: :approved)}

      {:ok, :deny} ->
        {:noreply, assign(socket, step: :denied)}

      {{:error, :admin_account}, _decision} ->
        {:noreply, assign(socket, step: :admin)}

      {{:error, :invalid_code}, _decision} ->
        {:noreply, assign(socket, step: :enter, invalid?: true, form: code_form(user_code))}
    end
  end

  defp decide(socket, _decision), do: {:noreply, socket}

  defp code_form(user_code), do: to_form(%{"user_code" => user_code}, as: :device)

  defp display_code(user_code) do
    case user_code |> String.upcase() |> String.replace(~r/[^A-Z]/, "") do
      <<first::binary-size(4), second::binary-size(4)>> -> first <> "-" <> second
      other -> other
    end
  end
end
