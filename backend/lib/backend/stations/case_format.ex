defmodule Backend.Stations.CaseFormat do
  @moduledoc """
  Parses a case written in the tagged Markdown format (issue #330, spec in
  `docs/case-format/README.md`) into a Station Package, or into a list of
  errors located at a line of the case.

  The parser is pure and deterministic: no LLM, no database, no file access.
  The package it builds passes `Backend.Stations.StationPackage.validate/1`.
  Besides the Station Package fields it carries format-only data that current
  consumers ignore:

  - `area` and `theme`;
  - `actors`: every actor with its profile, voice, facts, explicit-question
    facts and mandatory questions (the patient also fills `patient_profile`);
  - `pep_links`: the PEP criterion each fact answers, and the type of each
    criterion with the mandatory questions it checks.

  Terminology: a PEP `[ITEM]` is a package rubric criterion, and a PEP
  `[CRITÉRIO]` is one of its actions.
  """

  alias Backend.Stations.CaseFormat.Document
  alias Backend.Stations.CaseFormat.Rules
  alias Backend.Stations.CaseFormat.Tags
  alias Backend.Stations.CaseFormat.Values
  alias Backend.Stations.StationPackage

  @typedoc "A format error located at a 1-based line of the case."
  @type error :: %{line: pos_integer(), message: String.t()}

  @doc "Parses a tagged case into a Station Package or its located errors, sorted by line."
  @spec parse(String.t()) :: {:ok, map()} | {:error, [error()]}
  def parse(text) when is_binary(text) do
    if String.valid?(text), do: parse_valid(text), else: {:error, [invalid_encoding(text)]}
  end

  defp parse_valid(text) do
    {tags, syntax_errors} = Tags.scan(text)
    {doc, document_errors} = Document.collect(tags)

    case sort(syntax_errors ++ document_errors ++ Rules.check(doc)) do
      [] -> doc |> package() |> validate()
      errors -> {:error, errors}
    end
  end

  # The tag regexes are Unicode-aware and raise on invalid UTF-8, so the
  # encoding is checked first and reported at the first line that breaks it.
  defp invalid_encoding(text) do
    index = text |> String.split("\n") |> Enum.find_index(&(not String.valid?(&1)))
    %{line: index + 1, message: "case is not valid UTF-8"}
  end

  defp sort(errors), do: errors |> Enum.uniq() |> Enum.sort_by(&{&1.line, &1.message})

  # The format rules cover the package contract, so this only fails on a gap
  # between the two; the error then names the package rule.
  defp validate(package) do
    case StationPackage.validate(package) do
      {:ok, package} ->
        {:ok, package}

      {:error, messages} ->
        {:error, Enum.map(messages, &%{line: 1, message: "Station Package: #{&1}"})}
    end
  end

  # ---------------------------------------------------------------------------
  # Package
  # ---------------------------------------------------------------------------

  defp package(doc) do
    patient = Enum.find(doc.actors, &(role(&1) == "patient"))
    theme = doc.singles["TEMA"].value

    %{
      "station_id" => doc.singles["ESTACAO"].id,
      "version" => StationPackage.version(),
      "language" => "pt-BR",
      "display_title" => theme,
      "area" => doc.singles["AREA"].value,
      "theme" => theme,
      "placeholder" => placeholder(doc),
      "candidate_brief" => %{
        "scenario" => doc.singles["CENARIO"].value,
        "tasks" => Enum.map(doc.tasks, & &1.value)
      },
      "patient_profile" => %{
        "persona" => patient.children["PERFIL"].value,
        "age" => age(patient),
        "presenting_context" => patient.children["CONTEXTO"].value,
        "tone" => patient.children["TOM"].value
      },
      "revealable_facts" => Enum.map(doc.facts, &fact/1),
      "response_rules" => Enum.map(doc.rules, &%{"id" => &1.id, "instruction" => &1.value}),
      "expected_actions" =>
        Enum.map(doc.tasks ++ doc.expected, &%{"id" => &1.id, "description" => &1.value}),
      "rubric" => doc.items |> Enum.with_index(1) |> Enum.map(&criterion/1),
      "approved_templates" => nil,
      "impressos" => Enum.map(doc.impressos, &impresso/1),
      "actors" => Enum.map(doc.actors, &actor(&1, doc.facts)),
      "pep_links" => pep_links(doc)
    }
  end

  defp placeholder(%{singles: %{"PROVISORIO" => tag}}) do
    {:ok, placeholder} = Values.boolean(tag.value)
    placeholder
  end

  defp placeholder(_doc), do: false

  defp role(%{tag: tag}) do
    {:ok, role} = Values.role(tag.attrs["papel"])
    role
  end

  defp age(%{tag: tag}) do
    {:ok, age} = Values.non_negative_integer(tag.attrs["idade"])
    age
  end

  defp fact(%{tag: tag, topic: topic, kind: kind}) do
    %{
      "id" => tag.id,
      "topic" => topic.value,
      "content" => tag.value,
      "disclosure_condition" => if(kind == :question, do: "timed", else: "on_request")
    }
  end

  defp actor(%{tag: tag, children: children} = actor, facts) do
    owned = for %{tag: %{attrs: %{"ator" => id}}} = fact <- facts, id == tag.id, do: fact

    %{
      "id" => tag.id,
      "role" => role(actor),
      "name" => tag.value,
      "age" => age(actor),
      "voice" => tag.attrs["voz"],
      "persona" => children["PERFIL"].value,
      "tone" => children["TOM"].value,
      "fact_ids" => for(%{kind: :fact, tag: fact} <- owned, do: fact.id),
      "explicit_fact_ids" =>
        for(%{kind: :fact, tag: fact} <- owned, "EXPLICITO" in fact.flags, do: fact.id),
      "mandatory_question_ids" => for(%{kind: :question, tag: question} <- owned, do: question.id)
    }
    |> put_present("presenting_context", children["CONTEXTO"])
  end

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, tag), do: Map.put(map, key, tag.value)

  defp impresso(%{tag: tag, children: children}) do
    {:ok, category} = Values.category(tag.attrs["categoria"])

    %{
      "id" => tag.id,
      "title" => tag.value,
      "category" => category,
      "keywords" => Values.keywords(children["LIBERACAO"].value),
      "content" => children["CONTEUDO"].value
    }
  end

  # ---------------------------------------------------------------------------
  # Rubric
  # ---------------------------------------------------------------------------

  defp criterion({%{tag: tag, criteria: actions} = item, number}) do
    {:ok, levels} = Rules.thresholds(item)
    levels = Enum.sort_by(levels, &{elem(&1, 1), elem(&1, 2)})
    maximum = levels |> Enum.map(&elem(&1, 1)) |> Enum.max()

    %{
      "id" => tag.id,
      "description" => description(number, tag.value, maximum, actions),
      "evidence_questions" => [],
      "practice_recommendation" => tag.value,
      "levels" => Enum.map(levels, &level/1),
      "actions" => Enum.map(actions, &action/1),
      "order" => nil,
      "count_cap" => nil,
      "first_n" => nil,
      "veto" => Enum.any?(actions, &("PROIBIDO" in &1.flags)),
      "exclusion" => false,
      "modality_requirement" => nil,
      "rule" => nil
    }
  end

  # The PEP heading and its numbered criteria, as the item is printed for the
  # examiner. A forbidden criterion is a veto, not a criterion to perform.
  defp description(number, title, maximum, actions) do
    criteria =
      actions
      |> Enum.reject(&("PROIBIDO" in &1.flags))
      |> Enum.with_index(1)
      |> Enum.map_join("; ", fn {action, index} -> "(#{index}) #{action.value}" end)

    "ITEM #{number}: #{title} (Total: #{Values.format_points(maximum)} ponto)\n" <>
      "Critérios avaliados: #{criteria}."
  end

  defp level({tag, _fortieths, minimum}) do
    {:ok, points, _fortieths} = Values.points(tag.attrs["pontos"])

    %{
      "label" => tag.id,
      "points" => points,
      "min_actions" => minimum,
      "description" => tag.value
    }
  end

  defp action(tag) do
    %{"id" => tag.id, "description" => tag.value}
    |> put_role(tag.flags)
    |> put_ids("impresso_ids", tag.attrs["impressos"])
    |> put_ids("interprets_impresso_ids", tag.attrs["apos"])
  end

  defp put_role(action, flags) do
    cond do
      "OBRIGATORIO" in flags -> Map.put(action, "role", "mandatory")
      "PROIBIDO" in flags -> Map.put(action, "role", "forbidden")
      true -> action
    end
  end

  defp put_ids(action, _key, nil), do: action
  defp put_ids(action, key, ids), do: Map.put(action, key, Values.ids(ids))

  defp pep_links(doc) do
    facts =
      for %{tag: %{attrs: %{"pep" => pep}} = tag} <- doc.facts do
        {:ok, item, criterion} = Values.pep(pep)
        %{"fact_id" => tag.id, "criterion_id" => item, "action_id" => criterion}
      end

    actions =
      for %{tag: item, criteria: criteria} <- doc.items, criterion <- criteria do
        {:ok, type} = Values.type(criterion.attrs["tipo"])

        %{
          "criterion_id" => item.id,
          "action_id" => criterion.id,
          "type" => type,
          "question_ids" => Values.ids(Map.get(criterion.attrs, "perguntas", ""))
        }
      end

    %{"facts" => facts, "actions" => actions}
  end
end
