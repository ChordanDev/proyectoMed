defmodule Backend.Stations.Qualification.CasesTest do
  use ExUnit.Case, async: true

  alias Backend.Stations.Qualification.Cases

  @pending %{"status" => "pending", "adjudicator" => nil, "date" => nil, "expected" => nil}

  defp dialogue_case(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "ambiguity-01",
        "category" => "ambiguity",
        "surface" => "dialogue_gate",
        "probes" => [],
        "input" => %{
          "turns" => [%{"role" => "learner", "modality" => "text", "text" => "E como está isso?"}],
          "candidate_reply" => "Está doendo bastante."
        },
        "proposed_expected" => %{"outcomes" => ["low_confidence"], "note" => "Structural note."},
        "adjudication" => @pending
      },
      overrides
    )
  end

  defp rubric_case(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "ambiguity-02",
        "category" => "ambiguity",
        "surface" => "rubric_assessment",
        "probes" => ["G1"],
        "input" => %{
          "criterion_id" => "item-10",
          "action_id" => "criterio-1",
          "turns" => [
            %{"role" => "learner", "modality" => "voice", "text" => "Solicito avaliação."},
            %{"role" => "learner", "modality" => "impressos", "text" => "Solicito hemograma."}
          ]
        },
        "proposed_expected" => %{
          "outcomes" => ["action:performed", "assessed:inadequado", "uncertain"],
          "note" => "Structural note."
        },
        "adjudication" => @pending
      },
      overrides
    )
  end

  defp file(cases, overrides \\ %{}) do
    Map.merge(
      %{
        "station_id" => "acute-appendicitis",
        "category" => "ambiguity",
        "fictional" => true,
        "cases" => cases
      },
      overrides
    )
  end

  defp adjudication(overrides) do
    Map.merge(
      %{
        "status" => "adjudicated",
        "adjudicator" => "Reviewer placeholder",
        "date" => "2026-10-07",
        "expected" => %{"outcomes" => ["delivered"]}
      },
      overrides
    )
  end

  defp put_input(case_map, key, value), do: put_in(case_map, ["input", key], value)

  describe "validate_file/1" do
    test "accepts pending dialogue and rubric cases" do
      cases = [dialogue_case(), rubric_case()]

      assert Cases.validate_file(file(cases)) == {:ok, cases}
    end

    test "accepts an adjudicated case and an expired deadline" do
      cases = [
        dialogue_case(%{"adjudication" => adjudication(%{})})
        |> put_input("deadline", "expired")
      ]

      assert {:ok, ^cases} = Cases.validate_file(file(cases))
    end

    test "rejects a file that is not marked fictional" do
      for fictional <- [false, nil] do
        assert Cases.validate_file(file([dialogue_case()], %{"fictional" => fictional})) ==
                 {:error, {:invalid_file, :not_fictional}}
      end
    end

    test "rejects an unknown file category and a file without cases" do
      assert Cases.validate_file(file([dialogue_case()], %{"category" => "accuracy"})) ==
               {:error, {:invalid_file, :unknown_category}}

      assert Cases.validate_file(file([])) == {:error, {:invalid_file, :invalid_cases}}
      assert Cases.validate_file([]) == {:error, {:invalid_file, :expected_map}}
    end

    test "rejects a case with an unknown category or one that differs from its file" do
      assert Cases.validate_file(file([dialogue_case(%{"category" => "accuracy"})])) ==
               {:error, {:invalid_case, "ambiguity-01", :unknown_category}}

      assert Cases.validate_file(file([dialogue_case(%{"category" => "injection"})])) ==
               {:error, {:invalid_case, "ambiguity-01", :category_mismatch}}
    end

    test "rejects a missing field" do
      for field <- ~w(category surface probes input proposed_expected adjudication) do
        assert Cases.validate_file(file([Map.delete(dialogue_case(), field)])) ==
                 {:error, {:invalid_case, "ambiguity-01", {:missing_field, field}}}
      end

      assert Cases.validate_file(file([Map.delete(dialogue_case(), "id")])) ==
               {:error, {:invalid_case, 1, {:missing_field, "id"}}}
    end

    test "rejects a duplicate id" do
      assert Cases.validate_file(file([dialogue_case(), dialogue_case()])) ==
               {:error, {:invalid_case, "ambiguity-01", :duplicate_id}}
    end

    test "rejects an unknown surface" do
      assert Cases.validate_file(file([dialogue_case(%{"surface" => "transcription"})])) ==
               {:error, {:invalid_case, "ambiguity-01", :unknown_surface}}
    end

    test "rejects probes that are not a list of strings" do
      assert Cases.validate_file(file([dialogue_case(%{"probes" => "G1"})])) ==
               {:error, {:invalid_case, "ambiguity-01", :invalid_probes}}
    end

    test "rejects an input the surface cannot be driven with" do
      invalid = [
        Map.delete(dialogue_case(), "input") |> Map.put("input", %{"turns" => []}),
        put_input(dialogue_case(), "candidate_reply", nil),
        put_input(dialogue_case(), "turns", [%{"role" => "examiner", "text" => "Oi"}]),
        put_input(dialogue_case(), "turns", [
          %{"role" => "learner", "modality" => "impressos", "text" => "Solicito hemograma."}
        ]),
        put_input(dialogue_case(), "deadline", "soon"),
        put_input(rubric_case(), "criterion_id", ""),
        put_input(rubric_case(), "action_id", 4),
        put_input(rubric_case(), "turns", [
          %{"role" => "patient", "modality" => "impressos", "text" => "Hemograma."}
        ])
      ]

      for case_map <- invalid do
        assert {:error, {:invalid_case, _id, :invalid_input}} =
                 Cases.validate_file(file([case_map]))
      end
    end

    test "rejects a proposed outcome outside the vocabulary of the surface" do
      invalid = [
        dialogue_case(%{"proposed_expected" => %{"outcomes" => ["passed"], "note" => "n"}}),
        dialogue_case(%{"proposed_expected" => %{"outcomes" => [], "note" => "n"}}),
        dialogue_case(%{"proposed_expected" => %{"outcomes" => ["delivered"]}}),
        dialogue_case(%{"proposed_expected" => %{"outcomes" => ["uncertain"], "note" => "n"}}),
        rubric_case(%{"proposed_expected" => %{"outcomes" => ["delivered"], "note" => "n"}}),
        rubric_case(%{"proposed_expected" => %{"outcomes" => ["action:met"], "note" => "n"}}),
        rubric_case(%{"proposed_expected" => %{"outcomes" => ["assessed:"], "note" => "n"}})
      ]

      for case_map <- invalid do
        assert {:error, {:invalid_case, _id, :invalid_proposed_expected}} =
                 Cases.validate_file(file([case_map]))
      end
    end

    test "rejects an adjudicated case without adjudicator, date or expected outcome" do
      invalid = [
        adjudication(%{"adjudicator" => nil}),
        adjudication(%{"adjudicator" => " "}),
        adjudication(%{"date" => nil}),
        adjudication(%{"date" => "07/10/2026"}),
        adjudication(%{"expected" => nil}),
        adjudication(%{"expected" => %{"outcomes" => ["uncertain"]}}),
        adjudication(%{"status" => "approved"})
      ]

      for adjudication <- invalid do
        assert Cases.validate_file(file([dialogue_case(%{"adjudication" => adjudication})])) ==
                 {:error, {:invalid_case, "ambiguity-01", :invalid_adjudication}}
      end
    end

    test "rejects a pending case that already records an adjudication" do
      for {field, value} <- [
            {"adjudicator", "Someone"},
            {"date", "2026-10-07"},
            {"expected", %{"outcomes" => ["delivered"]}}
          ] do
        adjudication = Map.put(@pending, field, value)

        assert Cases.validate_file(file([dialogue_case(%{"adjudication" => adjudication})])) ==
                 {:error, {:invalid_case, "ambiguity-01", :invalid_adjudication}}
      end
    end
  end

  describe "validate_thresholds/1" do
    defp thresholds(value, overrides \\ %{}) do
      Map.merge(
        %{
          "station_id" => "acute-appendicitis",
          "defined_by" => nil,
          "date" => nil,
          "overall" => %{"required_agreement" => value},
          "categories" => Map.new(Cases.categories(), &{&1, %{"required_agreement" => value}})
        },
        overrides
      )
    end

    @defined %{"defined_by" => "Reviewer placeholder", "date" => "2026-10-07"}

    test "null values are undefined thresholds" do
      assert Cases.validate_thresholds(thresholds(nil)) == {:ok, :undefined}
    end

    test "one null value keeps the thresholds undefined" do
      partial =
        put_in(thresholds(0.9, @defined), ["categories", "injection"], %{
          "required_agreement" => nil
        })

      assert Cases.validate_thresholds(partial) == {:ok, :undefined}
    end

    test "fully defined thresholds need who defined them and when" do
      assert Cases.validate_thresholds(thresholds(0.9, @defined)) == {:ok, :defined}

      assert Cases.validate_thresholds(thresholds(0.9)) ==
               {:error, {:invalid_thresholds, :missing_definition_record}}
    end

    test "rejects a value that is not a fraction between 0 and 1" do
      for value <- [1.5, -0.1, "0.9", true] do
        assert Cases.validate_thresholds(thresholds(value, @defined)) ==
                 {:error, {:invalid_thresholds, :invalid_required_agreement}}
      end
    end

    test "rejects a missing or unknown category and a missing overall entry" do
      missing = update_in(thresholds(nil), ["categories"], &Map.delete(&1, "chronology"))

      unknown =
        put_in(thresholds(nil), ["categories", "accuracy"], %{"required_agreement" => nil})

      assert Cases.validate_thresholds(missing) == {:error, {:invalid_thresholds, :categories}}
      assert Cases.validate_thresholds(unknown) == {:error, {:invalid_thresholds, :categories}}

      assert Cases.validate_thresholds(Map.delete(thresholds(nil), "overall")) ==
               {:error, {:invalid_thresholds, :invalid_required_agreement}}
    end
  end
end
