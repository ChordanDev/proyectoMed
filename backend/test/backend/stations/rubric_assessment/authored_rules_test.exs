defmodule Backend.Stations.RubricAssessment.AuthoredRulesTest do
  use ExUnit.Case, async: true

  alias Backend.Stations.RubricAssessment.AuthoredRules

  @fixtures_path Path.expand("../../../../priv/stations/fixtures", __DIR__)

  @inadequado %{label: "inadequado", points: 0}
  @parcial %{label: "parcialmente_adequado", points: 4}
  @adequado %{label: "adequado", points: 8}

  defp criterion(fixture, id) do
    @fixtures_path
    |> Path.join(fixture)
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("rubric")
    |> Enum.find(&(&1["id"] == id))
  end

  # Thresholds 0/2/3 for 0/0.5/1, `ask-onset` mandatory, three counted actions
  # and `count_cap: 3`.
  defp history, do: criterion("valid-package-v2-authored-rules.json", "history-taking")

  # No thresholds (0/1), one counted action and one forbidden action.
  defp treatment, do: criterion("valid-package-v2-authored-rules.json", "treatment-plan")

  # No rule field at all: one plain action, levels 0/1.
  defp plain, do: criterion("valid-package-v2.json", "onset-assessment")

  # `history/0` plus a forbidden action.
  defp history_with_forbidden do
    forbidden = %{"id" => "ask-leading", "description" => "Leads.", "role" => "forbidden"}

    history()
    |> Map.update!("actions", &(&1 ++ [forbidden]))
    |> Map.put("veto", true)
  end

  defp without_thresholds(criterion) do
    Map.update!(criterion, "levels", fn levels ->
      Enum.map(levels, &Map.delete(&1, "min_actions"))
    end)
  end

  defp put_level(criterion, index, key, value) do
    put_in(criterion, ["levels", Access.at(index), key], value)
  end

  # One decision per authored action, in authored order. Actions named in
  # `performed` were performed with evidence; `overrides` replaces whole
  # decisions as `id => {classification, evidence_ids}`.
  defp sub_actions(criterion, performed, overrides) do
    for %{"id" => id} <- criterion["actions"] do
      default = if id in performed, do: {"performed", ["turn-1"]}, else: {"not_performed", []}
      {classification, evidence_ids} = Map.get(overrides, id, default)

      %{id: id, classification: classification, evidence_ids: evidence_ids}
    end
  end

  defp decide(criterion, jev_level, performed, overrides \\ %{}) do
    AuthoredRules.decide_level(criterion, jev_level, sub_actions(criterion, performed, overrides))
  end

  @history_actions ["ask-onset", "ask-duration", "ask-intensity", "ask-relief"]

  describe "rule 1: unresolved sub-actions" do
    test "an uncertain sub-action makes the criterion uncertain" do
      assert decide(history(), @adequado, @history_actions, %{"ask-duration" => {"uncertain", []}}) ==
               {:uncertain, {:uncertain_sub_action, "ask-duration"}}
    end

    test "an uncertain sub-action is unresolved even when it cites evidence" do
      assert decide(history(), @adequado, @history_actions, %{
               "ask-relief" => {"uncertain", ["turn-1"]}
             }) == {:uncertain, {:uncertain_sub_action, "ask-relief"}}
    end

    test "a sub-action performed without validated evidence makes the criterion uncertain" do
      assert decide(history(), @adequado, @history_actions, %{
               "ask-intensity" => {"performed", []}
             }) ==
               {:uncertain, {:unsupported_sub_action, "ask-intensity"}}
    end

    test "the first unresolved sub-action in authored order is reported" do
      assert decide(history(), @adequado, @history_actions, %{
               "ask-duration" => {"performed", []},
               "ask-relief" => {"uncertain", []}
             }) == {:uncertain, {:unsupported_sub_action, "ask-duration"}}
    end

    test "a sub-action that was not performed needs no evidence" do
      assert decide(history(), @adequado, ["ask-onset", "ask-duration"]) == {:ok, @parcial}
    end
  end

  describe "rule 2: forbidden actions" do
    test "a performed forbidden action scores the zero-point level" do
      assert decide(treatment(), @adequado, ["indicate-expected", "indicate-contraindicated"]) ==
               {:ok, @inadequado}
    end

    test "a forbidden action that was not performed leaves the level alone" do
      assert decide(treatment(), @adequado, ["indicate-expected"]) == {:ok, @adequado}
    end
  end

  describe "rule 3: mandatory actions" do
    test "a missing mandatory action scores the zero-point level whatever the count" do
      assert decide(history(), @adequado, ["ask-duration", "ask-intensity", "ask-relief"]) ==
               {:ok, @inadequado}
    end

    test "a missing mandatory action scores the zero-point level without thresholds" do
      assert decide(without_thresholds(history()), @adequado, ["ask-duration"]) ==
               {:ok, @inadequado}
    end

    test "a performed mandatory action without thresholds leaves Jev's level" do
      assert decide(without_thresholds(history()), @parcial, ["ask-onset"]) == {:ok, @parcial}
    end
  end

  describe "rule 4: thresholds" do
    test "the count of performed actions decides the level" do
      cases = [
        {["ask-onset"], @inadequado},
        {["ask-onset", "ask-duration"], @parcial},
        {["ask-onset", "ask-duration", "ask-intensity"], @adequado},
        {@history_actions, @adequado}
      ]

      for {performed, expected} <- cases do
        assert decide(history(), @parcial, performed) == {:ok, expected}
      end
    end

    test "Jev's criterion-level class does not decide the level" do
      assert decide(history(), @inadequado, @history_actions) == {:ok, @adequado}
      assert decide(history(), @adequado, ["ask-onset"]) == {:ok, @inadequado}
    end

    test "count_cap caps the count" do
      capped = Map.put(history(), "count_cap", 2)

      assert decide(capped, @adequado, @history_actions) == {:ok, @parcial}
    end

    test "no count_cap leaves the count uncapped" do
      uncapped = Map.put(history(), "count_cap", nil)

      assert decide(uncapped, @inadequado, @history_actions) == {:ok, @adequado}
    end

    test "levels are compared by points, not by authored order" do
      reversed = Map.update!(history(), "levels", &Enum.reverse/1)

      assert decide(reversed, @inadequado, ["ask-onset", "ask-duration"]) == {:ok, @parcial}
    end

    test "points stay integer eighths" do
      assert {:ok, %{points: points}} =
               decide(history(), @adequado, ["ask-onset", "ask-duration"])

      assert is_integer(points)
    end
  end

  describe "rule 5: no thresholds" do
    test "Jev's level stands on a criterion without rule fields" do
      assert decide(plain(), @adequado, []) == {:ok, @adequado}
      assert decide(plain(), @inadequado, ["ask-onset"]) == {:ok, @inadequado}
    end

    test "an action that cannot change the level is never an unresolved sub-action" do
      assert decide(plain(), @adequado, [], %{"ask-onset" => {"uncertain", []}}) ==
               {:ok, @adequado}

      assert decide(plain(), @adequado, [], %{"ask-onset" => {"performed", []}}) ==
               {:ok, @adequado}

      assert decide(treatment(), @adequado, [], %{"indicate-expected" => {"uncertain", []}}) ==
               {:ok, @adequado}
    end

    test "a criterion without actions keeps Jev's level" do
      assert AuthoredRules.decide_level(Map.put(plain(), "actions", []), @adequado, []) ==
               {:ok, @adequado}
    end
  end

  describe "precedence" do
    test "an uncertain sub-action wins over a performed forbidden action" do
      assert decide(history_with_forbidden(), @adequado, ["ask-onset", "ask-leading"], %{
               "ask-relief" => {"uncertain", []}
             }) == {:uncertain, {:uncertain_sub_action, "ask-relief"}}
    end

    test "an uncertain forbidden action is unresolved, not a veto" do
      assert decide(treatment(), @adequado, ["indicate-expected"], %{
               "indicate-contraindicated" => {"uncertain", []}
             }) == {:uncertain, {:uncertain_sub_action, "indicate-contraindicated"}}
    end

    test "a performed forbidden action wins over thresholds" do
      assert decide(history_with_forbidden(), @adequado, @history_actions ++ ["ask-leading"]) ==
               {:ok, @inadequado}
    end

    test "a forbidden action that was not performed is not counted" do
      assert decide(history_with_forbidden(), @inadequado, ["ask-onset", "ask-duration"]) ==
               {:ok, @parcial}
    end

    test "a missing mandatory action wins over thresholds" do
      assert decide(history(), @adequado, ["ask-duration", "ask-intensity"]) == {:ok, @inadequado}
    end
  end

  describe "check/1" do
    test "accepts criteria with and without rule fields" do
      for criterion <- [history(), treatment(), plain(), history_with_forbidden()] do
        assert AuthoredRules.check(criterion) == :ok
      end
    end

    test "a criterion without rule fields needs no zero-point level" do
      assert AuthoredRules.check(put_level(plain(), 0, "points", 0.5)) == :ok
    end

    test "thresholds on only some levels are inconsistent" do
      partial =
        Map.update!(history(), "levels", fn [zero | rest] ->
          [Map.delete(zero, "min_actions") | rest]
        end)

      assert AuthoredRules.check(partial) == {:error, :inconsistent_thresholds}
    end

    test "a threshold that is not a non-negative integer is inconsistent" do
      assert AuthoredRules.check(put_level(history(), 1, "min_actions", -1)) ==
               {:error, :inconsistent_thresholds}

      assert AuthoredRules.check(put_level(history(), 1, "min_actions", "2")) ==
               {:error, :inconsistent_thresholds}
    end

    test "a zero-point level with a positive threshold is inconsistent" do
      assert AuthoredRules.check(put_level(history(), 0, "min_actions", 1)) ==
               {:error, :inconsistent_thresholds}
    end

    test "thresholds, mandatory and forbidden actions need a zero-point level" do
      for criterion <- [history(), without_thresholds(history()), treatment()] do
        assert AuthoredRules.check(put_level(criterion, 0, "points", 0.125)) ==
                 {:error, :missing_zero_point_level}
      end
    end
  end
end
