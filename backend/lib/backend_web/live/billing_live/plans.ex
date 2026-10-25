defmodule BackendWeb.BillingLive.Plans do
  @moduledoc """
  The plan page (#339): each plan links to its RevenueCat Web Purchase Link
  carrying the learner's app_user_id and email (research A7). RevenueCat runs
  checkout with Stripe Billing and returns the learner to `/conta`.
  """

  use BackendWeb, :live_view

  alias Backend.Billing

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Planos
        <:subtitle>Escolha como pagar o acesso ao simulador.</:subtitle>
      </.header>

      <p :if={@status.state in [:active, :cancelled]} id="already-subscribed" class="alert alert-info">
        Você já tem uma assinatura ativa.
        <.link navigate={~p"/conta"} class="link">Ver minha conta</.link>
      </p>

      <ul class="space-y-4">
        <li :for={plan <- @plans} class="card card-border">
          <div class="card-body">
            <h2 class="card-title">{plan.name}</h2>
            <p>{description(plan.payment)}</p>
            <div class="card-actions justify-end">
              <a :if={plan.url} id={"plan-#{plan.payment}"} href={plan.url} class="btn btn-primary">
                Assinar
              </a>
              <span :if={!plan.url} class="text-sm opacity-70">Compra indisponível no momento.</span>
            </div>
          </div>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    plans =
      for plan <- Billing.plans() do
        Map.put(plan, :url, Billing.purchase_url(plan, user))
      end

    {:ok, assign(socket, plans: plans, status: Billing.subscription_status(user))}
  end

  defp description(:card),
    do: "Pagamento com cartão de crédito, com renovação automática a cada mês."

  defp description(:pix),
    do:
      "Pagamento por Pix a cada mês. A renovação não é automática: avisamos antes do vencimento."
end
