defmodule Backend.ContentTest do
  @moduledoc """
  The Content context reads the cases that n8n inserts as pending rows
  (issue #331, ADR-014 #346). Rows are inserted with plain SQL, exactly as the
  n8n Postgres node does (see `docs/case-format/README.md`).
  """

  use Backend.DataCase, async: true

  alias Backend.Content

  defp insert_case!(area, theme, markdown \\ "# caso") do
    %{rows: [[id]]} =
      Repo.query!(
        "INSERT INTO cases (area, theme, markdown) VALUES ($1, $2, $3) RETURNING id",
        [area, theme, markdown]
      )

    Content.get_case!(id)
  end

  describe "the n8n insert contract" do
    test "a row with only area, theme and markdown is a pending case with a number" do
      kase = insert_case!("Cirurgia Geral", "Apendicite aguda", "[ESTAÇÃO x]")

      assert kase.status == :pending
      assert kase.area == "Cirurgia Geral"
      assert kase.theme == "Apendicite aguda"
      assert kase.markdown == "[ESTAÇÃO x]"
      assert is_integer(kase.number) and kase.number > 0
      assert %DateTime{} = kase.inserted_at
      assert %DateTime{} = kase.updated_at
      # Defaults are UTC whatever the server time zone is.
      assert abs(DateTime.diff(kase.inserted_at, DateTime.utc_now())) < 60
    end

    test "numbers are sequential in insertion order" do
      first = insert_case!("Pediatria", "Bronquiolite")
      second = insert_case!("Pediatria", "Asma")

      assert second.number == first.number + 1
    end

    test "n8n cannot choose the number" do
      assert_raise Postgrex.Error,
                   ~r/cannot insert a non-DEFAULT value into column "number"/,
                   fn ->
                     Repo.query!(
                       "INSERT INTO cases (number, area, theme, markdown) VALUES (7, 'a', 'b', 'c')"
                     )
                   end
    end

    test "an unknown status is refused" do
      assert_raise Postgrex.Error, ~r/cases_status_check/, fn ->
        Repo.query!(
          "INSERT INTO cases (area, theme, markdown, status) VALUES ('a', 'b', 'c', 'published')"
        )
      end
    end

    test "area, theme and markdown are required" do
      assert_raise Postgrex.Error, ~r/not-null/, fn ->
        Repo.query!("INSERT INTO cases (area, theme) VALUES ('a', 'b')")
      end
    end
  end

  describe "list_cases/1" do
    setup do
      pending = insert_case!("Pediatria", "Bronquiolite")
      approved = insert_case!("Cirurgia Geral", "Apendicite")
      Repo.query!("UPDATE cases SET status = 'approved' WHERE id = $1", [approved.id])
      %{pending: pending, approved: Content.get_case!(approved.id)}
    end

    test "lists every case by number without filters", %{pending: p, approved: a} do
      assert Enum.map(Content.list_cases(), & &1.number) == [p.number, a.number]
    end

    test "filters by status", %{pending: p, approved: a} do
      assert [%{id: id}] = Content.list_cases(status: "pending")
      assert id == p.id
      assert [%{id: id}] = Content.list_cases(status: "approved")
      assert id == a.id
      assert [] = Content.list_cases(status: "disapproved")
    end

    test "filters by area", %{approved: a} do
      assert [%{id: id}] = Content.list_cases(area: "Cirurgia Geral")
      assert id == a.id
    end

    test "combines filters and ignores blank or unknown ones", %{pending: p} do
      assert [%{id: id}] = Content.list_cases(status: "pending", area: "Pediatria")
      assert id == p.id
      assert [] = Content.list_cases(status: "approved", area: "Pediatria")
      assert length(Content.list_cases(status: "", area: "")) == 2
      assert length(Content.list_cases(status: "published")) == 2
    end
  end

  test "list_areas/0 returns the distinct areas in alphabetical order" do
    insert_case!("Pediatria", "Asma")
    insert_case!("Cirurgia Geral", "Apendicite")
    insert_case!("Pediatria", "Bronquiolite")

    assert Content.list_areas() == ["Cirurgia Geral", "Pediatria"]
  end

  test "get_case_by_number/1 finds a case by its human number" do
    kase = insert_case!("Pediatria", "Asma")

    assert Content.get_case_by_number(kase.number).id == kase.id
    assert Content.get_case_by_number(kase.number + 1000) == nil
  end

  test "statuses/0 lists the review statuses in order" do
    assert Content.statuses() == [:pending, :approved, :disapproved]
  end

  describe "editing a case (issue #332)" do
    setup do
      %{editor: Backend.AccountsFixtures.admin_fixture()}
    end

    test "a row inserted by n8n starts at lock version 1" do
      assert insert_case!("Pediatria", "Asma").lock_version == 1
    end

    test "saving replaces the Markdown and keeps the previous one as a revision", %{
      editor: editor
    } do
      kase = insert_case!("Pediatria", "Asma", "versão 1")

      assert {:ok, saved} = Content.update_case_markdown(kase, "versão 2", editor)

      assert saved.markdown == "versão 2"
      assert saved.lock_version == 2
      assert Content.get_case!(kase.id).markdown == "versão 2"

      assert [revision] = Content.list_case_revisions(saved)
      assert revision.markdown == "versão 1"
      assert revision.lock_version == 1
      assert revision.editor_id == editor.id
      assert revision.editor_email == editor.email
      assert %DateTime{} = revision.inserted_at
    end

    test "every save keeps its previous Markdown, newest first", %{editor: editor} do
      other = Backend.AccountsFixtures.admin_fixture()
      kase = insert_case!("Pediatria", "Asma", "v1")

      {:ok, kase} = Content.update_case_markdown(kase, "v2", editor)
      {:ok, kase} = Content.update_case_markdown(kase, "v3", other)

      assert kase.lock_version == 3

      assert [%{markdown: "v2", editor_email: second}, %{markdown: "v1", editor_email: first}] =
               Content.list_case_revisions(kase)

      assert second == other.email
      assert first == editor.email
    end

    test "a save over a newer version is rejected and overwrites nothing", %{editor: editor} do
      kase = insert_case!("Pediatria", "Asma", "v1")
      {:ok, _newer} = Content.update_case_markdown(kase, "v2 de outra pessoa", editor)

      assert {:error, :stale} = Content.update_case_markdown(kase, "v2 atrasada", editor)

      current = Content.get_case!(kase.id)
      assert current.markdown == "v2 de outra pessoa"
      assert current.lock_version == 2
      assert [%{markdown: "v1"}] = Content.list_case_revisions(current)
    end

    test "saving the same Markdown changes nothing and keeps no revision", %{editor: editor} do
      kase = insert_case!("Pediatria", "Asma", "v1")

      assert {:ok, same} = Content.update_case_markdown(kase, "v1", editor)

      assert same.lock_version == 1
      assert Content.list_case_revisions(same) == []
    end

    test "blank Markdown is refused", %{editor: editor} do
      kase = insert_case!("Pediatria", "Asma", "v1")

      assert {:error, %Ecto.Changeset{} = changeset} =
               Content.update_case_markdown(kase, "   ", editor)

      assert %{markdown: [_message]} = errors_on(changeset)
      assert Content.get_case!(kase.id).markdown == "v1"
      assert Content.list_case_revisions(kase) == []
    end

    test "saving keeps the review status, area and theme", %{editor: editor} do
      kase = insert_case!("Pediatria", "Asma", "v1")
      Repo.query!("UPDATE cases SET status = 'approved' WHERE id = $1", [kase.id])
      kase = Content.get_case!(kase.id)

      {:ok, saved} = Content.update_case_markdown(kase, "v2", editor)

      assert saved.status == :approved
      assert saved.area == "Pediatria"
      assert saved.theme == "Asma"
    end

    test "deleting a case deletes its revisions", %{editor: editor} do
      kase = insert_case!("Pediatria", "Asma", "v1")
      {:ok, kase} = Content.update_case_markdown(kase, "v2", editor)

      Repo.query!("DELETE FROM cases WHERE id = $1", [kase.id])

      assert %{rows: [[0]]} = Repo.query!("SELECT count(*) FROM case_revisions")
    end
  end
end
