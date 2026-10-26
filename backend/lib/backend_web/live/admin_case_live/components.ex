defmodule BackendWeb.AdminCaseLive.Components do
  @moduledoc """
  Small pieces shared by the admin case list and case page (issue #331).
  """

  use Phoenix.Component

  @labels %{pending: "Pendente", approved: "Aprovado", disapproved: "Reprovado"}
  @classes %{pending: "badge-warning", approved: "badge-success", disapproved: "badge-error"}

  @doc "The pt-BR label of a review status."
  @spec status_label(atom()) :: String.t()
  def status_label(status), do: Map.fetch!(@labels, status)

  @doc "A badge with the pt-BR label of a review status."
  attr :status, :atom, required: true

  def status_badge(assigns) do
    assigns = assign(assigns, :class, Map.fetch!(@classes, assigns.status))

    ~H"""
    <span class={["badge badge-soft", @class]}>{status_label(@status)}</span>
    """
  end
end
