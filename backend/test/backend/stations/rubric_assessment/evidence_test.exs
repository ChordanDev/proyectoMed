defmodule Backend.Stations.RubricAssessment.EvidenceTest do
  use ExUnit.Case, async: true

  alias Backend.Stations.RubricAssessment.Evidence

  @stations_path Path.expand("../../../../priv/stations", __DIR__)
  @categories ~w(physical_exam laboratory imaging report)

  @t0 ~U[2026-01-10 12:00:00.000000Z]
  @t1 ~U[2026-01-10 12:00:01.000000Z]
  @t2 ~U[2026-01-10 12:00:02.000000Z]
  @t3 ~U[2026-01-10 12:00:03.000000Z]
  @t4 ~U[2026-01-10 12:00:04.000000Z]

  defp package(relative_path) do
    @stations_path
    |> Path.join(relative_path)
    |> File.read!()
    |> Jason.decode!()
  end

  # Authors one impresso per category.
  defp chest_pain, do: package("chest-pain-initial-assessment/package.json")

  # Authors no impresso.
  defp no_impressos, do: package("fixtures/valid-package-v2.json")

  defp turn(role, text, at, modality \\ :text) do
    %{role: role, modality: modality, text: text, at: at}
  end

  defp event(request_id, order, released_ids, at, overrides \\ %{}) do
    Map.merge(
      %{
        request_id: request_id,
        station_id: "chest-pain-initial-assessment",
        station_version: "2.0.0",
        order: order,
        text: "request #{request_id}",
        matched_ids: released_ids,
        decision: :released,
        released_ids: released_ids,
        at: at
      },
      overrides
    )
  end

  defp session(messages, impresso_requests) do
    %{messages: messages, impresso_requests: impresso_requests}
  end

  # turn-1 learner (text), turn-2 patient, impresso-req-lab, turn-3 learner
  # (voice), impresso-req-ecg, impresso-req-stale (wrong version),
  # impresso-req-ghost (unauthored id), impresso-req-none (released nothing).
  defp rich_pool do
    messages = [
      turn(:learner, "Quando começou a dor?", @t0),
      turn(:patient, "Começou há duas horas.", @t1),
      turn(:learner, "A dor irradia?", @t3, :voice)
    ]

    events = [
      event("req-lab", 1, ["laboratorio-sangue-enzimas"], @t2),
      event("req-ecg", 2, ["laudo-eletrocardiograma"], @t4),
      event("req-stale", 3, ["exame-fisico-geral"], @t4, %{station_version: "1.0.0"}),
      event("req-ghost", 4, ["not-authored"], @t4),
      event("req-none", 5, [], @t4, %{decision: :unavailable})
    ]

    Evidence.build(session(messages, events), chest_pain())
  end

  defp requirement(modality), do: Evidence.requirement(%{"modality_requirement" => modality})

  describe "build/2 identifiers and items" do
    test "derives turn ids from the 1-based message index and keeps role and modality" do
      pool =
        Evidence.build(
          session([turn(:learner, "Olá", @t0), turn(:patient, "Oi", @t1, :voice)], []),
          chest_pain()
        )

      assert [
               %{
                 id: "turn-1",
                 kind: :turn,
                 role: :learner,
                 channel: :text,
                 provenance: :transcript,
                 text: "Olá",
                 at: @t0,
                 released_ids: [],
                 categories: []
               },
               %{id: "turn-2", kind: :turn, role: :patient, channel: :voice, text: "Oi"}
             ] = pool
    end

    test "derives event ids from the request id and labels released categories" do
      pool =
        Evidence.build(
          session([], [event("req-lab", 1, ["laboratorio-sangue-enzimas"], @t0)]),
          chest_pain()
        )

      assert [
               %{
                 id: "impresso-req-lab",
                 kind: :impresso_event,
                 role: :learner,
                 channel: :impressos,
                 provenance: :impressos,
                 text: "request req-lab",
                 at: @t0,
                 released_ids: ["laboratorio-sangue-enzimas"],
                 categories: ["laboratory"]
               }
             ] = pool
    end

    test "is deterministic for the same session and package" do
      assert rich_pool() == rich_pool()
    end

    test "keeps an event from another station version in the pool as unverified" do
      pool = rich_pool()

      assert %{provenance: :unverified, channel: :impressos} =
               Enum.find(pool, &(&1.id == "impresso-req-stale"))
    end

    test "keeps an event that released an unauthored impresso in the pool as unverified" do
      pool = rich_pool()

      assert %{provenance: :unverified, categories: []} =
               Enum.find(pool, &(&1.id == "impresso-req-ghost"))
    end

    test "works for a session without the impresso_requests key" do
      pool = Evidence.build(%{messages: [turn(:learner, "Olá", @t0)]}, no_impressos())

      assert Evidence.ids(pool) == ["turn-1"]
    end

    test "accepts string-keyed session maps" do
      session = %{
        "messages" => [%{"role" => "learner", "modality" => "text", "text" => "Olá", "at" => @t0}],
        "impresso_requests" => []
      }

      assert [%{id: "turn-1", role: "learner", text: "Olá"}] =
               Evidence.build(session, no_impressos())
    end
  end

  describe "build/2 ordering" do
    test "interleaves turns and events by timestamp" do
      assert Evidence.ids(rich_pool()) == [
               "turn-1",
               "turn-2",
               "impresso-req-lab",
               "turn-3",
               "impresso-req-ecg",
               "impresso-req-stale",
               "impresso-req-ghost",
               "impresso-req-none"
             ]
    end

    test "keeps turn ids tied to message position even when timestamps are out of order" do
      pool =
        Evidence.build(
          session([turn(:learner, "second", @t1), turn(:learner, "first", @t0)], []),
          chest_pain()
        )

      assert Enum.map(pool, &{&1.id, &1.text}) == [{"turn-2", "first"}, {"turn-1", "second"}]
    end

    test "on an exact tie keeps message order, then event order, turns before events" do
      messages = [turn(:learner, "a", @t0), turn(:patient, "b", @t0)]

      events = [
        event("req-b", 2, ["laudo-eletrocardiograma"], @t0),
        event("req-a", 1, ["laboratorio-sangue-enzimas"], @t0)
      ]

      pool = Evidence.build(session(messages, events), chest_pain())

      assert Evidence.ids(pool) == ["turn-1", "turn-2", "impresso-req-a", "impresso-req-b"]
    end
  end

  describe "jev_view/1 and ids/1" do
    test "returns the minimized id, role and text items in pool order" do
      pool =
        Evidence.build(
          session(
            [turn(:learner, "Olá", @t0), turn(:patient, "Oi", @t2)],
            [event("req-lab", 1, ["laboratorio-sangue-enzimas"], @t1)]
          ),
          chest_pain()
        )

      assert Evidence.jev_view(pool) == [
               %{id: "turn-1", role: "learner", text: "Olá"},
               %{id: "impresso-req-lab", role: "learner", text: "request req-lab"},
               %{id: "turn-2", role: "patient", text: "Oi"}
             ]
    end

    test "ids/1 lists every id in pool order" do
      pool = Evidence.build(session([turn(:patient, "Oi", @t0)], []), no_impressos())

      assert Evidence.ids(pool) == ["turn-1"]
      assert Evidence.ids([]) == []
    end
  end

  describe "requirement/1" do
    test "maps an absent or nil modality to any learner evidence" do
      assert requirement(nil) == :any
      assert Evidence.requirement(%{}) == :any
    end

    test "maps verbal and impressos" do
      assert requirement("verbal") == :verbal
      assert requirement("impressos") == :impressos
    end

    test "maps each Impressos category name" do
      for category <- @categories do
        assert requirement(category) == {:impressos_category, category}
      end
    end

    test "maps any other value to an unknown modality" do
      assert requirement("telepathy") == {:unknown_modality, "telepathy"}
      assert requirement("") == {:unknown_modality, ""}
      assert requirement(7) == {:unknown_modality, 7}
    end

    test "maps the modality requirements authored in the v2 fixture" do
      assert Enum.map(no_impressos()["rubric"], &Evidence.requirement/1) == [
               :verbal,
               :any,
               {:impressos_category, "physical_exam"},
               :impressos
             ]
    end
  end

  describe "providability/2" do
    test "transcript requirements are always providable" do
      for package <- [chest_pain(), no_impressos()], modality <- [nil, "verbal"] do
        assert Evidence.providability(requirement(modality), package) == :ok
      end
    end

    test "impressos is providable only when the package authors an impresso" do
      assert Evidence.providability(:impressos, chest_pain()) == :ok
      assert Evidence.providability(:impressos, no_impressos()) == {:error, :no_authored_impresso}

      assert Evidence.providability(:impressos, %{"impressos" => nil}) ==
               {:error, :no_authored_impresso}
    end

    test "a category is providable only when the package authors an impresso of it" do
      for category <- @categories do
        requirement = requirement(category)

        assert Evidence.providability(requirement, chest_pain()) == :ok

        assert Evidence.providability(requirement, no_impressos()) ==
                 {:error, :no_authored_impresso}
      end

      only_lab = %{"impressos" => [%{"id" => "lab", "category" => "laboratory"}]}

      assert Evidence.providability(requirement("laboratory"), only_lab) == :ok

      assert Evidence.providability(requirement("imaging"), only_lab) ==
               {:error, :no_authored_impresso}
    end

    test "an unknown modality is never providable" do
      assert Evidence.providability(requirement("telepathy"), chest_pain()) ==
               {:error, :unknown_modality}
    end
  end

  describe "validate/3 accepted evidence" do
    test "an empty citation list is valid" do
      assert Evidence.validate(rich_pool(), [], :verbal) == {:ok, []}
    end

    test "the same learner turn backs criteria with different requirements" do
      pool = rich_pool()

      assert {:ok, [%{id: "turn-1"}]} = Evidence.validate(pool, ["turn-1"], :verbal)
      assert {:ok, [%{id: "turn-1"}]} = Evidence.validate(pool, ["turn-1"], :any)
      assert {:ok, [%{id: "turn-1"}]} = Evidence.validate(pool, ["turn-1"], :verbal)
    end

    test "typed and spoken learner turns both satisfy verbal" do
      assert {:ok, [%{channel: :text}, %{channel: :voice}]} =
               Evidence.validate(rich_pool(), ["turn-1", "turn-3"], :verbal)
    end

    test "a valid event satisfies impressos, its own category and any" do
      pool = rich_pool()
      ids = ["impresso-req-lab"]

      for requirement <- [:impressos, {:impressos_category, "laboratory"}, :any] do
        assert {:ok, [%{id: "impresso-req-lab", provenance: :impressos}]} =
                 Evidence.validate(pool, ids, requirement)
      end
    end

    test "returns the cited items in pool order without duplicates" do
      cited = ["impresso-req-ecg", "turn-3", "turn-1", "turn-3"]

      assert {:ok, items} = Evidence.validate(rich_pool(), cited, :any)
      assert Enum.map(items, & &1.id) == ["turn-1", "turn-3", "impresso-req-ecg"]
    end
  end

  describe "validate/3 rejected evidence" do
    test "an id that is not in the pool does not exist" do
      pool = rich_pool()

      for id <- ["turn-99", "turn-0", "impresso-req-missing", "Turn-1", "turn-1 ", "1", ""] do
        assert Evidence.validate(pool, [id], :any) == {:error, {:nonexistent_evidence_id, id}}
      end
    end

    test "a malformed id does not exist" do
      pool = rich_pool()

      for id <- [1, nil, :"turn-1", %{id: "turn-1"}, ["turn-1"]] do
        assert Evidence.validate(pool, [id], :any) == {:error, {:nonexistent_evidence_id, id}}
      end
    end

    test "a citation value that is not a list does not exist" do
      assert Evidence.validate(rich_pool(), "turn-1", :any) ==
               {:error, {:nonexistent_evidence_id, "turn-1"}}
    end

    test "a patient turn has the wrong role, whatever the requirement" do
      pool = rich_pool()

      for requirement <- [:any, :verbal, :impressos] do
        assert Evidence.validate(pool, ["turn-2"], requirement) ==
                 {:error, {:wrong_role, "turn-2"}}
      end
    end

    test "a learner turn cited for an Impressos requirement has the wrong channel" do
      pool = rich_pool()

      for requirement <- [:impressos, {:impressos_category, "laboratory"}] do
        assert Evidence.validate(pool, ["turn-1"], requirement) ==
                 {:error, {:wrong_channel, "turn-1"}}
      end
    end

    test "an event of another category has the wrong channel" do
      assert Evidence.validate(rich_pool(), ["impresso-req-lab"], {:impressos_category, "report"}) ==
               {:error, {:wrong_channel, "impresso-req-lab"}}
    end

    test "an event cited for a verbal requirement has the wrong channel" do
      assert Evidence.validate(rich_pool(), ["impresso-req-lab"], :verbal) ==
               {:error, {:wrong_channel, "impresso-req-lab"}}
    end

    test "an event that released nothing satisfies no requirement" do
      pool = rich_pool()

      for requirement <- [:any, :impressos, {:impressos_category, "laboratory"}] do
        assert Evidence.validate(pool, ["impresso-req-none"], requirement) ==
                 {:error, {:wrong_channel, "impresso-req-none"}}
      end
    end

    test "nothing satisfies an unknown modality" do
      assert Evidence.validate(rich_pool(), ["turn-1"], {:unknown_modality, "telepathy"}) ==
               {:error, {:wrong_channel, "turn-1"}}
    end

    test "an event recorded for another station version has the wrong provenance" do
      pool = rich_pool()

      for requirement <- [:any, :impressos, {:impressos_category, "physical_exam"}] do
        assert Evidence.validate(pool, ["impresso-req-stale"], requirement) ==
                 {:error, {:wrong_provenance, "impresso-req-stale"}}
      end
    end

    test "an event that released an unauthored impresso has the wrong provenance" do
      assert Evidence.validate(rich_pool(), ["impresso-req-ghost"], :impressos) ==
               {:error, {:wrong_provenance, "impresso-req-ghost"}}
    end

    test "reports the first offending id in citation order" do
      cited = ["turn-1", "turn-2", "turn-99"]

      assert Evidence.validate(rich_pool(), cited, :verbal) == {:error, {:wrong_role, "turn-2"}}
    end

    test "never matches evidence by text" do
      assert Evidence.validate(rich_pool(), ["Quando começou a dor?"], :verbal) ==
               {:error, {:nonexistent_evidence_id, "Quando começou a dor?"}}
    end
  end
end
