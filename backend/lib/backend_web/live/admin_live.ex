defmodule BackendWeb.AdminLive do
  @moduledoc """
  Placeholder admin page (issue #329): proves that LiveView, the root layout and
  the assets render. The admin case panel (#344) replaces it behind the `admin`
  role (ADR-015 #347). It calls no context and reads no data.
  """

  use BackendWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Painel administrativo")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Painel administrativo
        <:subtitle>A revisão de casos chega em breve.</:subtitle>
      </.header>

      <p id="admin-status" class="alert alert-success">
        <.icon name="hero-check-circle" class="size-5" /> Backend em funcionamento
      </p>
    </Layouts.app>
    """
  end
end
