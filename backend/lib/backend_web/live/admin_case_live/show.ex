defmodule BackendWeb.AdminCaseLive.Show do
  @moduledoc """
  Admin case page (issue #331): number, area, theme and status, then the
  located format errors, then the case text with numbered lines.

  Errors are computed on read with `Backend.Stations.parse_case/1` and never
  stored (see `docs/case-format/README.md`): n8n inserts rows without passing
  through Phoenix, and stored errors would go stale when the parser or the case
  changes. `Backend.Content` calls no other context, so this LiveView composes
  the two public contexts.
  """

  use BackendWeb, :live_view

  import BackendWeb.AdminCaseLive.Components

  alias Backend.Content
  alias Backend.Stations

  @impl true
  def mount(%{"number" => number}, _session, socket) do
    case fetch_case(number) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Caso #{number} não encontrado.")
         |> push_navigate(to: ~p"/admin")}

      kase ->
        lines = String.split(kase.markdown, ~r/\r\n|\n/)

        {:ok,
         assign(socket,
           page_title: "Caso #{kase.number}",
           case: kase,
           errors: format_errors(kase.markdown),
           lines: Enum.with_index(lines, 1)
         )}
    end
  end

  defp fetch_case(number) do
    case Integer.parse(number) do
      {number, ""} -> Content.get_case_by_number(number)
      _invalid -> nil
    end
  end

  defp format_errors(markdown) do
    case Stations.parse_case(markdown) do
      {:ok, _package} -> []
      {:error, errors} -> errors
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.link navigate={~p"/admin"} class="link text-sm">← Casos</.link>

      <.header>
        Caso {@case.number}
        <:subtitle>
          <span id="case-meta" class="flex flex-wrap items-center gap-2">
            <span>{@case.area}</span>
            <span aria-hidden="true">·</span>
            <span>{@case.theme}</span>
            <.status_badge status={@case.status} />
          </span>
        </:subtitle>
      </.header>

      <section :if={@errors != []} id="case-errors" class="alert alert-error block" role="alert">
        <h2 class="font-semibold">Erros de formato ({length(@errors)})</h2>
        <p class="text-sm">Este caso não pode ser publicado enquanto houver erros.</p>
        <ul class="mt-2 list-disc pl-5">
          <li :for={error <- @errors}>
            <a href={"#line-#{error.line}"} class="link">Linha {error.line}</a>: {error.message}
          </li>
        </ul>
      </section>

      <p :if={@errors == []} id="case-valid" class="alert alert-success">
        <.icon name="hero-check-circle" class="size-5" /> Sem erros de formato.
      </p>

      <ol
        id="case-markdown"
        class="mt-6 overflow-x-auto rounded-box bg-base-200 p-4 font-mono text-sm"
      >
        <li :for={{line, number} <- @lines} id={"line-#{number}"} class="flex gap-4">
          <span class="w-10 shrink-0 select-none text-right text-base-content/50">{number}</span>
          <span class="whitespace-pre-wrap break-words">{line}</span>
        </li>
      </ol>
    </Layouts.app>
    """
  end
end
