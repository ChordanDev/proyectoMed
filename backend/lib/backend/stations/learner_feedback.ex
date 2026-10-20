defmodule Backend.Stations.LearnerFeedback do
  @moduledoc """
  Post-assessment step that replaces the per-criterion `recommendation` of an
  already computed rubric assessment with provider-written learner feedback
  (issue #215, ADR-005).

  It is a pure transformation of the `recommendation` field: status, level,
  points, evidence, reason, sub-actions, estimates and calls are never read
  back from the provider or changed.

    * **Eligibility.** Only `:assessed` criteria are sent. Other criteria are
      never sent. Without an eligible criterion no provider call is made.
    * **Uncertain criteria.** An `:uncertain` criterion that reports its
      authored actions gets a deterministic text, written without a provider,
      naming the actions the learner performed with evidence and the ones
      still missing (issue #291). Every other unsent criterion keeps the
      authored `practice_recommendation`.
    * **Request.** One call for every eligible criterion that has no cached
      text, carrying the package `language` and, per criterion, its
      description, obtained and next level, points, performed and missing
      authored actions, and the text of the learner evidence the assessment
      already cited. The conversation is never sent.
    * **Deadline.** The call runs under `:learner_feedback_deadline_ms`
      (default 45 000 ms, overridden at boot by `LEARNER_FEEDBACK_DEADLINE_MS`);
      a timeout, error or crash keeps the authored text for every criterion.
      There are no retries. Each call logs its latency at info level (success)
      or warning level (fallback), never the texts.
    * **Validation.** Each text must be a non-blank string of at most 400
      characters once trimmed, and must not contain global score or
      pass/fail/readiness language (`@forbidden`). An invalid or missing text
      keeps the authored text for that criterion only.
    * **Cache.** Generated texts are stored with the session
      (`Backend.Stations.Conversation.put_learner_feedback/2`), each bound to
      the fingerprint of its graded outcome (id, status, level, points, sorted
      evidence ids and sorted sub-action id/classification pairs). A changed
      outcome regenerates only that criterion. Fallbacks are never cached, so
      a transient failure retries on the next fetch. A cache read or write that
      exits (timeout, process gone) degrades to no cache; the texts are still
      returned for this response.

  The provider is selected with `:learner_feedback_adapter` (a
  `Backend.Stations.LearnerFeedback.Adapter`). `config/config.exs` sets it to
  `Backend.Stations.LearnerFeedback.OpenAIAdapter` for dev and prod
  (`LLM_PROVIDER=anthropic` swaps in
  `Backend.Stations.LearnerFeedback.AnthropicAdapter` at boot), and
  `config/test.exs` keeps the `Backend.Stations.LearnerFeedback.DisabledAdapter`,
  which is also the fallback when the key is unset.
  """

  require Logger

  alias Backend.Stations.Conversation
  alias Backend.Stations.LearnerFeedback.DisabledAdapter
  alias Backend.Stations.RubricAssessment.Points

  @default_deadline_ms 45_000
  @max_characters 400
  @performed "performed"
  @not_performed "not_performed"
  @learner_roles [:learner, :student, "learner", "student"]

  # Global score, pass/fail and readiness language (pt-BR and English) that
  # per-criterion feedback must never contain. Matched case-insensitively on
  # whole words.
  @forbidden ~r/\b(?:aprovad[oa]s?|reprovad[oa]s?|aprova[cç][aã]o|reprova[cç][aã]o|apt[oa]s?|inapt[oa]s?|passou|nota final|nota global|nota total|pontua[cç][aã]o final|pontua[cç][aã]o total|pass|passed|passes|fail|failed|fails|failing|ready|readiness|final score|overall score|total score)\b/iu

  @doc """
  Returns `assessment` with the `recommendation` of each assessed criterion
  replaced by valid generated feedback, and of each uncertain criterion that
  reports its actions by what was asked and what is still missing, keeping the
  authored text otherwise.
  """
  @spec attach(map(), map(), String.t()) :: map()
  def attach(%{criteria: criteria} = assessment, package, session_id) do
    authored = Map.new(rubric(package), &{&1["id"], &1})
    eligible = Enum.filter(criteria, &(&1.status == :assessed and Map.has_key?(authored, &1.id)))
    cached = cached_texts(session_id, eligible)
    pending = Enum.reject(eligible, &Map.has_key?(cached, &1.id))
    generated = generate(pending, authored, package, session_id)

    texts =
      cached |> Map.merge(generated) |> Map.merge(uncertain_texts(criteria, authored, package))

    %{
      assessment
      | criteria:
          Enum.map(criteria, fn criterion ->
            case Map.fetch(texts, criterion.id) do
              {:ok, text} -> %{criterion | recommendation: text}
              :error -> criterion
            end
          end)
    }
  end

  # The texts of uncertain criteria that report their actions: what was asked
  # (performed with evidence) and what is still missing (everything else).
  defp uncertain_texts(criteria, authored, package) do
    for %{status: :uncertain, sub_actions: [_ | _] = sub_actions, id: id} <- criteria,
        Map.has_key?(authored, id),
        actions =
          Map.new(list(authored[id], "actions"), &{&1["id"], to_string(&1["description"])}),
        {asked, missing} = asked_and_missing(sub_actions, actions),
        asked != [] or missing != [],
        into: %{},
        do: {id, uncertain_text(asked, missing, package["language"])}
  end

  defp asked_and_missing(sub_actions, actions) do
    known = Enum.filter(sub_actions, &Map.has_key?(actions, &1.id))
    {asked, missing} = Enum.split_with(known, &asked?/1)
    {Enum.map(asked, &phrase(actions[&1.id])), Enum.map(missing, &phrase(actions[&1.id]))}
  end

  # Authored descriptions join one sentence, so their own final period goes.
  defp phrase(description), do: description |> String.trim() |> String.trim_trailing(".")

  defp asked?(%{classification: @performed, evidence_ids: [_ | _]}), do: true
  defp asked?(_sub_action), do: false

  defp uncertain_text(asked, missing, language) do
    {asked_label, missing_label} = uncertain_labels(language)

    [{asked_label, asked}, {missing_label, missing}]
    |> Enum.reject(fn {_label, descriptions} -> descriptions == [] end)
    |> Enum.map_join(" ", fn {label, descriptions} ->
      "#{label}: #{Enum.join(descriptions, "; ")}."
    end)
  end

  defp uncertain_labels("pt" <> _region), do: {"Você investigou", "Ainda falta investigar"}
  defp uncertain_labels(_language), do: {"You asked about", "Still to investigate"}

  defp cached_texts(session_id, eligible) do
    cache =
      try do
        case Conversation.learner_feedback(session_id) do
          {:ok, cache} -> cache
          {:error, _reason} -> %{}
        end
      catch
        :exit, _reason -> %{}
      end

    for criterion <- eligible,
        %{fingerprint: fingerprint, text: text} <- [Map.get(cache, criterion.id)],
        fingerprint == fingerprint(criterion),
        into: %{},
        do: {criterion.id, text}
  end

  defp generate([], _authored, _package, _session_id), do: %{}

  defp generate(pending, authored, package, session_id) do
    request = %{
      language: package["language"],
      criteria: Enum.map(pending, &request_criterion(&1, Map.fetch!(authored, &1.id)))
    }

    started_at = System.monotonic_time(:millisecond)
    result = run_with_deadline(request)
    elapsed_ms = System.monotonic_time(:millisecond) - started_at

    case result do
      {:ok, output} when is_map(output) ->
        valid =
          for criterion <- pending,
              text <- [valid_text(output, criterion.id)],
              is_binary(text),
              into: %{},
              do: {criterion.id, text}

        Logger.info(
          "Learner feedback answered in #{elapsed_ms} ms: " <>
            "#{map_size(valid)} texts for #{length(pending)} criteria"
        )

        store(session_id, pending, valid)
        valid

      {:ok, _malformed} ->
        Logger.warning(
          "Learner feedback output is malformed after #{elapsed_ms} ms; keeping authored text"
        )

        %{}

      {:error, :disabled} ->
        %{}

      {:error, reason} ->
        Logger.warning(
          "Learner feedback unavailable (#{failure_kind(reason)}) after #{elapsed_ms} ms; " <>
            "keeping authored text"
        )

        %{}
    end
  end

  defp store(_session_id, _pending, valid) when map_size(valid) == 0, do: :ok

  defp store(session_id, pending, valid) do
    entries =
      for criterion <- pending, Map.has_key?(valid, criterion.id), into: %{} do
        {criterion.id,
         %{fingerprint: fingerprint(criterion), text: Map.fetch!(valid, criterion.id)}}
      end

    try do
      _ = Conversation.put_learner_feedback(session_id, entries)
      :ok
    catch
      :exit, _reason -> :ok
    end
  end

  defp fingerprint(criterion) do
    {criterion.id, criterion.status, criterion[:level], criterion[:points],
     Enum.sort(criterion.evidence_ids),
     criterion.sub_actions |> Enum.map(&{&1.id, &1.classification}) |> Enum.sort()}
  end

  defp request_criterion(criterion, authored) do
    actions = Map.new(list(authored, "actions"), &{&1["id"], to_string(&1["description"])})

    %{
      id: criterion.id,
      description: to_string(authored["description"]),
      level: level(authored, criterion.level),
      next_level: next_level(authored, criterion.points),
      points: Points.to_decimal_string(criterion.points),
      max_points: Points.to_decimal_string(criterion.max_points),
      performed_actions: action_descriptions(criterion.sub_actions, @performed, actions),
      missing_actions: action_descriptions(criterion.sub_actions, @not_performed, actions),
      evidence:
        for(%{role: role, text: text} <- criterion.evidence, role in @learner_roles, do: text)
    }
  end

  defp level(authored, label) do
    authored |> list("levels") |> Enum.find(&(&1["label"] == label)) |> level_entry()
  end

  # The authored level with the smallest points above the obtained points, or
  # `nil` when the obtained level is already the highest.
  defp next_level(authored, points) do
    authored
    |> list("levels")
    |> Enum.flat_map(fn level ->
      case Points.from_authored(level["points"]) do
        {:ok, level_points} when level_points > points -> [{level_points, level}]
        _other -> []
      end
    end)
    |> Enum.min_by(&elem(&1, 0), fn -> nil end)
    |> case do
      nil -> nil
      {_points, level} -> level_entry(level)
    end
  end

  defp level_entry(%{} = level),
    do: %{label: to_string(level["label"]), description: to_string(level["description"])}

  defp level_entry(nil), do: nil

  defp action_descriptions(sub_actions, classification, actions) do
    for %{id: id, classification: ^classification} <- sub_actions,
        Map.has_key?(actions, id),
        do: Map.fetch!(actions, id)
  end

  defp valid_text(output, id) do
    with text when is_binary(text) <- Map.get(output, id),
         text = String.trim(text),
         true <- text != "" and String.length(text) <= @max_characters,
         false <- Regex.match?(@forbidden, text) do
      text
    else
      _invalid -> nil
    end
  end

  defp run_with_deadline(request) do
    adapter = Application.get_env(:backend, :learner_feedback_adapter, DisabledAdapter)

    deadline_ms =
      Application.get_env(:backend, :learner_feedback_deadline_ms, @default_deadline_ms)

    task =
      Task.async(fn ->
        try do
          adapter.write_feedback(request)
        rescue
          _e -> {:error, :adapter_crashed}
        catch
          :exit, _reason -> {:error, :adapter_exited}
          :throw, _value -> {:error, :adapter_threw}
        end
      end)

    case Task.yield(task, deadline_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, output}} -> {:ok, output}
      {:ok, {:error, reason}} -> {:error, reason}
      {:ok, _other} -> {:ok, :malformed}
      {:exit, _reason} -> {:error, :adapter_exited}
      nil -> {:error, :timeout}
    end
  end

  defp failure_kind(reason) when is_atom(reason), do: reason
  defp failure_kind(_reason), do: :provider_error

  defp rubric(package) do
    case package["rubric"] do
      rubric when is_list(rubric) -> Enum.filter(rubric, &is_map/1)
      _missing -> []
    end
  end

  defp list(criterion, key) do
    case Map.get(criterion, key) do
      entries when is_list(entries) -> Enum.filter(entries, &is_map/1)
      _missing -> []
    end
  end
end
