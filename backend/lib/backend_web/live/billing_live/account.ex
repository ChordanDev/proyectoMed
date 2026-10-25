defmodule BackendWeb.BillingLive.Account do
  @moduledoc """
  The account page (#339): the learner's subscription, with the plan, the
  renewal date of a card plan or the due date of a Pix plan, a reminder when a
  Pix payment is due soon, and the state of a cancelled or expired
  subscription. It is also the success page of the Web Purchase Link.

  With access, it also shows today's remaining simulations of the plan's daily
  quota and when the quota resets (#340).
  """

  use BackendWeb, :live_view

  alias Backend.Billing
  alias Backend.Stations

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Minha conta
        <:subtitle>{@current_scope.user.email}</:subtitle>
        <:actions>
          <.link navigate={~p"/users/settings"} class="btn btn-ghost btn-sm">Configurações</.link>
        </:actions>
      </.header>

      <div :if={@status.renewal_reminder?} id="pix-reminder" role="alert" class="alert alert-warning">
        <span>
          Sua assinatura Pix vence em {date(@status.expires_at)}. Pague a renovação para não perder o acesso.
        </span>
        <a :if={@pix_url} href={@pix_url} class="btn btn-sm">Renovar com Pix</a>
      </div>

      <section id="subscription" class="card card-border">
        <div class="card-body space-y-2">
          <h2 class="card-title">Assinatura</h2>

          <%= case @status.state do %>
            <% :none -> %>
              <p>Você ainda não tem uma assinatura.</p>
              <.link navigate={~p"/planos"} class="btn btn-primary">Ver planos</.link>
            <% :expired -> %>
              <p>
                Assinatura expirada<span :if={@status.expires_at}> em {date(@status.expires_at)}</span>.
              </p>
              <.link navigate={~p"/planos"} class="btn btn-primary">Assinar novamente</.link>
            <% state -> %>
              <dl class="grid grid-cols-2 gap-2">
                <dt class="font-semibold">Plano</dt>
                <dd>{plan_name(@status)}</dd>
                <dt class="font-semibold">Pagamento</dt>
                <dd>{payment(@status.plan)}</dd>
                <dt class="font-semibold">Situação</dt>
                <dd>{situation(state, @status)}</dd>
              </dl>
          <% end %>
        </div>
      </section>

      <section :if={@quota} id="daily-quota" class="card card-border">
        <div class="card-body space-y-2">
          <h2 class="card-title">Simulações de hoje</h2>
          <p class="text-lg font-semibold">
            {@quota.remaining} de {@quota.daily_quota} simulações restantes hoje
          </p>
          <p :if={@quota.remaining == 0}>Você usou todas as simulações de hoje.</p>
          <p class="text-sm opacity-70">A cota renova à meia-noite (horário de Brasília).</p>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    status = Billing.subscription_status(user)

    pix_url =
      if status.renewal_reminder?, do: Billing.purchase_url(status.plan, user), else: nil

    quota =
      if status.state in [:active, :cancelled], do: Stations.daily_quota_status(user.id)

    {:ok, assign(socket, status: status, pix_url: pix_url, quota: quota)}
  end

  defp plan_name(%{plan: %{name: name}}), do: name
  defp plan_name(%{product_id: product_id}), do: product_id

  defp payment(%{payment: :pix}), do: "Pix (pagamento manual a cada mês)"
  defp payment(%{payment: :card}), do: "Cartão (renovação automática)"
  defp payment(_plan), do: "—"

  defp situation(:cancelled, status), do: "Cancelada: acesso até #{date(status.expires_at)}"

  defp situation(:active, %{auto_renews?: true} = status),
    do: "Ativa. Renova automaticamente em #{date(status.expires_at)}"

  defp situation(:active, status), do: "Ativa. Vence em #{date(status.expires_at)}"

  # Dates are shown in UTC, day first.
  defp date(%DateTime{} = at), do: Calendar.strftime(at, "%d/%m/%Y")
end
