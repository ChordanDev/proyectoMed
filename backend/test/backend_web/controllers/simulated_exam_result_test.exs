defmodule BackendWeb.SimulatedExamResultTest do
  use BackendWeb.ConnCase, async: false

  alias Backend.Stations
  alias Backend.Stations.StationLoader

  # Answers each criterion as `Application.get_env(:backend, __MODULE__)` says:
  # a level label assesses it, and a criterion left out stays uncertain.
  defmodule RubricDouble do
    @behaviour Backend.Stations.JevDecision.Adapter
    def decide_patient(_), do: {:ok, %{status: :verified}}
    def decide_rubric(_), do: {:error, :not_implemented}

    def decide_rubric_batch(request) do
      answers = Application.get_env(:backend, __MODULE__, %{})

      {:ok,
       %{
         decisions:
           Enum.map(request.questions, fn question ->
             classification = Map.get(answers, question.criterion.id, "uncertain")

             %{
               criterion_id: question.criterion.id,
               classification: classification,
               evidence_ids: if(classification == "uncertain", do: [], else: ["turn-1"]),
               actions: []
             }
           end)
       }}
    end
  end

  setup do
    package = Stations.get_active_package()
    adapter = Application.fetch_env(:backend, :jev_decision_adapter)
    Application.put_env(:backend, :jev_decision_adapter, RubricDouble)

    on_exit(fn ->
      Application.delete_env(:backend, RubricDouble)
      :sys.replace_state(StationLoader, fn _ -> package end)

      case adapter do
        {:ok, value} -> Application.put_env(:backend, :jev_decision_adapter, value)
        :error -> Application.delete_env(:backend, :jev_decision_adapter)
      end
    end)

    :ok
  end

  defp fixture do
    File.read!("priv/stations/fixtures/valid-package-v2-partial-reconciliation.json")
    |> Jason.decode!()
  end

  defp criterion(id, max_points, overrides \\ %{}) do
    Map.merge(
      %{
        "id" => id,
        "description" => "Criterion #{id}.",
        "evidence_questions" => ["Was #{id} met?"],
        "practice_recommendation" => "Practice #{id}.",
        "levels" => [
          %{"label" => "inadequado", "points" => 0, "description" => "Not met."},
          %{"label" => "adequado", "points" => max_points, "description" => "Met."}
        ],
        "actions" => [],
        "order" => 1,
        "count_cap" => nil,
        "first_n" => nil,
        "veto" => false,
        "exclusion" => false,
        "modality_requirement" => nil
      },
      overrides
    )
  end

  # One criterion worth `scored_max`, with a partial level that earns `scored`.
  defp assessed(scored, scored_max) do
    levels =
      Enum.uniq_by(
        [
          %{"label" => "adequado", "points" => scored_max, "description" => "Met."},
          %{"label" => "parcialmente_adequado", "points" => scored, "description" => "Part."}
        ],
        & &1["points"]
      )

    criterion("assessed", scored_max, %{"levels" => levels})
  end

  defp answer(scored, scored_max) do
    if scored == scored_max, do: "adequado", else: "parcialmente_adequado"
  end

  defp finished_exam(rubric, answers) do
    :sys.replace_state(StationLoader, fn _ -> Map.put(fixture(), "rubric", rubric) end)
    Application.put_env(:backend, RubricDouble, answers)

    session = Stations.create_session(%{audio_consent: true, mode: :simulated_exam})
    on_exit(fn -> Stations.discard_session(session.session_id) end)

    {:ok, _} =
      Backend.Stations.Conversation.append_message(session.session_id, %{
        role: :learner,
        modality: :voice,
        text: "Exemplo da sessão"
      })

    {:ok, _} = Stations.complete_session(session.session_id)
    session.session_id
  end

  defp result(conn, id) do
    conn |> get("/api/v2/stations/active/sessions/#{id}/result") |> json_response(200)
  end

  describe "certainty level at the Phoenix HTTP API (#426)" do
    # {scored_max, level}: each threshold exactly, and one fortieth of a point
    # below it, on a 10-point station.
    for {scored_max, level} <- [
          {10, 5},
          {9.975, 4},
          {8, 4},
          {7.975, 3},
          {6, 3},
          {5.975, 2},
          {4, 2},
          {3.975, 1}
        ] do
      @scored_max scored_max
      @level level
      test "#{scored_max} of 10 assessed points is level #{level}", %{conn: conn} do
        rubric =
          if @scored_max == 10 do
            [assessed(10, 10)]
          else
            [
              assessed(@scored_max, @scored_max),
              criterion("left-out", Float.round(10 - @scored_max * 1.0, 3))
            ]
          end

        id = finished_exam(rubric, %{"assessed" => "adequado"})
        assert result(conn, id)["certainty_level"] == @level
      end
    end

    test "no assessed point at all is level 1 with no total", %{conn: conn} do
      id = finished_exam([criterion("left-out", 10)], %{})
      body = result(conn, id)

      assert body["certainty_level"] == 1
      assert body["scaled_total"] == nil
      assert body["incomplete"] == true
    end

    test "eligible_max = 0 is level 1 with no total, and nothing is left out", %{conn: conn} do
      excluded = criterion("excluded", 10, %{"exclusion" => true})

      for rubric <- [[], [excluded]] do
        id = finished_exam(rubric, %{})
        body = result(conn, id)

        assert body["estimates"]["eligible_max"] == "0"
        assert body["certainty_level"] == 1
        assert body["scaled_total"] == nil
        assert body["incomplete"] == false
      end
    end
  end

  describe "scaled total (#426)" do
    test "6 of 8 assessed points on a 10-point station shows 7.5", %{conn: conn} do
      id =
        finished_exam([assessed(6, 8), criterion("left-out", 2)], %{"assessed" => answer(6, 8)})

      body = result(conn, id)

      assert body["scaled_total"] == "7.5"
      assert body["certainty_level"] == 4
      assert body["incomplete"] == true
      assert [%{"id" => "left-out", "status" => "uncertain"}] = body["estimates"]["unresolved"]
    end

    test "complete coverage shows exactly the total, and is not incomplete", %{conn: conn} do
      id =
        finished_exam([assessed(1.125, 1.5)], %{"assessed" => answer(1.125, 1.5)})

      body = result(conn, id)

      assert body["estimates"]["total"] == "1.125"
      assert body["scaled_total"] == "1.125"
      assert body["certainty_level"] == 5
      assert body["incomplete"] == false
    end

    # {subtotal, scored_max, eligible_max, scaled_total}
    for {subtotal, scored_max, eligible_max, scaled_total} <- [
          # 285.71 fortieths: the mockup's run, up to the next fortieth.
          {6.25, 8.75, 10, "7.15"},
          # 1.33 fortieths, down.
          {0.025, 0.075, 0.1, "0.025"},
          # 2.67 fortieths, up.
          {0.05, 0.075, 0.1, "0.075"},
          # 1.5 fortieths exactly: a tie rounds up.
          {0.025, 0.05, 0.075, "0.05"}
        ] do
      @subtotal subtotal
      @scored_max scored_max
      @left_out eligible_max - scored_max
      @scaled_total scaled_total
      test "#{subtotal} of #{scored_max} assessed on #{eligible_max} rounds to #{scaled_total}",
           %{conn: conn} do
        id =
          finished_exam(
            [assessed(@subtotal, @scored_max), criterion("left-out", Float.round(@left_out, 3))],
            %{"assessed" => answer(@subtotal, @scored_max)}
          )

        assert result(conn, id)["scaled_total"] == @scaled_total
      end
    end

    test "the rounded total never passes the station's maximum", %{conn: conn} do
      id =
        finished_exam([assessed(8, 8), criterion("left-out", 2.025)], %{"assessed" => "adequado"})

      body = result(conn, id)

      assert body["estimates"]["eligible_max"] == "10.025"
      assert body["scaled_total"] == "10.025"
    end

    test "the rubric estimates stay as they are", %{conn: conn} do
      id =
        finished_exam([assessed(6, 8), criterion("left-out", 2)], %{"assessed" => answer(6, 8)})

      assert %{
               "total" => nil,
               "scored_subtotal" => "6",
               "scored_max" => "8",
               "eligible_max" => "10"
             } = result(conn, id)["estimates"]
    end
  end

  test "a training has none of the simulated exam fields", %{conn: conn} do
    :sys.replace_state(StationLoader, fn _ -> Map.put(fixture(), "rubric", [assessed(6, 8)]) end)
    Application.put_env(:backend, RubricDouble, %{"assessed" => answer(6, 8)})

    session = Stations.create_session(%{audio_consent: false})
    on_exit(fn -> Stations.discard_session(session.session_id) end)

    {:ok, _} =
      Backend.Stations.Conversation.append_message(session.session_id, %{
        role: :learner,
        modality: :text,
        text: "Exemplo da sessão"
      })

    {:ok, _} = Stations.complete_session(session.session_id)
    body = result(conn, session.session_id)

    assert body["estimates"]["total"] == "6"
    refute Map.has_key?(body, "scaled_total")
    refute Map.has_key?(body, "certainty_level")
    refute Map.has_key?(body, "incomplete")
  end

  test "a technical failure invalidates the run with no result (#196)", %{conn: conn} do
    id = finished_exam([assessed(8, 8)], %{"assessed" => "adequado"})

    Application.put_env(
      :backend,
      :jev_decision_adapter,
      Backend.Stations.JevDecision.DisabledAdapter
    )

    body =
      conn |> get("/api/v2/stations/active/sessions/#{id}/result") |> json_response(502)

    assert Map.keys(body) |> Enum.sort() == ["error", "message"]
    assert body["error"] == "invalid_attempt"
  end
end
