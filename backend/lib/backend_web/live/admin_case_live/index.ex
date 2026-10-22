defmodule BackendWeb.AdminCaseLive.Index do
  @moduledoc """
  Admin case list (issue #331, ADR-015 #347): number, area, theme and status
  of every case, filtered by status and area through the URL. Thin: it reads
  through `Backend.Content` only.
  """

  use BackendWeb, :live_view

  import BackendWeb.AdminCaseLive.Components

  alias Backend.Content

  @impl true
  def mount(_params, _session, socket) do
    status_options =
      Enum.map(Content.statuses(), &{status_label(&1), Atom.to_string(&1)})

    {:ok,
     assign(socket,
       page_title: "Casos",
       status_options: status_options,
       areas: Content.list_areas()
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      "status" => Map.get(params, "status", ""),
      "area" => Map.get(params, "area", "")
    }

    cases = Content.list_cases(status: filters["status"], area: filters["area"])

    {:noreply,
     assign(socket,
       cases: cases,
       filter_form: to_form(filters, as: :filters)
     )}
  end

  @impl true
  def handle_event("filter", params, socket) do
    query =
      params
      |> Map.take(["status", "area"])
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)

    {:noreply, push_patch(socket, to: ~p"/admin?#{query}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Casos
        <:subtitle>Casos gerados para revisão, por número.</:subtitle>
      </.header>

      <form id="case-filters" phx-change="filter" class="flex flex-wrap gap-4">
        <.input
          type="select"
          id="filter-status"
          name="status"
          label="Situação"
          value={@filter_form[:status].value}
          options={@status_options}
          prompt="Todas"
        />
        <.input
          type="select"
          id="filter-area"
          name="area"
          label="Área"
          value={@filter_form[:area].value}
          options={@areas}
          prompt="Todas"
        />
      </form>

      <p :if={@cases == []} id="cases-empty" class="mt-6 text-base-content/70">
        Nenhum caso encontrado.
      </p>

      <table :if={@cases != []} id="cases" class="table table-zebra mt-6">
        <thead>
          <tr>
            <th>Número</th>
            <th>Área</th>
            <th>Tema</th>
            <th>Situação</th>
            <th>Aprovado por</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={kase <- @cases} id={"case-#{kase.number}"}>
            <td>
              <.link navigate={~p"/admin/cases/#{kase.number}"} class="link font-semibold">
                {kase.number}
              </.link>
            </td>
            <td>{kase.area}</td>
            <td>{kase.theme}</td>
            <td><.status_badge status={kase.status} /></td>
            <td class="text-sm text-base-content/70">
              <span :if={kase.approved_by_email}>
                {kase.approved_by_email}
              </span>
              <span :if={!kase.approved_by_email}>—</span>
            </td>
          </tr>
        </tbody>
      </table>
    </Layouts.app>
    """
  end
end
