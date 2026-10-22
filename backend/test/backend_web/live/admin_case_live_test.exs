defmodule BackendWeb.AdminCaseLiveTest do
  @moduledoc """
  The admin case panel (issue #331): rows inserted as n8n does appear in the
  list with their number, the list filters by status and area, and a case
  shows its located format errors at the top.
  """

  use BackendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Backend.AccountsFixtures

  alias Backend.Content
  alias Backend.Repo

  @reference_case File.read!(
                    Path.expand("../../../priv/stations/acute-appendicitis/case.md", __DIR__)
                  )

  # Inserts a row exactly as the n8n Postgres node does (docs/case-format).
  defp insert_case!(area, theme, markdown, status \\ nil) do
    %{rows: [[number]]} =
      Repo.query!(
        "INSERT INTO cases (area, theme, markdown) VALUES ($1, $2, $3) RETURNING number",
        [area, theme, markdown]
      )

    if status, do: Repo.query!("UPDATE cases SET status = $1 WHERE number = $2", [status, number])

    number
  end

  setup %{conn: conn} do
    admin = admin_fixture()
    %{conn: log_in_user(conn, admin), admin: admin}
  end

  describe "case list" do
    test "a valid pending row appears with its sequential number", %{conn: conn} do
      number = insert_case!("Cirurgia Geral", "Apendicite aguda", @reference_case)
      next = insert_case!("Pediatria", "Bronquiolite", "[ESTAÇÃO x]")

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert next == number + 1
      assert has_element?(view, "#case-#{number}", "Cirurgia Geral")
      assert has_element?(view, "#case-#{number}", "Apendicite aguda")
      assert has_element?(view, "#case-#{number}", "Pendente")
      assert has_element?(view, "#case-#{number} a[href='/admin/cases/#{number}']", "#{number}")
      assert has_element?(view, "#case-#{next}", "Bronquiolite")
    end

    test "shows a message when there is no case", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#cases-empty", "Nenhum caso")
    end

    test "filters by status", %{conn: conn} do
      pending = insert_case!("Pediatria", "Asma", "x")
      approved = insert_case!("Pediatria", "Bronquiolite", "x", "approved")

      {:ok, view, _html} = live(conn, ~p"/admin")

      view |> form("#case-filters", %{"status" => "approved", "area" => ""}) |> render_change()

      assert_patch(view, ~p"/admin?status=approved")
      assert has_element?(view, "#case-#{approved}", "Aprovado")
      refute has_element?(view, "#case-#{pending}")
    end

    test "filters by area", %{conn: conn} do
      surgery = insert_case!("Cirurgia Geral", "Apendicite", "x")
      pediatrics = insert_case!("Pediatria", "Asma", "x")

      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#case-filters option[value='Pediatria']")

      view |> form("#case-filters", %{"status" => "", "area" => "Pediatria"}) |> render_change()

      assert_patch(view, ~p"/admin?area=Pediatria")
      assert has_element?(view, "#case-#{pediatrics}")
      refute has_element?(view, "#case-#{surgery}")
    end

    test "reads both filters from the URL", %{conn: conn} do
      match = insert_case!("Pediatria", "Asma", "x", "disapproved")
      insert_case!("Pediatria", "Bronquiolite", "x")
      insert_case!("Cirurgia Geral", "Apendicite", "x", "disapproved")

      {:ok, view, _html} = live(conn, ~p"/admin?status=disapproved&area=Pediatria")

      assert [_one] =
               view
               |> render()
               |> LazyHTML.from_fragment()
               |> LazyHTML.query("#cases tbody tr")
               |> Enum.to_list()

      assert has_element?(view, "#case-#{match}", "Reprovado")
    end
  end

  describe "case page" do
    test "an invalid case shows its located format errors at the top", %{conn: conn} do
      markdown = String.replace(@reference_case, "[TEMA] ", "[TEMAX] ", global: false)
      number = insert_case!("Cirurgia Geral", "Apendicite aguda", markdown)

      {:ok, view, html} = live(conn, ~p"/admin/cases/#{number}")

      assert has_element?(view, "#case-errors", "Erros de formato")
      assert has_element?(view, "#case-errors li", "Linha 1")
      assert has_element?(view, "#case-errors li", "missing [TEMA] tag")
      assert has_element?(view, "#case-errors a[href='#line-5']", "Linha 5")
      assert has_element?(view, "#line-5", "[TEMAX]")

      # The errors come before the case text.
      {errors_at, _} = :binary.match(html, "case-errors")
      {text_at, _} = :binary.match(html, "case-markdown")
      assert errors_at < text_at
    end

    test "a valid case says it has no format errors", %{conn: conn} do
      number = insert_case!("Cirurgia Geral", "Apendicite aguda", @reference_case)

      {:ok, view, _html} = live(conn, ~p"/admin/cases/#{number}")

      assert has_element?(view, "h1", "Caso #{number}")
      assert has_element?(view, "#case-meta", "Cirurgia Geral")
      assert has_element?(view, "#case-meta", "Apendicite aguda")
      assert has_element?(view, "#case-meta", "Pendente")
      assert has_element?(view, "#case-valid", "Sem erros de formato")
      refute has_element?(view, "#case-errors")
      assert has_element?(view, "#case-markdown", "[ESTAÇÃO acute-appendicitis]")
    end

    test "the list links to the case page", %{conn: conn} do
      number = insert_case!("Pediatria", "Asma", "sem tags")

      {:ok, view, _html} = live(conn, ~p"/admin")

      {:ok, case_view, _html} =
        view
        |> element("#case-#{number} a")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/cases/#{number}")

      assert has_element?(case_view, "#case-errors")
    end

    test "an unknown number goes back to the list with a message", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/admin", flash: %{"error" => message}}}} =
               live(conn, ~p"/admin/cases/999999")

      assert message =~ "não encontrado"
    end

    test "a number beyond the bigint range goes back to the list with a message", %{
      conn: conn
    } do
      assert {:error, {:live_redirect, %{to: "/admin", flash: %{"error" => message}}}} =
               live(conn, ~p"/admin/cases/99999999999999999999")

      assert message =~ "não encontrado"
    end
  end

  describe "editing a case (issue #332)" do
    defp save(view, markdown) do
      view |> form("#case-edit", %{"markdown" => markdown}) |> render_submit()
    end

    test "the editor holds the current Markdown", %{conn: conn} do
      number = insert_case!("Cirurgia Geral", "Apendicite aguda", @reference_case)

      {:ok, view, html} = live(conn, ~p"/admin/cases/#{number}")

      # The editor and the revisions come before the long numbered text.
      {editor_at, _} = :binary.match(html, "case-edit")
      {revisions_at, _} = :binary.match(html, "case-revisions")
      {text_at, _} = :binary.match(html, "case-markdown")
      assert editor_at < revisions_at
      assert revisions_at < text_at

      assert has_element?(
               view,
               "#case-edit textarea[name='markdown']",
               "[ESTAÇÃO acute-appendicitis]"
             )
    end

    test "saving a bad edit stores it and shows its located errors", %{conn: conn} do
      number = insert_case!("Cirurgia Geral", "Apendicite aguda", @reference_case)
      bad = String.replace(@reference_case, "[TEMA] ", "[TEMAX] ", global: false)

      {:ok, view, _html} = live(conn, ~p"/admin/cases/#{number}")
      assert has_element?(view, "#case-valid")

      save(view, bad)

      assert has_element?(view, "#flash-info", "Caso salvo")
      assert has_element?(view, "#case-errors li", "missing [TEMA] tag")
      assert has_element?(view, "#case-errors a[href='#line-5']", "Linha 5")
      assert has_element?(view, "#line-5", "[TEMAX]")
      refute has_element?(view, "#case-valid")
      assert Content.get_case_by_number(number).markdown == bad
    end

    test "saving a fix clears the errors", %{conn: conn} do
      bad = String.replace(@reference_case, "[TEMA] ", "[TEMAX] ", global: false)
      number = insert_case!("Cirurgia Geral", "Apendicite aguda", bad)

      {:ok, view, _html} = live(conn, ~p"/admin/cases/#{number}")
      assert has_element?(view, "#case-errors")

      save(view, @reference_case)

      assert has_element?(view, "#case-valid", "Sem erros de formato")
      refute has_element?(view, "#case-errors")
    end

    test "a stale save warns to reload and overwrites nothing", %{conn: conn} do
      number = insert_case!("Pediatria", "Asma", "v1")

      {:ok, view, _html} = live(conn, ~p"/admin/cases/#{number}")

      # Another admin saves the case after this page was opened.
      {:ok, _newer} =
        Content.update_case_markdown(
          Content.get_case_by_number(number),
          "v2 de outra",
          admin_fixture()
        )

      save(view, "v2 atrasada")

      assert has_element?(view, "#case-stale", "Este caso mudou")
      assert has_element?(view, "#case-stale", "recarregue")
      assert has_element?(view, "#case-stale a[href='/admin/cases/#{number}']")
      assert has_element?(view, "#case-edit textarea", "v2 atrasada")
      assert Content.get_case_by_number(number).markdown == "v2 de outra"
    end

    test "a blank save is refused", %{conn: conn} do
      number = insert_case!("Pediatria", "Asma", "v1")

      {:ok, view, _html} = live(conn, ~p"/admin/cases/#{number}")

      save(view, "  ")

      assert has_element?(view, "#flash-error", "não pode ficar vazio")
      assert Content.get_case_by_number(number).markdown == "v1"
    end

    test "previous versions are listed with editor and time", %{conn: conn, admin: admin} do
      number = insert_case!("Pediatria", "Asma", "primeira versão")

      {:ok, view, _html} = live(conn, ~p"/admin/cases/#{number}")
      assert has_element?(view, "#case-revisions-empty", "Nenhuma versão anterior")

      save(view, "segunda versão")
      save(view, "terceira versão")

      assert has_element?(view, "#revision-2", "Versão 2")
      assert has_element?(view, "#revision-2", admin.email)
      assert has_element?(view, "#revision-2 pre", "segunda versão")
      assert has_element?(view, "#revision-1 pre", "primeira versão")
      refute has_element?(view, "#case-revisions-empty")

      html = render(view)
      {newest, _} = :binary.match(html, "revision-2")
      {oldest, _} = :binary.match(html, "revision-1")
      assert newest < oldest
      assert html =~ ~r/\d{2}\/\d{2}\/\d{4} \d{2}:\d{2} UTC/
    end

    test "approve button is disabled when case has format errors (Story 15 / AC1)", %{conn: conn} do
      bad = String.replace(@reference_case, "[TEMA] ", "[TEMAX] ", global: false)
      number = insert_case!("Cirurgia Geral", "Apendicite aguda", bad)

      {:ok, view, _html} = live(conn, ~p"/admin/cases/#{number}")

      assert has_element?(view, "#case-approve[disabled]")
    end

    test "approving a valid case publishes it and records approver (Story 14, 19 / AC1, AC4)", %{
      conn: conn,
      admin: admin
    } do
      number = insert_case!("Cirurgia Geral", "Apendicite aguda", @reference_case)

      {:ok, view, _html} = live(conn, ~p"/admin/cases/#{number}")

      refute has_element?(view, "#case-approve[disabled]")
      assert has_element?(view, "#case-approve", "Aprovar")

      view |> element("#case-approve") |> render_click()

      assert has_element?(view, "#flash-info", "Caso aprovado e publicado")
      assert has_element?(view, "#case-meta", "Aprovado")
      assert has_element?(view, "#case-approval", admin.email)
      assert has_element?(view, "#station-version-1", "Versão publicada 1")
      assert has_element?(view, "#station-version-1", admin.email)

      # Persisted state
      kase = Content.get_case_by_number(number)
      assert kase.status == :approved
      assert kase.approved_by_id == admin.id
      assert kase.approved_by_email == admin.email
      assert kase.approved_at != nil

      [version] = Content.list_station_versions(kase)
      assert version.version_number == 1
      assert version.approved_by_id == admin.id
      assert version.approved_by_email == admin.email
    end

    test "disapproving hides case with one click without reason (Story 16 / AC2)", %{
      conn: conn,
      admin: admin
    } do
      number = insert_case!("Cirurgia Geral", "Apendicite aguda", @reference_case)
      kase = Content.get_case_by_number(number)
      {:ok, package} = Backend.Stations.parse_case(@reference_case)
      {:ok, _} = Content.approve_case(kase, package, admin)

      {:ok, view, _html} = live(conn, ~p"/admin/cases/#{number}")
      assert has_element?(view, "#case-meta", "Aprovado")
      assert has_element?(view, "#case-approval", admin.email)

      view |> element("#case-disapprove") |> render_click()

      assert has_element?(view, "#flash-info", "Caso reprovado")
      assert has_element?(view, "#case-meta", "Reprovado")
      refute has_element?(view, "#case-approval")

      reloaded = Content.get_case_by_number(number)
      assert reloaded.status == :disapproved
      refute has_element?(view, "#case-disapprove")
    end

    test "disapproving a pending case works with one click", %{conn: conn} do
      number = insert_case!("Pediatria", "Asma", "sem tags")

      {:ok, view, _html} = live(conn, ~p"/admin/cases/#{number}")
      assert has_element?(view, "#case-meta", "Pendente")

      view |> element("#case-disapprove") |> render_click()

      assert has_element?(view, "#flash-info", "Caso reprovado")
      assert has_element?(view, "#case-meta", "Reprovado")
      assert Content.get_case_by_number(number).status == :disapproved
    end

    test "re-approving after an edit creates a new immutable version (Story 18 / AC3)", %{
      conn: conn
    } do
      number = insert_case!("Cirurgia Geral", "Apendicite aguda", @reference_case)

      {:ok, view, _html} = live(conn, ~p"/admin/cases/#{number}")
      view |> element("#case-approve") |> render_click()

      # Edit the case
      edited =
        String.replace(
          @reference_case,
          "dor abdominal iniciada há cerca de 18 horas",
          "dor forte na fossa ilíaca direita há cerca de 18 horas"
        )

      save(view, edited)

      # Re-approve
      view |> element("#case-approve") |> render_click()

      assert has_element?(view, "#flash-info", "Caso aprovado e publicado")
      assert has_element?(view, "#station-version-2", "Versão publicada 2")
      assert has_element?(view, "#station-version-1", "Versão publicada 1")

      kase = Content.get_case_by_number(number)
      versions = Content.list_station_versions(kase)
      assert length(versions) == 2
      assert Enum.map(versions, & &1.version_number) == [2, 1]
    end

    test "attempting to approve with errors flashes error", %{conn: conn} do
      bad = String.replace(@reference_case, "[TEMA] ", "[TEMAX] ", global: false)
      number = insert_case!("Cirurgia Geral", "Apendicite aguda", bad)

      {:ok, view, _html} = live(conn, ~p"/admin/cases/#{number}")

      # Directly trigger approve event bypassing disabled button
      render_click(view, "approve")

      assert has_element?(view, "#flash-error", "erros de formato")
      assert Content.get_case_by_number(number).status == :pending
    end
  end

  describe "case index approver display (Story 19)" do
    test "shows who approved the case when approved, and dashes when disapproved", %{
      conn: conn,
      admin: admin
    } do
      number = insert_case!("Cirurgia Geral", "Apendicite aguda", @reference_case)
      kase = Content.get_case_by_number(number)
      {:ok, package} = Backend.Stations.parse_case(@reference_case)
      {:ok, approved} = Content.approve_case(kase, package, admin)

      {:ok, view, _html} = live(conn, ~p"/admin")
      assert has_element?(view, "#case-#{number}", admin.email)

      # When disapproved, approval attribution is hidden
      {:ok, _disapproved} = Content.disapprove_case(approved)
      {:ok, view2, _html} = live(conn, ~p"/admin")
      refute has_element?(view2, "#case-#{number}", admin.email)
    end
  end

  test "a student cannot open a case page" do
    conn = log_in_user(build_conn(), user_fixture())

    assert {:error, {:redirect, %{to: "/users/settings"}}} = live(conn, ~p"/admin/cases/1")
  end
end
