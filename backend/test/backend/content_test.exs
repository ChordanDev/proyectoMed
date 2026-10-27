defmodule Backend.ContentTest do
  @moduledoc """
  The Content context reads the cases that n8n inserts as pending rows
  (issue #331, ADR-014 #346). Rows are inserted with plain SQL, exactly as the
  n8n Postgres node does (see `docs/case-format/README.md`).
  """

  use Backend.DataCase, async: true

  alias Backend.Content
  alias Backend.Stations

  @reference_case File.read!(
                    Path.expand("../../priv/stations/acute-appendicitis/case.md", __DIR__)
                  )

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

    test "numbers increase in insertion order" do
      first = insert_case!("Pediatria", "Bronquiolite")
      second = insert_case!("Pediatria", "Asma")

      # The identity sequence is shared by concurrent (async) tests and is not
      # rolled back, so another test may take the numbers in between: only the
      # order is guaranteed, not the gap (issue #381).
      assert second.number > first.number
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

  describe "approving and publishing a case (issue #333)" do
    setup do
      admin = Backend.AccountsFixtures.admin_fixture()
      {:ok, valid_package} = Stations.parse_case(@reference_case)
      %{admin: admin, package: valid_package}
    end

    test "approving publishes an immutable StationVersion, sets approval metadata, and updates status",
         %{admin: admin, package: package} do
      kase = insert_case!("Cirurgia Geral", "Apendicite aguda", @reference_case)

      assert {:ok, approved} = Content.approve_case(kase, package, admin)

      assert approved.status == :approved
      assert approved.approved_by_id == admin.id
      assert approved.approved_by_email == admin.email
      assert %DateTime{} = approved.approved_at
      assert approved.lock_version == 2

      # Re-fetch from DB
      reloaded = Content.get_case!(kase.id)
      assert reloaded.status == :approved
      assert reloaded.approved_by_id == admin.id
      assert reloaded.approved_by_email == admin.email
      assert reloaded.approved_at == approved.approved_at

      # Immutable station_versions record created
      assert [version] = Content.list_station_versions(approved)
      assert version.case_id == kase.id
      assert version.case_revision_id == nil
      assert version.version_number == 1
      assert version.station_id == "acute-appendicitis"
      assert version.area == package["area"]
      assert version.theme == package["theme"]
      assert version.markdown == @reference_case
      assert version.package == package
      assert version.approved_by_id == admin.id
      assert version.approved_by_email == admin.email
      assert version.approved_at == approved.approved_at
      assert %DateTime{} = version.inserted_at

      assert Content.get_station_version!(version.id).id == version.id
      assert Content.get_station_version(version.id).id == version.id
      assert Content.get_station_version(-1) == nil
    end

    test "approve accepts either {:ok, package} or a valid package map",
         %{admin: admin, package: package} do
      kase1 = insert_case!("Cirurgia Geral", "Apendicite 1", @reference_case)
      assert {:ok, _} = Content.approve_case(kase1, {:ok, package}, admin)

      kase2 = insert_case!("Cirurgia Geral", "Apendicite 2", @reference_case)
      assert {:ok, _} = Content.approve_case(kase2, package, admin)
    end

    test "approve refuses a case with parser errors or invalid package without modifying the case",
         %{admin: admin} do
      kase = insert_case!("Cirurgia Geral", "Apendicite", "markdown invalido")

      # With {:error, _} tuple from Stations.parse_case/1
      parse_result = Stations.parse_case("markdown invalido")
      assert {:error, _errors} = parse_result
      assert {:error, :invalid_case} = Content.approve_case(kase, parse_result, admin)

      # With an invalid map or nil
      assert {:error, :invalid_case} = Content.approve_case(kase, %{"station_id" => "x"}, admin)
      assert {:error, :invalid_case} = Content.approve_case(kase, nil, admin)

      unchanged = Content.get_case!(kase.id)
      assert unchanged.status == :pending
      assert unchanged.approved_by_id == nil
      assert unchanged.approved_at == nil
      assert Content.list_station_versions(unchanged) == []
    end

    test "approve on a stale case returns {:error, :stale}",
         %{admin: admin, package: package} do
      kase = insert_case!("Cirurgia Geral", "Apendicite", @reference_case)
      {:ok, _updated} = Content.update_case_markdown(kase, @reference_case <> "\n", admin)

      # Attempting to approve using the original kase with older lock_version
      assert {:error, :stale} = Content.approve_case(kase, package, admin)

      current = Content.get_case!(kase.id)
      assert current.status == :pending
      assert Content.list_station_versions(current) == []
    end

    test "re-approving after an edit creates a new immutable version referencing its revision and leaves the previous version untouched",
         %{admin: admin, package: package} do
      kase = insert_case!("Cirurgia Geral", "Apendicite", @reference_case)
      {:ok, v1_case} = Content.approve_case(kase, package, admin)
      assert [v1_version] = Content.list_station_versions(v1_case)

      # Admin edits the case
      other_admin = Backend.AccountsFixtures.admin_fixture()
      edited_markdown = @reference_case <> "\n# Just a comment"
      {:ok, edited_case} = Content.update_case_markdown(v1_case, edited_markdown, other_admin)
      assert [revision] = Content.list_case_revisions(edited_case)

      # Admin approves edited case
      {:ok, edited_package} = Stations.parse_case(edited_markdown)
      {:ok, v2_case} = Content.approve_case(edited_case, edited_package, other_admin)

      assert v2_case.status == :approved
      assert v2_case.approved_by_id == other_admin.id
      assert v2_case.approved_by_email == other_admin.email

      # Both versions are preserved; newest first
      assert [v2_version, v1_version_reloaded] = Content.list_station_versions(v2_case)
      assert v2_version.version_number == 2
      assert v2_version.case_revision_id == revision.id
      assert v2_version.markdown == edited_markdown
      assert v2_version.approved_by_email == other_admin.email

      # Previous version is completely unchanged
      assert v1_version_reloaded.id == v1_version.id
      assert v1_version_reloaded.version_number == 1
      assert v1_version_reloaded.markdown == @reference_case
      assert v1_version_reloaded.approved_by_email == admin.email
    end

    test "approving an already approved case with unchanged markdown is an idempotent no-op",
         %{admin: admin, package: package} do
      kase = insert_case!("Cirurgia Geral", "Apendicite", @reference_case)
      {:ok, approved} = Content.approve_case(kase, package, admin)
      assert approved.lock_version == 2
      assert length(Content.list_station_versions(approved)) == 1

      # Re-approving without any markdown changes
      assert {:ok, same} = Content.approve_case(approved, package, admin)
      assert same.lock_version == 2
      assert length(Content.list_station_versions(same)) == 1
    end

    test "disapproving transitions case to :disapproved, clears approval metadata, and respects optimistic locking",
         %{admin: admin, package: package} do
      kase = insert_case!("Cirurgia Geral", "Apendicite", @reference_case)
      {:ok, approved} = Content.approve_case(kase, package, admin)

      assert {:ok, disapproved} = Content.disapprove_case(approved)
      assert disapproved.status == :disapproved
      assert disapproved.approved_by_id == nil
      assert disapproved.approved_by_email == nil
      assert disapproved.approved_at == nil

      reloaded = Content.get_case!(kase.id)
      assert reloaded.status == :disapproved
      assert reloaded.approved_by_id == nil
      assert reloaded.approved_by_email == nil
      assert reloaded.approved_at == nil

      # Attempting to disapprove with stale struct
      assert {:error, :stale} = Content.disapprove_case(approved)
    end

    test "deleting a case cascades to its station versions",
         %{admin: admin, package: package} do
      kase = insert_case!("Cirurgia Geral", "Apendicite", @reference_case)
      {:ok, approved} = Content.approve_case(kase, package, admin)

      assert length(Content.list_station_versions(approved)) == 1

      Repo.query!("DELETE FROM cases WHERE id = $1", [kase.id])
      assert Repo.all(Backend.Content.StationVersion) == []
    end

    test "deleting an admin user nilifies approved_by_id while keeping approved_by_email",
         %{admin: admin, package: package} do
      kase = insert_case!("Cirurgia Geral", "Apendicite", @reference_case)
      {:ok, approved} = Content.approve_case(kase, package, admin)
      [version] = Content.list_station_versions(approved)

      # Delete the admin user via plain SQL (simulate admin deletion)
      Repo.query!("DELETE FROM users WHERE id = $1", [admin.id])

      reloaded_case = Content.get_case!(kase.id)
      assert reloaded_case.approved_by_id == nil
      assert reloaded_case.approved_by_email == admin.email

      reloaded_version = Content.get_station_version!(version.id)
      assert reloaded_version.approved_by_id == nil
      assert reloaded_version.approved_by_email == admin.email
    end
  end

  describe "catalog of published stations (issue #333)" do
    setup do
      admin = Backend.AccountsFixtures.admin_fixture()
      {:ok, package} = Stations.parse_case(@reference_case)
      %{admin: admin, package: package}
    end

    test "Content.list_published_stations/0 lists latest versions of approved cases in number order, hiding pending and disapproved",
         %{admin: admin, package: package} do
      # Case 1: approved
      case1 = insert_case!("Cirurgia Geral", "Apendicite", @reference_case)
      {:ok, _approved1} = Content.approve_case(case1, package, admin)

      # Case 2: pending (should NOT appear)
      _pending = insert_case!("Pediatria", "Bronquiolite", @reference_case)

      # Case 3: approved, then disapproved (should NOT appear)
      case3 = insert_case!("Ginecologia", "Sangramento", @reference_case)
      {:ok, approved3} = Content.approve_case(case3, package, admin)
      {:ok, _disapproved3} = Content.disapprove_case(approved3)

      # Case 4: approved, edited, and approved again (v2 should appear, not v1)
      case4 = insert_case!("Clínica Médica", "Cefaleia", @reference_case)
      {:ok, approved4_v1} = Content.approve_case(case4, package, admin)
      {:ok, edited4} = Content.update_case_markdown(approved4_v1, @reference_case <> "\n", admin)
      {:ok, package4_v2} = Stations.parse_case(edited4.markdown)
      {:ok, _approved4_v2} = Content.approve_case(edited4, package4_v2, admin)

      published = Content.list_published_stations()
      assert Enum.map(published, & &1.case_id) == [case1.id, case4.id]
      assert Enum.map(published, & &1.version_number) == [1, 2]
    end

    test "Content.list_published_stations/0 keeps two approved cases that share one [ESTAÇÃO] slug",
         %{admin: admin, package: package} do
      case1 = insert_case!("Cirurgia Geral", "Apendicite", @reference_case)
      case2 = insert_case!("Cirurgia Geral", "Apendicite (variante)", @reference_case)
      {:ok, _} = Content.approve_case(case1, package, admin)
      {:ok, _} = Content.approve_case(case2, package, admin)

      published = Content.list_published_stations()

      assert Enum.map(published, & &1.case_id) == [case1.id, case2.id]
      assert Enum.map(published, & &1.station_id) == ["acute-appendicitis", "acute-appendicitis"]

      catalog = Stations.list_catalog_stations()

      assert Enum.map(catalog, & &1["id"]) == [case1.number, case2.number]
      assert Enum.map(catalog, & &1["slug"]) == ["acute-appendicitis", "acute-appendicitis"]
      assert Enum.map(catalog, & &1["version"]) == [1, 1]
    end

    test "Stations.list_catalog_stations/0 projects catalog items without examiner secrets",
         %{admin: admin, package: package} do
      case1 = insert_case!("Cirurgia Geral", "Apendicite", @reference_case)
      {:ok, _} = Content.approve_case(case1, package, admin)

      [catalog_item] = Stations.list_catalog_stations()

      assert catalog_item["id"] == case1.number
      assert catalog_item["version"] == 1
      assert catalog_item["slug"] == "acute-appendicitis"
      assert catalog_item["area"] == package["area"]
      assert catalog_item["theme"] == package["theme"]
      assert is_list(catalog_item["actors"])
      assert length(catalog_item["actors"]) == length(package["actors"])

      for actor <- catalog_item["actors"] do
        # Only public actor fields are exposed
        assert Map.keys(actor) |> Enum.sort() == ["age", "id", "name", "role", "voice"]
        # Secrets / examiner-only details are stripped
        refute Map.has_key?(actor, "fact_ids")
        refute Map.has_key?(actor, "explicit_fact_ids")
        refute Map.has_key?(actor, "mandatory_question_ids")
        refute Map.has_key?(actor, "persona")
        refute Map.has_key?(actor, "tone")
        refute Map.has_key?(actor, "presenting_context")
      end
    end
  end

  describe "picking a published station for a session (issue #334)" do
    setup do
      admin = Backend.AccountsFixtures.admin_fixture()
      {:ok, package} = Stations.parse_case(@reference_case)
      %{admin: admin, package: package}
    end

    defp publish!(package, admin, area) do
      kase = insert_case!(area, "Tema", @reference_case)
      {:ok, approved} = Content.approve_case(kase, Map.put(package, "area", area), admin)
      approved
    end

    test "get_published_station/1 returns the latest approved version of a case number",
         %{admin: admin, package: package} do
      approved = publish!(package, admin, "Cirurgia Geral")
      {:ok, edited} = Content.update_case_markdown(approved, @reference_case <> "\n", admin)
      {:ok, _v2} = Content.approve_case(edited, package, admin)

      version = Content.get_published_station(approved.number)

      assert version.case.number == approved.number
      assert version.version_number == 2
      assert version.package["station_id"] == "acute-appendicitis"
    end

    test "get_published_station/1 returns nil for an unknown, pending or disapproved case",
         %{admin: admin, package: package} do
      pending = insert_case!("Pediatria", "Bronquiolite", @reference_case)
      disapproved = publish!(package, admin, "Ginecologia")
      {:ok, _} = Content.disapprove_case(disapproved)

      assert Content.get_published_station(pending.number) == nil
      assert Content.get_published_station(disapproved.number) == nil
      assert Content.get_published_station(999_999) == nil
    end

    test "random_published_station/1 draws only published versions within the area",
         %{admin: admin, package: package} do
      surgery = publish!(package, admin, "Cirurgia Geral")
      pediatrics = publish!(package, admin, "Pediatria")
      _pending = insert_case!("Pediatria", "Pendente", @reference_case)

      for _ <- 1..10 do
        assert Content.random_published_station("Pediatria").case_id == pediatrics.id
        assert Content.random_published_station("Cirurgia Geral").case_id == surgery.id
      end

      drawn = MapSet.new(1..40, fn _ -> Content.random_published_station(nil).case_id end)
      assert MapSet.subset?(drawn, MapSet.new([surgery.id, pediatrics.id]))
      assert MapSet.size(drawn) == 2
    end

    test "random_published_station/1 returns nil when the area has no published station",
         %{admin: admin, package: package} do
      disapproved = publish!(package, admin, "Ginecologia")
      {:ok, _} = Content.disapprove_case(disapproved)

      assert Content.random_published_station("Ginecologia") == nil
      assert Content.random_published_station("Área inexistente") == nil
      assert Content.random_published_station(nil) == nil
    end

    test "random_published_station/1 draws the latest version of a re-published case",
         %{admin: admin, package: package} do
      approved = publish!(package, admin, "Cirurgia Geral")
      {:ok, edited} = Content.update_case_markdown(approved, @reference_case <> "\n", admin)
      {:ok, _v2} = Content.approve_case(edited, package, admin)

      assert Content.random_published_station("Cirurgia Geral").version_number == 2
    end
  end
end
