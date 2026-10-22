defmodule BackendWeb.AdminCaseLive.Show do
  @moduledoc """
  Admin case page (issue #331): number, area, theme and status, then the
  located format errors, then the case text with numbered lines.

  Admins edit the Markdown in place (issue #332). Each save goes through
  `Backend.Content.update_case_markdown/3`, which refuses a save over a newer
  version (optimistic lock) and keeps the replaced Markdown as a revision; the
  page then re-parses the saved Markdown and lists the revisions.

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
        {:ok,
         socket
         |> assign(page_title: "Caso #{kase.number}", stale: false)
         |> assign_case(kase)}
    end
  end

  defp assign_case(socket, kase) do
    lines = String.split(kase.markdown, ~r/\r\n|\n/)

    assign(socket,
      case: kase,
      draft: kase.markdown,
      errors: format_errors(kase.markdown),
      lines: Enum.with_index(lines, 1),
      revisions: Content.list_case_revisions(kase),
      station_versions: Content.list_station_versions(kase)
    )
  end

  # Case numbers are a Postgres bigint; anything outside that range cannot
  # exist and would make Postgrex raise while encoding the query.
  @max_bigint 9_223_372_036_854_775_807

  defp fetch_case(number) do
    case Integer.parse(number) do
      {number, ""} when number in 1..@max_bigint -> Content.get_case_by_number(number)
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
  def handle_event("approve", _params, socket) do
    case Stations.parse_case(socket.assigns.case.markdown) do
      {:ok, package} ->
        approver = socket.assigns.current_scope.user

        case Content.approve_case(socket.assigns.case, package, approver) do
          {:ok, saved} ->
            {:noreply,
             socket
             |> assign(stale: false)
             |> assign_case(saved)
             |> put_flash(:info, "Caso aprovado e publicado.")}

          {:error, :stale} ->
            {:noreply, assign(socket, stale: true)}

          {:error, :invalid_case} ->
            {:noreply,
             put_flash(socket, :error, "Este caso tem erros de formato e não pode ser aprovado.")}
        end

      {:error, _errors} ->
        {:noreply,
         put_flash(socket, :error, "Este caso tem erros de formato e não pode ser aprovado.")}
    end
  end

  @impl true
  def handle_event("disapprove", _params, socket) do
    case Content.disapprove_case(socket.assigns.case) do
      {:ok, saved} ->
        {:noreply,
         socket
         |> assign(stale: false)
         |> assign_case(saved)
         |> put_flash(:info, "Caso reprovado.")}

      {:error, :stale} ->
        {:noreply, assign(socket, stale: true)}
    end
  end

  @impl true
  def handle_event("save", %{"markdown" => markdown}, socket) do
    editor = socket.assigns.current_scope.user

    case Content.update_case_markdown(socket.assigns.case, markdown, editor) do
      {:ok, saved} ->
        {:noreply,
         socket
         |> assign_case(saved)
         |> put_flash(:info, saved_message(saved, socket.assigns.case))}

      {:error, :stale} ->
        {:noreply, assign(socket, stale: true, draft: markdown)}

      {:error, %Ecto.Changeset{}} ->
        {:noreply,
         socket
         |> assign(draft: markdown)
         |> put_flash(:error, "O texto do caso não pode ficar vazio.")}
    end
  end

  defp saved_message(%{lock_version: same}, %{lock_version: same}), do: "Nenhuma alteração."
  defp saved_message(_saved, _before), do: "Caso salvo."

  defp format_time(datetime), do: Calendar.strftime(datetime, "%d/%m/%Y %H:%M UTC")

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
          <span
            :if={@case.approved_by_email && @case.approved_at}
            id="case-approval"
            class="mt-1 block text-sm text-base-content/70"
          >
            Aprovado por {@case.approved_by_email} em {format_time(@case.approved_at)}
          </span>
        </:subtitle>
      </.header>

      <section id="case-review-actions" class="mt-4 flex flex-wrap gap-2">
        <button
          id="case-approve"
          type="button"
          phx-click="approve"
          disabled={@errors != []}
          class="btn btn-success btn-sm"
        >
          <.icon name="hero-check" class="size-4" /> Aprovar e publicar
        </button>
        <button
          :if={@case.status != :disapproved}
          id="case-disapprove"
          type="button"
          phx-click="disapprove"
          class="btn btn-outline btn-error btn-sm"
        >
          <.icon name="hero-x-mark" class="size-4" /> Reprovar
        </button>
      </section>

      <section :if={@errors != []} id="case-errors" class="alert alert-error mt-4 block" role="alert">
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

      <section
        :if={@stale}
        id="case-stale"
        class="alert alert-warning mt-4 block"
        role="alert"
      >
        <p class="font-semibold">
          Este caso mudou desde que você o abriu: recarregue a página antes de salvar.
        </p>
        <p class="text-sm">
          Outro administrador salvou uma versão mais nova, e o seu texto não foi salvo.
          Copie o seu texto do editor antes de recarregar.
        </p>
        <.link navigate={~p"/admin/cases/#{@case.number}"} class="btn btn-sm mt-2">
          Recarregar
        </.link>
      </section>

      <section id="case-editor" class="mt-6">
        <h2 class="text-lg font-semibold">Editar caso</h2>
        <p class="text-sm text-base-content/70">
          Ao salvar, o caso é validado de novo e a versão anterior fica guardada.
        </p>
        <form id="case-edit" phx-submit="save" class="mt-2">
          <textarea
            id="case-edit-markdown"
            name="markdown"
            rows="24"
            spellcheck="false"
            class="textarea w-full font-mono text-sm"
            aria-label="Texto do caso"
          >{@draft}</textarea>
          <button type="submit" class="btn btn-primary mt-2" phx-disable-with="Salvando...">
            Salvar
          </button>
        </form>
      </section>

      <section id="case-revisions" class="mt-8">
        <h2 class="text-lg font-semibold">Versões anteriores ({length(@revisions)})</h2>
        <p :if={@revisions == []} id="case-revisions-empty" class="text-sm text-base-content/70">
          Nenhuma versão anterior.
        </p>
        <ul :if={@revisions != []} class="mt-2 space-y-2">
          <li :for={revision <- @revisions} id={"revision-#{revision.lock_version}"}>
            <details class="rounded-box bg-base-200 p-3">
              <summary class="cursor-pointer">
                <span class="font-semibold">Versão {revision.lock_version}</span>
                — substituída por {revision.editor_email} em {format_time(revision.inserted_at)}
              </summary>
              <pre class="mt-2 overflow-x-auto whitespace-pre-wrap break-words font-mono text-sm">{revision.markdown}</pre>
            </details>
          </li>
        </ul>
      </section>

      <section id="case-station-versions" class="mt-8">
        <h2 class="text-lg font-semibold">Versões publicadas ({length(@station_versions)})</h2>
        <p
          :if={@station_versions == []}
          id="case-station-versions-empty"
          class="text-sm text-base-content/70"
        >
          Nenhuma versão publicada.
        </p>
        <ul :if={@station_versions != []} class="mt-2 space-y-2">
          <li
            :for={version <- @station_versions}
            id={"station-version-#{version.version_number}"}
            class="rounded-box bg-base-200 p-3 text-sm"
          >
            <span class="font-semibold">Versão publicada {version.version_number}</span>
            — aprovada por {version.approved_by_email} em {format_time(version.approved_at)}
          </li>
        </ul>
      </section>

      <h2 class="mt-8 text-lg font-semibold">Texto salvo</h2>
      <ol
        id="case-markdown"
        class="mt-2 overflow-x-auto rounded-box bg-base-200 p-4 font-mono text-sm"
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
