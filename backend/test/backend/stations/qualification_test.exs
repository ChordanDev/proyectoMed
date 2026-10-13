defmodule Backend.Stations.QualificationTest do
  use ExUnit.Case, async: true

  alias Backend.Stations.JevDecision.DisabledAdapter
  alias Backend.Stations.Qualification
  alias Backend.Stations.Qualification.Cases

  @moduletag capture_log: true

  @station_id "acute-appendicitis"
  @results [:agreed_with_adjudication, :disagreed, :not_adjudicated, :adapter_disabled] ++
             [:technical_failure]

  # ============================================================================
  # Scripted double and the in-test adjudicated fixture
  # ============================================================================

  @delivered "A dor fica na parte de baixo da barriga, do lado direito."
  @delivered_again "Começou ontem à noite."
  @low_confidence "Não tenho certeza do que o senhor quer saber."
  @upstream_failure "Estou com um pouco de enjoo."

  defmodule ScriptedDouble do
    @moduledoc """
    Verifies every candidate reply except the two scripted by text, and
    classifies every rubric action `"not_performed"` except `criterio-1` of
    `item-01`, performed with the first turn as evidence.
    """
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(%{candidate_text: "Não tenho certeza" <> _rest}) do
      {:ok, %{status: :low_confidence}}
    end

    def decide_patient(%{candidate_text: "Estou com um pouco" <> _rest}) do
      {:error, {:upstream_5xx, 503}}
    end

    def decide_patient(_request), do: {:ok, %{status: :verified}}

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}

    @impl true
    def decide_rubric_batch(request) do
      {:ok, %{decisions: Enum.map(request.questions, &decision/1)}}
    end

    defp decision(question) do
      %{
        criterion_id: question.criterion.id,
        classification: "uncertain",
        evidence_ids: [],
        actions: Enum.map(question.actions, &action(question.criterion.id, &1.id))
      }
    end

    defp action("item-01", "criterio-1") do
      %{id: "criterio-1", classification: "performed", evidence_ids: ["turn-1"]}
    end

    defp action(_criterion_id, id), do: %{id: id, classification: "not_performed"}
  end

  defp adjudicated(outcomes) do
    %{
      "status" => "adjudicated",
      "adjudicator" => "In-test fixture, not a clinical adjudication",
      "date" => "2026-10-07",
      "expected" => %{"outcomes" => outcomes}
    }
  end

  defp pending do
    %{"status" => "pending", "adjudicator" => nil, "date" => nil, "expected" => nil}
  end

  defp fixture_case(id, category, surface, input, adjudication) do
    %{
      "id" => id,
      "category" => category,
      "surface" => surface,
      "probes" => [],
      "input" => input,
      "proposed_expected" => %{"outcomes" => ["technical_failure"], "note" => "In-test fixture."},
      "adjudication" => adjudication
    }
  end

  defp dialogue(candidate_reply) do
    %{
      "turns" => [%{"role" => "learner", "modality" => "text", "text" => "Onde dói?"}],
      "candidate_reply" => candidate_reply
    }
  end

  defp rubric(action_id) do
    %{
      "criterion_id" => "item-01",
      "action_id" => action_id,
      "turns" => [
        %{
          "role" => "learner",
          "modality" => "text",
          "text" => "Bom dia, sou o médico de plantão."
        }
      ]
    }
  end

  defp fixture do
    [
      fixture_case(
        "fx-1",
        "ambiguity",
        "dialogue_gate",
        dialogue(@delivered),
        adjudicated(["delivered"])
      ),
      fixture_case(
        "fx-2",
        "ambiguity",
        "dialogue_gate",
        dialogue(@delivered_again),
        adjudicated(["semantic_refusal", "low_confidence"])
      ),
      fixture_case(
        "fx-3",
        "ambiguity",
        "dialogue_gate",
        dialogue(@low_confidence),
        adjudicated(["semantic_refusal", "low_confidence"])
      ),
      fixture_case(
        "fx-4",
        "ambiguity",
        "dialogue_gate",
        dialogue(@upstream_failure),
        adjudicated(["delivered"])
      ),
      fixture_case("fx-5", "ambiguity", "dialogue_gate", dialogue(@delivered), pending()),
      fixture_case(
        "fx-6",
        "chronology",
        "rubric_assessment",
        rubric("criterio-1"),
        adjudicated(["action:performed"])
      ),
      fixture_case(
        "fx-7",
        "chronology",
        "rubric_assessment",
        rubric(nil),
        adjudicated(["assessed:adequado"])
      ),
      fixture_case(
        "fx-8",
        "chronology",
        "rubric_assessment",
        rubric(nil),
        adjudicated(["assessed:parcialmente_adequado"])
      ),
      fixture_case(
        "fx-9",
        "technical_failure",
        "rubric_assessment",
        Map.put(rubric(nil), "deadline", "expired"),
        adjudicated(["technical_failure"])
      )
    ]
  end

  defp loaded(cases, thresholds \\ :undefined) do
    {:ok, shipped} = Qualification.load(@station_id)

    for {category, group} <- Enum.group_by(cases, & &1["category"]) do
      file = %{
        "station_id" => @station_id,
        "category" => category,
        "fictional" => true,
        "cases" => group
      }

      assert {:ok, _cases} = Cases.validate_file(file)
    end

    %{shipped | cases: cases, thresholds: thresholds}
  end

  defp by_id(summary), do: Map.new(summary.cases, &{&1.id, &1})

  # ============================================================================
  # Shipped cases and thresholds
  # ============================================================================

  describe "load/1 with the shipped acute-appendicitis files" do
    setup do
      {:ok, loaded} = Qualification.load(@station_id)
      %{loaded: loaded}
    end

    test "every category has at least two cases", %{loaded: %{cases: cases}} do
      counts = Enum.frequencies_by(cases, & &1["category"])

      assert Map.keys(counts) |> Enum.sort() == Enum.sort(Cases.categories())
      assert Enum.all?(counts, fn {_category, count} -> count >= 2 end)
    end

    test "every case is pending and unadjudicated", %{loaded: %{cases: cases}} do
      assert length(cases) >= 16

      for case_map <- cases do
        assert case_map["adjudication"] ==
                 %{"status" => "pending", "adjudicator" => nil, "date" => nil, "expected" => nil}
      end
    end

    test "every case file is marked fictional and holds one category" do
      directory = Application.app_dir(:backend, "priv/stations/qualification/#{@station_id}")
      files = directory |> Path.join("*.json") |> Path.wildcard() |> Enum.sort()

      assert Enum.map(files, &Path.basename(&1, ".json")) ==
               Enum.sort(["thresholds" | Cases.categories()])

      for path <- files, Path.basename(path) != "thresholds.json" do
        file = path |> File.read!() |> Jason.decode!()

        assert file["fictional"] == true
        assert file["category"] == Path.basename(path, ".json")
      end
    end

    test "ambiguity and chronology are covered on the dialogue gate", %{loaded: %{cases: cases}} do
      surfaces = fn category ->
        for %{"category" => ^category, "surface" => surface} <- cases, uniq: true, do: surface
      end

      assert "dialogue_gate" in surfaces.("ambiguity")
      assert Enum.sort(surfaces.("chronology")) == ["dialogue_gate", "rubric_assessment"]
    end

    test "the mapping and design gaps named by the issue are probed", %{loaded: %{cases: cases}} do
      probed = cases |> Enum.flat_map(& &1["probes"]) |> MapSet.new()

      for gap <- ~w(G1 G2b G5 G6 G10 first_n_enumeration single_turn_answer_order) do
        assert gap in probed
      end
    end

    test "every threshold is undefined", %{loaded: loaded} do
      assert loaded.thresholds == :undefined

      thresholds =
        Application.app_dir(:backend, "priv/stations/qualification/#{@station_id}")
        |> Path.join("thresholds.json")
        |> File.read!()
        |> Jason.decode!()

      assert thresholds["defined_by"] == nil
      assert thresholds["date"] == nil
      assert thresholds["overall"] == %{"required_agreement" => nil}

      assert thresholds["categories"] ==
               Map.new(Cases.categories(), &{&1, %{"required_agreement" => nil}})
    end

    test "rejects a station without qualification files" do
      assert Qualification.load("chest-pain-initial-assessment") == {:error, :unknown_station}
      assert Qualification.load("../acute-appendicitis") == {:error, :unknown_station}
    end
  end

  # ============================================================================
  # Runner
  # ============================================================================

  describe "run/2 with the default disabled adapter" do
    setup do
      {:ok, summary} = Qualification.run(@station_id)
      %{summary: summary}
    end

    test "names the adapter and reports undefined thresholds", %{summary: summary} do
      assert summary.adapter == DisabledAdapter
      assert summary.thresholds == :undefined
      assert summary.adjudicated == 0
    end

    test "Jev-dependent cases report adapter_disabled", %{summary: summary} do
      cases = by_id(summary)

      assert %{observed: "adapter_disabled", result: :adapter_disabled} = cases["ambiguity-01"]
      assert %{observed: "adapter_disabled", result: :adapter_disabled} = cases["ambiguity-03"]

      # Outcomes decided in code before the adapter is reached stay visible.
      assert %{observed: "technical_failure", result: :not_adjudicated} =
               cases["technical-failure-01"]

      assert summary.totals.adapter_disabled > 0
    end

    test "no case agrees or disagrees while nothing is adjudicated", %{summary: summary} do
      assert Enum.all?(summary.cases, &(&1.result in [:adapter_disabled, :not_adjudicated]))
      assert summary.totals.agreed_with_adjudication == 0
      assert summary.totals.disagreed == 0

      assert summary.totals.adapter_disabled + summary.totals.not_adjudicated ==
               length(summary.cases)
    end

    test "the rendered report carries no verdict and no case text", %{summary: summary} do
      {:ok, %{cases: cases}} = Qualification.load(@station_id)
      report = Qualification.render(summary)

      assert report =~ "Adapter: Backend.Stations.JevDecision.DisabledAdapter"
      assert report =~ "Thresholds: undefined"
      assert report =~ "not a clinical accuracy claim"
      refute report =~ ~r/\b(pass|passed|fail|failed|qualified|accurate)\b/i

      for case_map <- cases do
        assert report =~ case_map["id"]

        texts =
          [case_map["input"]["candidate_reply"], case_map["proposed_expected"]["note"]] ++
            Enum.map(case_map["input"]["turns"], & &1["text"])

        for text <- texts, is_binary(text), String.trim(text) != "" do
          refute report =~ text
        end
      end
    end
  end

  describe "evaluate/2 with a scripted adapter and an adjudicated in-test fixture" do
    setup do
      %{summary: Qualification.evaluate(loaded(fixture()), adapter: ScriptedDouble)}
    end

    test "records the observed structural outcome of each case", %{summary: summary} do
      assert summary.adapter == ScriptedDouble

      assert Map.new(summary.cases, &{&1.id, &1.observed}) == %{
               "fx-1" => "delivered",
               "fx-2" => "delivered",
               "fx-3" => "low_confidence",
               "fx-4" => "technical_failure",
               "fx-5" => "delivered",
               "fx-6" => "action:performed",
               "fx-7" => "assessed:parcialmente_adequado",
               "fx-8" => "assessed:parcialmente_adequado",
               "fx-9" => "technical_failure"
             }
    end

    test "computes agreement against the adjudicated expectation", %{summary: summary} do
      assert Map.new(summary.cases, &{&1.id, &1.result}) == %{
               "fx-1" => :agreed_with_adjudication,
               "fx-2" => :disagreed,
               "fx-3" => :agreed_with_adjudication,
               "fx-4" => :technical_failure,
               "fx-5" => :not_adjudicated,
               "fx-6" => :agreed_with_adjudication,
               "fx-7" => :disagreed,
               "fx-8" => :agreed_with_adjudication,
               "fx-9" => :agreed_with_adjudication
             }
    end

    test "counts results per category, in category order", %{summary: summary} do
      assert Enum.map(summary.categories, & &1.category) == Cases.categories()
      counts = Map.new(summary.categories, &{&1.category, &1.counts})

      assert counts["ambiguity"] == %{
               agreed_with_adjudication: 2,
               disagreed: 1,
               not_adjudicated: 1,
               adapter_disabled: 0,
               technical_failure: 1
             }

      assert counts["chronology"].agreed_with_adjudication == 2
      assert counts["chronology"].disagreed == 1
      assert counts["technical_failure"].agreed_with_adjudication == 1
      assert counts["injection"] == Map.new(@results, &{&1, 0})

      assert summary.totals.agreed_with_adjudication == 5
      assert summary.adjudicated == 8
    end

    test "defined thresholds and adjudicated cases still produce no verdict" do
      adjudicated = Enum.reject(fixture(), &(&1["id"] == "fx-5"))

      report =
        adjudicated
        |> loaded(:defined)
        |> Qualification.evaluate(adapter: ScriptedDouble)
        |> Qualification.render()

      assert report =~ "Thresholds: defined"
      assert report =~ "not a clinical accuracy claim"
      refute report =~ ~r/\b(pass|passed|fail|failed|qualified|accurate)\b/i
    end

    test "a disabled adapter is never counted as agreement or disagreement" do
      summary = Qualification.evaluate(loaded(fixture()), adapter: DisabledAdapter)
      results = Map.new(summary.cases, &{&1.id, &1.result})

      assert results["fx-1"] == :adapter_disabled
      assert results["fx-6"] == :adapter_disabled
      assert results["fx-9"] == :agreed_with_adjudication
      assert summary.totals.disagreed == 0
    end
  end
end
