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
end
