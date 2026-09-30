defmodule Backend.Stations.TemplateApplicabilityTest do
  use ExUnit.Case, async: true

  alias Backend.Stations.TemplateApplicability

  describe "evaluate/2 recognized predicates" do
    test "unconditional is always true regardless of case state" do
      assert TemplateApplicability.evaluate(%{"type" => "unconditional"}, %{}) == true
      assert TemplateApplicability.evaluate(%{"type" => "unconditional"}, nil) == true
    end

    test "first_learner_turn is true only when learner_turns is exactly 1" do
      predicate = %{"type" => "first_learner_turn"}

      assert TemplateApplicability.evaluate(predicate, %{learner_turns: 1}) == true
      assert TemplateApplicability.evaluate(predicate, %{learner_turns: 0}) == false
      assert TemplateApplicability.evaluate(predicate, %{learner_turns: 2}) == false
      assert TemplateApplicability.evaluate(predicate, %{}) == false
    end

    test "min_learner_turns is true at or above the count" do
      predicate = %{"type" => "min_learner_turns", "count" => 2}

      assert TemplateApplicability.evaluate(predicate, %{learner_turns: 2}) == true
      assert TemplateApplicability.evaluate(predicate, %{learner_turns: 5}) == true
      assert TemplateApplicability.evaluate(predicate, %{learner_turns: 1}) == false
      assert TemplateApplicability.evaluate(predicate, %{learner_turns: 0}) == false
    end

    test "max_learner_turns is true at or below the count" do
      predicate = %{"type" => "max_learner_turns", "count" => 3}

      assert TemplateApplicability.evaluate(predicate, %{learner_turns: 3}) == true
      assert TemplateApplicability.evaluate(predicate, %{learner_turns: 0}) == true
      assert TemplateApplicability.evaluate(predicate, %{learner_turns: 4}) == false
    end
  end

  describe "evaluate/2 key tolerance" do
    test "tolerates atom keys in the applicability predicate" do
      assert TemplateApplicability.evaluate(%{type: "first_learner_turn"}, %{learner_turns: 1}) ==
               true

      assert TemplateApplicability.evaluate(
               %{type: :not_a_type, count: 1},
               %{learner_turns: 1}
             ) == false

      assert TemplateApplicability.evaluate(%{type: "min_learner_turns", count: 2}, %{
               learner_turns: 2
             }) == true
    end

    test "tolerates string-keyed learner_turns in case state" do
      assert TemplateApplicability.evaluate(%{"type" => "first_learner_turn"}, %{
               "learner_turns" => 1
             }) == true

      assert TemplateApplicability.evaluate(
               %{"type" => "min_learner_turns", "count" => 2},
               %{"learner_turns" => 2}
             ) == true
    end
  end

  describe "evaluate/2 fail-closed cases" do
    test "invalid learner_turns values never satisfy a state-dependent predicate" do
      invalid_states = [
        %{},
        %{learner_turns: nil},
        %{learner_turns: -1},
        %{learner_turns: "2"},
        %{learner_turns: 2.0},
        nil,
        "not a map"
      ]

      predicates = [
        %{"type" => "first_learner_turn"},
        %{"type" => "min_learner_turns", "count" => 1},
        %{"type" => "max_learner_turns", "count" => 5}
      ]

      for predicate <- predicates, case_state <- invalid_states do
        assert TemplateApplicability.evaluate(predicate, case_state) == false
      end
    end

    test "unknown predicate types evaluate false" do
      for type <- ["whenever", "fact_revealed", "all_of", "", 1, :unconditional] do
        assert TemplateApplicability.evaluate(%{"type" => type}, %{learner_turns: 1}) == false
      end
    end

    test "malformed shapes evaluate false without raising" do
      malformed = [
        nil,
        true,
        false,
        "unconditional",
        "Use after the opening assessment.",
        42,
        [],
        %{},
        %{"count" => 1},
        %{"type" => "min_learner_turns"},
        %{"type" => "min_learner_turns", "count" => 0},
        %{"type" => "min_learner_turns", "count" => "2"},
        %{"type" => "min_learner_turns", "count" => 1.5},
        %{"type" => "max_learner_turns", "count" => -1},
        %{"type" => "unconditional", "count" => 1},
        %{"type" => "unconditional", "extra" => true},
        %{"type" => "first_learner_turn", "count" => 1},
        fn _state -> true end,
        {:type, "unconditional"}
      ]

      Enum.each(malformed, fn applicability ->
        assert TemplateApplicability.evaluate(applicability, %{learner_turns: 1}) == false
      end)
    end
  end

  describe "structural_errors/1" do
    test "returns no errors for the full structured vocabulary" do
      valid = [
        %{"type" => "unconditional"},
        %{"type" => "first_learner_turn"},
        %{"type" => "min_learner_turns", "count" => 1},
        %{"type" => "max_learner_turns", "count" => 7}
      ]

      Enum.each(valid, &assert(TemplateApplicability.structural_errors(&1) == []))
    end

    test "returns the exact error message for each invalid category" do
      cases = [
        {nil, "approved_templates entries require an applicability predicate object"},
        {"Use after the opening assessment.",
         "approved_templates applicability must be a structured predicate object, not a prose string"},
        {true,
         "approved_templates applicability must be a structured predicate object, not a boolean"},
        {42, "approved_templates applicability must be a structured predicate object"},
        {%{}, "approved_templates applicability requires a type"},
        {%{"type" => "whenever"},
         "approved_templates applicability type must be one of: unconditional, first_learner_turn, min_learner_turns, max_learner_turns"},
        {%{"type" => "min_learner_turns"},
         "approved_templates min_learner_turns predicate requires a count"},
        {%{"type" => "max_learner_turns", "count" => 0},
         "approved_templates max_learner_turns predicate requires an integer count >= 1"},
        {%{"type" => "unconditional", "count" => 1},
         "approved_templates unconditional predicates must not include additional fields"}
      ]

      Enum.each(cases, fn {applicability, expected_error} ->
        assert TemplateApplicability.structural_errors(applicability) == [expected_error]
      end)
    end
  end
end
