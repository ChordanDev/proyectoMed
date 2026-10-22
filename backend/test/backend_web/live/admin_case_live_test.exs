defmodule BackendWeb.AdminCaseLiveTest do
  @moduledoc """
  The admin case panel (issue #331): rows inserted as n8n does appear in the
  list with their number, the list filters by status and area, and a case
  shows its located format errors at the top.
  """

  use BackendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Backend.AccountsFixtures

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
    %{conn: log_in_user(conn, admin_fixture())}
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
  end

  test "a student cannot open a case page" do
    conn = log_in_user(build_conn(), user_fixture())

    assert {:error, {:redirect, %{to: "/users/settings"}}} = live(conn, ~p"/admin/cases/1")
  end
end
