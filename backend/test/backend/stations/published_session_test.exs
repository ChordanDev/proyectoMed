defmodule Backend.Stations.PublishedSessionTest do
  @moduledoc """
  Sessions start on a published Station version from the database and pin it
  (issue #334, ADR-013 amendment on #209): every session operation reads the
  pinned package, never the file loader's active station.
  """

  # Session state lives in the shared Conversation table: not async.
  use Backend.DataCase, async: false

  alias Backend.Content
  alias Backend.Stations

  @reference_case File.read!(
                    Path.expand("../../../priv/stations/acute-appendicitis/case.md", __DIR__)
                  )
  @imaging_request "Solicito uma ultrassonografia de abdome"
  @imaging_impresso "impresso-3-exame-de-imagem"

  setup do
    admin = Backend.AccountsFixtures.admin_fixture()
    {:ok, package} = Stations.parse_case(@reference_case)
    %{admin: admin, package: package}
  end

  defp publish!(package, admin, area \\ "Cirurgia Geral") do
    %{rows: [[id]]} =
      Repo.query!(
        "INSERT INTO cases (area, theme, markdown) VALUES ($1, $2, $3) RETURNING id",
        [area, "Tema", @reference_case]
      )

    {:ok, approved} =
      Content.approve_case(Content.get_case!(id), Map.put(package, "area", area), admin)

    approved
  end

  describe "start_station_session/2" do
    test "starts a session on the latest published version of a case number",
         %{admin: admin, package: package} do
      kase = publish!(package, admin)

      assert {:ok, session} =
               Stations.start_station_session({:station, kase.number}, %{audio_consent: true})

      assert session.station_id == kase.number
      assert session.station_version == 1
      assert session.station_slug == "acute-appendicitis"
      assert session.station_area == "Cirurgia Geral"
      assert session.audio_consent == true
      assert session.status == :active
      assert {:ok, ^session} = Stations.get_session(session.session_id)
    end

    test "draws a random published station within an area", %{admin: admin, package: package} do
      _surgery = publish!(package, admin, "Cirurgia Geral")
      pediatrics = publish!(package, admin, "Pediatria")

      assert {:ok, session} =
               Stations.start_station_session({:random, "Pediatria"}, %{audio_consent: false})

      assert session.station_id == pediatrics.number
      assert session.station_area == "Pediatria"
    end

    test "draws a random published station from any area", %{admin: admin, package: package} do
      kase = publish!(package, admin, "Pediatria")

      assert {:ok, session} = Stations.start_station_session({:random, nil}, %{})
      assert session.station_id == kase.number
      assert session.audio_consent == false
    end

    test "an unknown, pending or disapproved case number is station_not_found",
         %{admin: admin, package: package} do
      disapproved = publish!(package, admin)
      {:ok, _} = Content.disapprove_case(disapproved)

      assert {:error, :station_not_found} =
               Stations.start_station_session({:station, 999_999}, %{})

      assert {:error, :station_not_found} =
               Stations.start_station_session({:station, disapproved.number}, %{})
    end

    test "an area without a published station is no_published_station",
         %{admin: admin, package: package} do
      _surgery = publish!(package, admin, "Cirurgia Geral")

      assert {:error, :no_published_station} =
               Stations.start_station_session({:random, "Pediatria"}, %{})

      Repo.query!("DELETE FROM cases")
      assert {:error, :no_published_station} = Stations.start_station_session({:random, nil}, %{})
    end
  end

  describe "a session pins its Station version" do
    test "re-publishing the case changes neither the version nor the package of a running session",
         %{admin: admin, package: package} do
      kase = publish!(package, admin)
      {:ok, pinned} = Stations.start_station_session({:station, kase.number}, %{})

      # Version 2 no longer releases the imaging impresso on request.
      {:ok, edited} = Content.update_case_markdown(kase, @reference_case <> "\n", admin)

      v2_package =
        Map.update!(package, "impressos", fn impressos ->
          Enum.map(impressos, fn
            %{"id" => @imaging_impresso} = impresso -> Map.put(impresso, "keywords", [])
            impresso -> impresso
          end)
        end)

      {:ok, _} = Content.approve_case(edited, v2_package, admin)
      {:ok, fresh} = Stations.start_station_session({:station, kase.number}, %{})

      assert fresh.station_version == 2
      assert {:ok, %{station_version: 1}} = Stations.get_session(pinned.session_id)

      assert {:ok, %{decision: "released", newly_released: [%{id: @imaging_impresso}]}} =
               Stations.request_impresso(pinned.session_id, %{"text" => @imaging_request})

      assert {:ok, %{decision: "unavailable"}} =
               Stations.request_impresso(fresh.session_id, %{"text" => @imaging_request})
    end

    test "impressos, the voice worker context and results read the pinned package",
         %{admin: admin, package: package} do
      kase = publish!(package, admin)

      {:ok, session} =
        Stations.start_station_session({:station, kase.number}, %{audio_consent: true})

      # The file loader's active station (chest pain) has no abdominal imaging.
      refute Enum.any?(
               Stations.get_active_package()["impressos"] || [],
               &(&1["id"] == @imaging_impresso)
             )

      assert {:ok, %{newly_released: [%{id: @imaging_impresso}]}} =
               Stations.request_impresso(session.session_id, %{"text" => @imaging_request})

      assert {:ok, %{released_impressos: [%{id: @imaging_impresso}]}} =
               Stations.list_impressos(session.session_id)

      assert {:ok, context} = Stations.voice_worker_context(session.session_id)
      assert context.language == "pt-BR"
      assert "apendicite" in Enum.map(context.keyterms, &String.downcase/1)

      {:ok, _} = Stations.complete_session(session.session_id, :user)
      {:ok, result} = Stations.get_session_result(session.session_id)

      assert Enum.map(result.criteria, & &1.id) == Enum.map(package["rubric"], & &1["id"])
    end

    test "a released impresso grades the impresso-only criterion of the pinned package",
         %{admin: admin, package: package} do
      # A criterion graded only by the released imaging impresso: no transcript
      # message mentions it, so impresso evidence alone can make it met.
      imaging_criterion =
        package["rubric"]
        |> List.last()
        |> Map.merge(%{
          "id" => "item-imaging-impresso",
          "order" => length(package["rubric"]) + 1,
          "impresso_ids" => [@imaging_impresso]
        })

      kase = publish!(Map.update!(package, "rubric", &(&1 ++ [imaging_criterion])), admin)
      {:ok, session} = Stations.start_station_session({:station, kase.number}, %{})

      assert {:ok, %{newly_released: [%{id: @imaging_impresso}]}} =
               Stations.request_impresso(session.session_id, %{"text" => @imaging_request})

      {:ok, played} = Stations.get_session(session.session_id)

      %{criteria: criteria} = Backend.Stations.Evaluator.evaluate(played.package, played)
      graded = Enum.find(criteria, &(&1.id == imaging_criterion["id"]))

      assert graded.status == :met
      assert Enum.any?(graded.evidence, &(&1.role == :impresso))

      {:ok, _} = Stations.complete_session(session.session_id, :user)
      {:ok, result} = Stations.get_session_result(session.session_id)

      assert %{status: "met"} = Enum.find(result.criteria, &(&1.id == imaging_criterion["id"]))
    end

    test "a released impresso of a pinned session is verified rubric evidence",
         %{admin: admin, package: package} do
      kase = publish!(package, admin)
      {:ok, session} = Stations.start_station_session({:station, kase.number}, %{})

      assert {:ok, %{newly_released: [%{id: @imaging_impresso}]}} =
               Stations.request_impresso(session.session_id, %{"text" => @imaging_request})

      {:ok, played} = Stations.get_session(session.session_id)

      assert [%{provenance: :impressos, released_ids: [@imaging_impresso]}] =
               played
               |> Backend.Stations.RubricAssessment.Evidence.build(played.package)
               |> Enum.filter(&(&1.kind == :impresso_event))

      # Graded against another package, the pinned version number proves nothing.
      assert [%{provenance: :unverified}] =
               played
               |> Backend.Stations.RubricAssessment.Evidence.build(
                 Map.put(package, "id", "other")
               )
               |> Enum.filter(&(&1.kind == :impresso_event))
    end
  end
end
