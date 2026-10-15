defmodule Backend.Stations.Qualification do
  @moduledoc """
  Qualification harness for the Jev dialogue gate and the rubric assessment of
  one station (issue #130).

  The harness drives each fictional case of
  `priv/stations/qualification/<station_id>/` through the real seam, with the
  configured Jev adapter and, for the rubric, the configured rubric resolver
  (`Backend.Stations.RubricAssessment.Resolver`), and records the observed
  structural outcome:

    * a `dialogue_gate` case calls
      `Backend.Stations.CandidateGate.verify_and_deliver/4` with the case's
      candidate patient reply and no regeneration, so a refusal is observed as
      refused;
    * a `rubric_assessment` case calls
      `Backend.Stations.RubricAssessment.assess/3` over a session built from the
      case's turns, and reads one criterion or one of its actions.

  Each observation is then placed in exactly one result:

    * `:adapter_disabled` — the adapter is disabled, so nothing was observed;
    * `:not_adjudicated` — no human recorded an expected outcome for the case;
    * `:agreed_with_adjudication` — the observed outcome is one the adjudicator
      accepted;
    * `:technical_failure` — the call failed where the adjudicator expected a
      decision;
    * `:disagreed` — any other observed outcome.

  The harness measures agreement between the seam and a human adjudication of
  structural outcomes. It never compares a result with the thresholds and never
  produces a verdict: with undefined thresholds or pending cases there is
  nothing to decide, and once both exist the decision is a human one.

  ## Privacy

  A summary and its rendered report hold case identifiers, categories, surfaces
  and outcome labels only. No case text, candidate reply, rationale or adapter
  payload is kept, logged or written. Before each case, a `:debug` line
  `[Qualification] case=<id> surface=<surface>` names the case, so the adapter's
  own debug lines that follow it can be attributed to that case.
  """

  require Logger

  alias Backend.Stations.CandidateGate
  alias Backend.Stations.Impressos
  alias Backend.Stations.JevDecision
  alias Backend.Stations.Qualification.Cases
  alias Backend.Stations.RubricAssessment
  alias Backend.Stations.RubricAssessment.Resolver
  alias Backend.Stations.StationPackage

  @results [:agreed_with_adjudication, :disagreed, :not_adjudicated, :adapter_disabled] ++
             [:technical_failure]
  @failed_calls ~w(technical_failure invalid_attempt)
  @thresholds_file "thresholds.json"
  # Turns carry no real time; one second apart keeps their authored order.
  @session_start ~U[2000-01-01 00:00:00Z]

  @type result ::
          :agreed_with_adjudication
          | :disagreed
          | :not_adjudicated
          | :adapter_disabled
          | :technical_failure

  @type counts :: %{result() => non_neg_integer()}

  @type loaded :: %{
          station_id: String.t(),
          package: map(),
          cases: [map()],
          thresholds: :undefined | :defined
        }

  @type case_result :: %{
          id: String.t(),
          category: String.t(),
          surface: String.t(),
          observed: String.t(),
          result: result()
        }

  @type summary :: %{
          station_id: String.t(),
          adapter: module(),
          resolver: module(),
          thresholds: :undefined | :defined,
          adjudicated: non_neg_integer(),
          cases: [case_result()],
          categories: [%{category: String.t(), counts: counts()}],
          totals: counts()
        }

  @type load_error ::
          :unknown_station
          | {:invalid_package, String.t()}
          | {:unreadable, String.t()}
          | {:invalid_case, String.t(), :unknown_criterion | :unknown_action | :unknown_level}
          | Cases.file_error()
          | Cases.thresholds_error()

  @doc """
  Loads the station package with its qualification cases and thresholds, and
  runs every case. See `load/1` and `evaluate/2`.
  """
  @spec run(String.t(), keyword()) :: {:ok, summary()} | {:error, load_error()}
  def run(station_id, opts \\ []) when is_list(opts) do
    with {:ok, loaded} <- load(station_id) do
      {:ok, evaluate(loaded, opts)}
    end
  end

  @doc """
  Loads and validates the package, the case files (in category order) and the
  thresholds file of `station_id`.

  Returns `{:error, :unknown_station}` when the station has no qualification
  directory.
  """
  @spec load(String.t()) :: {:ok, loaded()} | {:error, load_error()}
  def load(station_id) when is_binary(station_id) do
    with {:ok, directory} <- directory(station_id),
         {:ok, package} <- package(station_id),
         {:ok, thresholds} <- thresholds(directory),
         {:ok, cases} <- cases(directory, package) do
      {:ok, %{station_id: station_id, package: package, cases: cases, thresholds: thresholds}}
    end
  end

  @doc """
  Runs every loaded case through its seam and summarises the results.

  `opts[:adapter]` overrides the configured Jev adapter and
  `opts[:resolver_adapter]` the configured rubric resolver, which only rubric
  cases reach. No other option is read.
  """
  @spec evaluate(loaded(), keyword()) :: summary()
  def evaluate(%{package: package, cases: cases} = loaded, opts \\ []) when is_list(opts) do
    jev_opts = Keyword.take(opts, [:adapter, :resolver_adapter])
    results = Enum.map(cases, &case_result(&1, package, jev_opts))

    %{
      station_id: loaded.station_id,
      adapter: JevDecision.resolve_adapter(jev_opts),
      resolver: Resolver.adapter(jev_opts),
      thresholds: loaded.thresholds,
      adjudicated: Enum.count(cases, &adjudicated?/1),
      cases: results,
      categories:
        for category <- Cases.categories() do
          %{category: category, counts: counts(Enum.filter(results, &(&1.category == category)))}
        end,
      totals: counts(results)
    }
  end

  @doc """
  Renders a summary as plain text: a header, the counts per category and one
  line per case. The text holds identifiers and labels only.
  """
  @spec render(summary()) :: String.t()
  def render(summary) do
    header = [
      "Jev qualification run: #{summary.station_id}",
      "Adapter: #{inspect(summary.adapter)}",
      "Resolver: #{inspect(summary.resolver)}",
      "Thresholds: #{thresholds_line(summary.thresholds)}",
      "Adjudication: #{summary.adjudicated} of #{length(summary.cases)} cases adjudicated",
      "This output is not a clinical accuracy claim. It counts structural agreement with",
      "human adjudication and carries no verdict.",
      "",
      Enum.join(["category", "cases" | Enum.map(@results, &Atom.to_string/1)], " | ")
    ]

    categories = Enum.map(summary.categories, &counts_line(&1.category, &1.counts))
    totals = counts_line("total", summary.totals)

    cases =
      for result <- summary.cases do
        Enum.join(
          [result.id, result.category, result.surface, result.observed, result.result],
          " | "
        )
      end

    Enum.join(
      header ++ categories ++ [totals, "", "id | category | surface | observed | result"] ++ cases,
      "\n"
    )
  end

  # ============================================================================
  # Loading
  # ============================================================================

  defp directory(station_id) do
    directory = Application.app_dir(:backend, "priv/stations/qualification/#{station_id}")

    if station_id =~ ~r/\A[a-z0-9-]+\z/ and File.dir?(directory) do
      {:ok, directory}
    else
      {:error, :unknown_station}
    end
  end

  defp package(station_id) do
    path = Application.app_dir(:backend, "priv/stations/#{station_id}/package.json")

    with {:ok, package} <- decode(path) do
      case StationPackage.validate(package) do
        {:ok, package} -> {:ok, package}
        {:error, _errors} -> {:error, {:invalid_package, station_id}}
      end
    end
  end

  defp thresholds(directory) do
    with {:ok, thresholds} <- decode(Path.join(directory, @thresholds_file)) do
      Cases.validate_thresholds(thresholds)
    end
  end

  defp cases(directory, package) do
    Enum.reduce_while(Cases.categories(), {:ok, []}, fn category, {:ok, loaded} ->
      with {:ok, file} <- decode(Path.join(directory, "#{category}.json")),
           {:ok, cases} <- Cases.validate_file(file),
           :ok <- check_file(file, category, package),
           :ok <- check_targets(cases, package) do
        {:cont, {:ok, loaded ++ cases}}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp check_file(%{"category" => category, "station_id" => station_id}, category, package) do
    if station_id == package["station_id"], do: :ok, else: {:error, {:invalid_file, :station_id}}
  end

  defp check_file(_file, _category, _package), do: {:error, {:invalid_file, :unknown_category}}

  defp decode(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, decoded} <- Jason.decode(contents) do
      {:ok, decoded}
    else
      {:error, _reason} -> {:error, {:unreadable, Path.basename(path)}}
    end
  end

  # A rubric case must name a criterion, action and level the package authors.
  defp check_targets(cases, package) do
    rubric = Map.new(package["rubric"], &{&1["id"], &1})

    Enum.find_value(cases, :ok, fn
      %{"surface" => "rubric_assessment"} = case_map ->
        case target_error(case_map, rubric[case_map["input"]["criterion_id"]]) do
          nil -> nil
          reason -> {:error, {:invalid_case, case_map["id"], reason}}
        end

      _dialogue_case ->
        nil
    end)
  end

  defp target_error(_case_map, nil), do: :unknown_criterion

  defp target_error(%{"input" => input} = case_map, criterion) do
    action_ids = Enum.map(criterion["actions"], & &1["id"])
    labels = Enum.map(criterion["levels"], & &1["label"])

    cond do
      input["action_id"] not in [nil | action_ids] -> :unknown_action
      Enum.all?(levels(case_map), &(&1 in labels)) -> nil
      true -> :unknown_level
    end
  end

  defp levels(case_map) do
    outcomes =
      case_map["proposed_expected"]["outcomes"] ++ (expected(case_map) || [])

    for "assessed:" <> level <- outcomes, do: level
  end

  # ============================================================================
  # Observation
  # ============================================================================

  defp case_result(case_map, package, jev_opts) do
    # Lets a maintainer attribute the adapter's debug lines to the case that follows.
    Logger.debug("[Qualification] case=#{case_map["id"]} surface=#{case_map["surface"]}")
    observed = observe(case_map, package, jev_opts ++ deadline(case_map["input"]))

    %{
      id: case_map["id"],
      category: case_map["category"],
      surface: case_map["surface"],
      observed: observed,
      result: result(observed, expected(case_map))
    }
  end

  defp observe(%{"surface" => "dialogue_gate", "input" => input}, package, jev_opts) do
    conversation = input["turns"] |> Enum.with_index(1) |> Enum.map(&message/1)

    gate_opts =
      Keyword.delete(jev_opts, :resolver_adapter) ++
        [
          station_id: package["station_id"],
          version: package["version"],
          case_state: %{learner_turns: Enum.count(conversation, &(&1.role == :learner))},
          can_retry?: false
        ]

    case CandidateGate.verify_and_deliver(
           input["candidate_reply"],
           package,
           conversation,
           gate_opts
         ) do
      {:ok, _delivered} -> "delivered"
      {:error, {:denied, _rule}} -> "denied"
      {:error, {:refused, status}} -> Atom.to_string(status)
      {:error, reason} -> failure(reason)
    end
  end

  defp observe(%{"surface" => "rubric_assessment", "input" => input}, package, jev_opts) do
    case RubricAssessment.assess(package, session(input["turns"], package), jev_opts) do
      {:ok, %{criteria: criteria}} ->
        criteria
        |> Enum.find(&(&1.id == input["criterion_id"]))
        |> rubric_outcome(input["action_id"])

      {:error, {:invalid_attempt, reason}} ->
        failure(reason)
    end
  end

  defp rubric_outcome(%{status: :assessed, level: level}, nil), do: "assessed:#{level}"
  defp rubric_outcome(%{status: status}, nil), do: Atom.to_string(status)

  # A criterion skipped before Jev has no action decisions to read.
  defp rubric_outcome(%{sub_actions: sub_actions} = criterion, action_id) do
    case Enum.find(sub_actions, &(&1.id == action_id)) do
      %{classification: classification} -> "action:#{classification}"
      nil -> rubric_outcome(criterion, nil)
    end
  end

  defp failure(:adapter_disabled), do: "adapter_disabled"
  defp failure({:adapter_disabled, _message}), do: "adapter_disabled"

  defp failure(reason) do
    if JevDecision.technical_failure?(reason), do: "technical_failure", else: "invalid_attempt"
  end

  defp deadline(%{"deadline" => "expired"}) do
    [deadline_at_monotonic_ms: JevDecision.monotonic_now_ms() - 1]
  end

  defp deadline(_input), do: []

  # ============================================================================
  # Session
  # ============================================================================

  # The session an attempt with these turns would leave: transcript messages,
  # and one Impressos request event per `impressos` turn, decided by the same
  # keyword match as a live request.
  defp session(turns, package) do
    {messages, events, _released} =
      turns
      |> Enum.with_index(1)
      |> Enum.reduce({[], [], []}, fn
        {%{"modality" => "impressos"} = turn, position}, {messages, events, released} ->
          event = impresso_event(turn, position, length(events) + 1, released, package)
          {messages, events ++ [event], released ++ event.released_ids}

        turn, {messages, events, released} ->
          {messages ++ [message(turn)], events, released}
      end)

    %{messages: messages, impresso_requests: events}
  end

  defp message({turn, position}) do
    %{
      role: role(turn["role"]),
      modality: modality(turn["modality"]),
      text: turn["text"],
      at: DateTime.add(@session_start, position, :second)
    }
  end

  defp impresso_event(%{"text" => text}, position, order, released, package) do
    matched_ids = Impressos.match(package["impressos"] || [], Impressos.normalize(text))
    {decision, released_ids} = Impressos.decide(matched_ids, released)

    %{
      request_id: "qualification-request-#{order}",
      station_id: package["station_id"],
      station_version: package["version"],
      order: order,
      text: text,
      matched_ids: matched_ids,
      decision: decision,
      released_ids: released_ids,
      at: DateTime.add(@session_start, position, :second)
    }
  end

  defp role("learner"), do: :learner
  defp role("patient"), do: :patient

  defp modality("text"), do: :text
  defp modality("voice"), do: :voice

  # ============================================================================
  # Results
  # ============================================================================

  defp adjudicated?(case_map), do: expected(case_map) != nil

  defp expected(%{"adjudication" => %{"status" => "adjudicated", "expected" => expected}}) do
    expected["outcomes"]
  end

  defp expected(_pending_case), do: nil

  @spec result(String.t(), [String.t()] | nil) :: result()
  defp result("adapter_disabled", _expected), do: :adapter_disabled
  defp result(_observed, nil), do: :not_adjudicated

  defp result(observed, expected) do
    cond do
      observed in expected -> :agreed_with_adjudication
      observed in @failed_calls -> :technical_failure
      true -> :disagreed
    end
  end

  defp counts(results) do
    Map.merge(Map.new(@results, &{&1, 0}), Enum.frequencies_by(results, & &1.result))
  end

  # ============================================================================
  # Rendering
  # ============================================================================

  defp thresholds_line(:undefined), do: "undefined (pending human definition)"

  defp thresholds_line(:defined) do
    "defined (see thresholds.json; this harness does not compare results with them)"
  end

  defp counts_line(label, counts) do
    cases = counts |> Map.values() |> Enum.sum()

    Enum.join([label, cases | Enum.map(@results, &Map.fetch!(counts, &1))], " | ")
  end
end
