defmodule BackendWeb.UserLive.Legal do
  @moduledoc """
  The terms of use (`/termos`) and the privacy policy (`/privacidade`) a learner
  accepts at sign-up (#336), with their version. The texts are placeholders
  owned by `Backend.Accounts`.
  """

  use BackendWeb, :live_view

  alias Backend.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <article class="space-y-4">
        <.header>
          {@document.title}
          <:subtitle>Versão {@document.version}</:subtitle>
        </.header>

        <p :for={paragraph <- @document.paragraphs}>{paragraph}</p>

        <p>
          <.link navigate={~p"/users/register"} class="link">Voltar para criar conta</.link>
        </p>
      </article>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    document = Accounts.legal_document(socket.assigns.live_action)

    {:ok, assign(socket, document: document, page_title: document.title)}
  end
end
