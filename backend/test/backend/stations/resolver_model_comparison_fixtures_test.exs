defmodule Backend.Stations.ResolverModelComparisonFixturesTest do
  @moduledoc """
  Guards the synthetic transcripts of the resolver model comparison (issue
  #343, `docs/research/resolver-model-comparison.md`). Each fixture must stay a
  gradable input: it names its station, builds the session a live attempt
  would leave (`Backend.Stations.Qualification.session/2`), releases exactly the
  Impressos it declares, and runs through `RubricAssessment.assess/3` with a Jev
  double that leaves every action undecided, so every asked criterion reaches
  the rubric resolver.
  """
  use ExUnit.Case, async: true

  alias Backend.Stations
  alias Backend.Stations.Qualification
  alias Backend.Stations.RubricAssessment

  @moduletag capture_log: true

  @fixtures_dir Path.expand("fixtures/resolver_model_comparison", __DIR__)
  @stations_dir Path.expand("../../../priv/stations", __DIR__)
  @case_format_dir Path.expand("fixtures/case_format", __DIR__)

  @expected [
    {"acute-appendicitis-strong.json", "acute-appendicitis", "strong"},
    {"acute-appendicitis-partial.json", "acute-appendicitis", "partial"},
    {"acute-appendicitis-weak.json", "acute-appendicitis", "weak"},
    {"bronquiolite-strong.json", "bronquiolite-viral-lactente", "strong"},
    {"bronquiolite-partial.json", "bronquiolite-viral-lactente", "partial"},
    {"bronquiolite-weak.json", "bronquiolite-viral-lactente", "weak"}
  ]

  defmodule UndecidedJev do
    @moduledoc "Classifies every rubric question and action as uncertain."
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request), do: {:ok, %{status: :verified}}

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}

    @impl true
    def decide_rubric_batch(request) do
      decisions =
        Enum.map(request.questions, fn question ->
          %{
            criterion_id: question.criterion.id,
            classification: "uncertain",
            evidence_ids: [],
            actions:
              Enum.map(
                question.actions,
                &%{id: &1.id, classification: "uncertain", evidence_ids: []}
              )
          }
        end)

      {:ok, %{decisions: decisions}}
    end
  end

  defmodule RecordingResolver do
    @moduledoc "Reports each resolver request to the test process and decides nothing."
    @behaviour Backend.Stations.RubricAssessment.Resolver

    @impl true
    def resolve(request, opts) do
      send(opts[:test_pid], {:resolver_request, request})
      {:ok, %{actions: []}}
    end
  end

  defp fixture(name), do: @fixtures_dir |> Path.join(name) |> File.read!() |> Jason.decode!()

  defp package(%{"package" => "station:" <> station_id}),
    do:
      @stations_dir |> Path.join("#{station_id}/package.json") |> File.read!() |> Jason.decode!()

  defp package(%{"package" => "case_format:" <> file}) do
    {:ok, package} = @case_format_dir |> Path.join(file) |> File.read!() |> Stations.parse_case()
    package
  end

  for {name, station_id, quality} <- @expected do
    describe name do
      test "names its station and quality and alternates learner and other turns" do
        fixture = fixture(unquote(name))

        assert fixture["station_id"] == unquote(station_id)
        assert fixture["quality"] == unquote(quality)
        assert package(fixture)["station_id"] == unquote(station_id)
        assert Enum.all?(fixture["turns"], &(&1["role"] in ["learner", "patient"]))
        assert Enum.count(fixture["turns"], &(&1["role"] == "learner")) >= 4
      end

      test "releases exactly the Impressos it declares" do
        fixture = fixture(unquote(name))
        session = Qualification.session(fixture["turns"], package(fixture))

        released = session.impresso_requests |> Enum.flat_map(& &1.released_ids) |> Enum.sort()

        assert released == Enum.sort(fixture["expected_released_ids"])
      end

      test "sends every asked criterion to the resolver when Jev decides nothing" do
        fixture = fixture(unquote(name))
        package = package(fixture)
        session = Qualification.session(fixture["turns"], package)

        assert {:ok, %{criteria: criteria}} =
                 RubricAssessment.assess(package, session,
                   adapter: UndecidedJev,
                   resolver_adapter: RecordingResolver,
                   resolver_opts: [test_pid: self()]
                 )

        assert length(criteria) == length(package["rubric"])
        assert_received {:resolver_request, _request}
      end
    end
  end
end
