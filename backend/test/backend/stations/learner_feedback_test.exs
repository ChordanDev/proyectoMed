defmodule Backend.Stations.LearnerFeedbackTest do
  # Swaps the application-level learner feedback adapter, so it cannot run concurrently.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  require Logger

  alias Backend.Stations
  alias Backend.Stations.LearnerFeedback

  @moduletag capture_log: true

  defmodule FeedbackDouble do
    @moduledoc """
    Learner feedback double. Reports every request to the test process and
    answers with the function stored under its own application env key.
    """
    @behaviour Backend.Stations.LearnerFeedback.Adapter

    @impl true
    def write_feedback(request) do
      {test_pid, respond} = Application.fetch_env!(:backend, __MODULE__)
      send(test_pid, {:feedback_request, request})
      respond.(request)
    end
  end

  @package %{
    "language" => "pt-BR",
    "rubric" => [
      %{
        "id" => "history",
        "description" => "Takes the pain history.",
        "practice_recommendation" => "Authored history recommendation.",
        "levels" => [
          %{"label" => "inadequado", "points" => 0, "description" => "No history taken."},
          %{
            "label" => "parcialmente_adequado",
            "points" => 0.5,
            "description" => "Partial history."
          },
          %{"label" => "adequado", "points" => 1, "description" => "Complete history."}
        ],
        "actions" => [
          %{"id" => "onset", "description" => "Asks about onset."},
          %{"id" => "radiation", "description" => "Asks about radiation."},
          %{"id" => "duration", "description" => "Asks about duration."}
        ]
      },
      %{
        "id" => "exam",
        "description" => "Examines the abdomen.",
        "practice_recommendation" => "Authored exam recommendation.",
        "levels" => [
          %{"label" => "inadequado", "points" => 0, "description" => "No exam."},
          %{"label" => "adequado", "points" => 1, "description" => "Full exam."}
        ],
        "actions" => []
      },
      %{
        "id" => "unclear",
        "description" => "Unresolved criterion.",
        "practice_recommendation" => "Authored unclear recommendation.",
        "levels" => [
          %{"label" => "inadequado", "points" => 0, "description" => "Nothing."},
          %{"label" => "adequado", "points" => 1, "description" => "Everything."}
        ],
        "actions" => []
      }
    ]
  }

  @history %{
    id: "history",
    status: :assessed,
    level: "parcialmente_adequado",
    points: 20,
    max_points: 40,
    evidence_ids: ["turn-1"],
    evidence: [%{id: "turn-1", role: :learner, text: "Quando começou a dor?"}],
    reason: nil,
    sub_actions: [
      %{id: "onset", classification: "performed", evidence_ids: ["turn-1"]},
      %{id: "radiation", classification: "not_performed", evidence_ids: []},
      %{id: "duration", classification: "uncertain", evidence_ids: []}
    ],
    recommendation: "Authored history recommendation."
  }

  @exam %{
    id: "exam",
    status: :assessed,
    level: "adequado",
    points: 40,
    max_points: 40,
    evidence_ids: ["turn-3"],
    evidence: [%{id: "turn-3", role: :learner, text: "Vou examinar seu abdome."}],
    reason: nil,
    sub_actions: [],
    recommendation: "Authored exam recommendation."
  }

  @unclear %{
    id: "unclear",
    status: :uncertain,
    max_points: 40,
    evidence_ids: [],
    evidence: [],
    reason: :classifier_uncertain,
    sub_actions: [],
    recommendation: "Authored unclear recommendation."
  }

  @assessment %{
    criteria: [@history, @exam, @unclear],
    estimates: %{
      total: nil,
      scored_subtotal: 60,
      scored_max: 80,
      eligible_max: 120,
      unresolved: [%{id: "unclear", status: :uncertain}]
    },
    calls: [%{question_count: 3, justification: :single_batch}]
  }

  @generated %{
    "history" => "Você perguntou sobre o início da dor; investigue também a irradiação.",
    "exam" => "Seu exame do abdome cobriu o que o caso pedia."
  }

  setup do
    previous_adapter = Application.fetch_env(:backend, :learner_feedback_adapter)
    previous_deadline = Application.fetch_env(:backend, :learner_feedback_deadline_ms)
    Application.put_env(:backend, :learner_feedback_adapter, FeedbackDouble)
    respond_with(fn _request -> {:ok, @generated} end)

    on_exit(fn ->
      Application.delete_env(:backend, FeedbackDouble)
      restore(:learner_feedback_adapter, previous_adapter)
      restore(:learner_feedback_deadline_ms, previous_deadline)
    end)

    session = Stations.create_session(audio_consent: false)
    {:ok, _} = Stations.complete_session(session.session_id)
    on_exit(fn -> Stations.discard_session(session.session_id) end)
    %{session_id: session.session_id}
  end

  defp restore(key, {:ok, value}), do: Application.put_env(:backend, key, value)
  defp restore(key, :error), do: Application.delete_env(:backend, key)

  defp respond_with(respond) do
    Application.put_env(:backend, FeedbackDouble, {self(), respond})
  end

  defp recommendations(assessment), do: Map.new(assessment.criteria, &{&1.id, &1.recommendation})

  defp without_recommendations(assessment) do
    update_in(assessment.criteria, fn criteria ->
      Enum.map(criteria, &Map.delete(&1, :recommendation))
    end)
  end

  defp attach(id, assessment \\ @assessment), do: LearnerFeedback.attach(assessment, @package, id)

  defp assert_authored(result) do
    assert recommendations(result) == recommendations(@assessment)
    assert result == @assessment
  end

  describe "attach/3" do
    test "attaches generated feedback to assessed criteria only", %{session_id: id} do
      result = attach(id)

      assert recommendations(result) == %{
               "history" => @generated["history"],
               "exam" => @generated["exam"],
               "unclear" => "Authored unclear recommendation."
             }

      assert_received {:feedback_request, request}
      assert Enum.map(request.criteria, & &1.id) == ["history", "exam"]
    end

    test "changes nothing but the recommendation", %{session_id: id} do
      result = attach(id)
      refute result == @assessment
      assert without_recommendations(result) == without_recommendations(@assessment)
      assert result.estimates == @assessment.estimates
      assert result.calls == @assessment.calls
    end

    test "builds the request from the graded record and cited evidence only", %{session_id: id} do
      attach(id)
      assert_received {:feedback_request, request}
      assert request.language == "pt-BR"
      assert Enum.sort(Map.keys(request)) == [:criteria, :language]

      [history, exam] = request.criteria

      assert history == %{
               id: "history",
               description: "Takes the pain history.",
               level: %{label: "parcialmente_adequado", description: "Partial history."},
               next_level: %{label: "adequado", description: "Complete history."},
               points: "0.5",
               max_points: "1",
               performed_actions: ["Asks about onset."],
               missing_actions: ["Asks about radiation."],
               evidence: ["Quando começou a dor?"]
             }

      assert exam.next_level == nil
      assert exam.evidence == ["Vou examinar seu abdome."]
    end

    test "makes no provider call when no criterion is assessed", %{session_id: id} do
      assessment = %{@assessment | criteria: [@unclear]}
      assert attach(id, assessment) == assessment
      refute_received {:feedback_request, _}
    end

    test "the disabled default adapter keeps the authored text", %{session_id: id} do
      Application.put_env(
        :backend,
        :learner_feedback_adapter,
        Backend.Stations.LearnerFeedback.DisabledAdapter
      )

      assert_authored(attach(id))
    end

    test "provider error falls back for every criterion", %{session_id: id} do
      respond_with(fn _request -> {:error, :rate_limited} end)
      assert_authored(attach(id))
    end

    test "timeout falls back for every criterion", %{session_id: id} do
      Application.put_env(:backend, :learner_feedback_deadline_ms, 20)

      respond_with(fn _request ->
        Process.sleep(500)
        {:ok, @generated}
      end)

      {elapsed_us, result} = :timer.tc(fn -> attach(id) end)
      assert_authored(result)
      assert elapsed_us < 400_000
    end

    test "a slow provider that answers within the configured deadline is used", %{
      session_id: id
    } do
      Application.put_env(:backend, :learner_feedback_deadline_ms, 1_000)

      respond_with(fn _request ->
        Process.sleep(150)
        {:ok, @generated}
      end)

      assert recommendations(attach(id))["history"] == @generated["history"]
    end

    test "without a configured deadline a provider slower than 3 s is still used", %{
      session_id: id
    } do
      Application.delete_env(:backend, :learner_feedback_deadline_ms)

      respond_with(fn _request ->
        Process.sleep(3_100)
        {:ok, @generated}
      end)

      assert recommendations(attach(id))["history"] == @generated["history"]
    end

    test "the configured deadline is one minute" do
      assert Application.fetch_env!(:backend, :learner_feedback_deadline_ms) == 60_000
    end

    test "logs the latency of a successful call without any feedback text", %{session_id: id} do
      # The test environment logs at :warning; this module's info line is the subject here.
      Logger.put_module_level(LearnerFeedback, :info)
      on_exit(fn -> Logger.delete_module_level(LearnerFeedback) end)

      log = capture_log([level: :info], fn -> attach(id) end)

      assert log =~ ~r/Learner feedback answered in \d+ ms: 2 texts for 2 criteria/
      refute log =~ @generated["history"]
      refute log =~ "Quando começou a dor?"
    end

    test "logs the latency of a failed call", %{session_id: id} do
      respond_with(fn _request -> {:error, :upstream_error} end)
      log = capture_log([level: :info], fn -> attach(id) end)

      assert log =~
               ~r/Learner feedback unavailable \(upstream_error\) after \d+ ms; keeping authored text/
    end

    test "logs the latency of a timed out call", %{session_id: id} do
      Application.put_env(:backend, :learner_feedback_deadline_ms, 20)

      respond_with(fn _request ->
        Process.sleep(500)
        {:ok, @generated}
      end)

      log = capture_log([level: :info], fn -> attach(id) end)
      assert log =~ ~r/Learner feedback unavailable \(timeout\) after \d+ ms/
    end

    test "raise, exit and throw fall back for every criterion", %{session_id: id} do
      for crash <- [
            fn _ -> raise "boom" end,
            fn _ -> exit(:boom) end,
            fn _ -> throw(:boom) end
          ] do
        respond_with(crash)
        assert_authored(attach(id))
      end
    end

    test "malformed output falls back", %{session_id: id} do
      for output <- [
            :ok,
            {:ok, "not a map"},
            {:ok, [{"history", "text"}]},
            {:ok, %{"history" => 42, "exam" => nil}},
            {:ok, %{"history" => "   ", "exam" => %{"text" => "nested"}}}
          ] do
        respond_with(fn _request -> output end)
        assert_authored(attach(id))
      end
    end

    test "missing, over-length or pass/fail/score text falls back per criterion", %{
      session_id: id
    } do
      cases = [
        %{"exam" => @generated["exam"]},
        %{"history" => String.duplicate("a", 401), "exam" => @generated["exam"]},
        %{"history" => "Você foi aprovado nesta estação.", "exam" => @generated["exam"]},
        %{"history" => "Candidato inapto para a prova.", "exam" => @generated["exam"]},
        %{"history" => "Sua nota final foi 7.", "exam" => @generated["exam"]},
        %{"history" => "You PASSED this station.", "exam" => @generated["exam"]},
        %{"history" => "You are ready for the exam.", "exam" => @generated["exam"]},
        %{"history" => "This would fail the station.", "exam" => @generated["exam"]}
      ]

      for output <- cases do
        respond_with(fn _request -> {:ok, output} end)
        result = attach(id)

        assert recommendations(result) == %{
                 "history" => "Authored history recommendation.",
                 "exam" => @generated["exam"],
                 "unclear" => "Authored unclear recommendation."
               }
      end
    end

    test "accepts trimmed text of exactly 400 characters", %{session_id: id} do
      text = String.duplicate("é", 400)
      respond_with(fn _request -> {:ok, %{"history" => "  #{text}\n", "exam" => "Bom."}} end)
      assert recommendations(attach(id))["history"] == text
    end
  end

  describe "cache" do
    test "a second fetch reuses the stored feedback", %{session_id: id} do
      first = attach(id)
      assert_received {:feedback_request, _}
      assert attach(id) == first
      refute_received {:feedback_request, _}
    end

    test "a changed graded outcome regenerates only that criterion", %{session_id: id} do
      attach(id)
      assert_received {:feedback_request, _}

      respond_with(fn _request -> {:ok, %{"history" => "Agora você completou a história."}} end)
      changed = %{@history | level: "adequado", points: 40}
      result = attach(id, %{@assessment | criteria: [changed, @exam, @unclear]})

      assert_received {:feedback_request, request}
      assert Enum.map(request.criteria, & &1.id) == ["history"]

      assert recommendations(result) == %{
               "history" => "Agora você completou a história.",
               "exam" => @generated["exam"],
               "unclear" => "Authored unclear recommendation."
             }
    end

    test "changed cited evidence regenerates the criterion", %{session_id: id} do
      attach(id)
      assert_received {:feedback_request, _}

      changed = %{@exam | evidence_ids: ["turn-3", "turn-5"]}
      attach(id, %{@assessment | criteria: [@history, changed, @unclear]})
      assert_received {:feedback_request, request}
      assert Enum.map(request.criteria, & &1.id) == ["exam"]
    end

    test "a changed action classification regenerates the criterion", %{session_id: id} do
      attach(id)
      assert_received {:feedback_request, _}

      sub_actions = [
        %{id: "onset", classification: "performed", evidence_ids: ["turn-1"]},
        %{id: "radiation", classification: "performed", evidence_ids: ["turn-1"]},
        %{id: "duration", classification: "uncertain", evidence_ids: []}
      ]

      changed = %{@history | sub_actions: sub_actions}
      attach(id, %{@assessment | criteria: [changed, @exam, @unclear]})
      assert_received {:feedback_request, request}
      assert Enum.map(request.criteria, & &1.id) == ["history"]
      assert hd(request.criteria).missing_actions == []
    end

    test "unchanged action classifications in another order reuse the cache", %{
      session_id: id
    } do
      attach(id)
      assert_received {:feedback_request, _}

      reordered = %{@history | sub_actions: Enum.reverse(@history.sub_actions)}
      attach(id, %{@assessment | criteria: [reordered, @exam, @unclear]})
      refute_received {:feedback_request, _}
    end

    # Unregistering the Conversation name makes every GenServer.call to it exit
    # with :noproc at once, deterministically and without waiting for a call
    # timeout. The process keeps running and is re-registered afterwards. This
    # module is async: false, so no concurrent test depends on the name.
    test "an exiting cache read and write still returns generated feedback", %{
      session_id: id
    } do
      pid = Process.whereis(Backend.Stations.Conversation)
      true = Process.unregister(Backend.Stations.Conversation)

      result =
        try do
          attach(id)
        after
          Process.register(pid, Backend.Stations.Conversation)
        end

      assert recommendations(result) == %{
               "history" => @generated["history"],
               "exam" => @generated["exam"],
               "unclear" => "Authored unclear recommendation."
             }

      assert without_recommendations(result) == without_recommendations(@assessment)
      assert_received {:feedback_request, _}
    end

    test "a failure is not cached, so the next fetch retries", %{session_id: id} do
      respond_with(fn _request -> {:error, :unavailable} end)
      assert_authored(attach(id))
      assert_received {:feedback_request, _}

      respond_with(fn _request -> {:ok, @generated} end)
      assert recommendations(attach(id))["history"] == @generated["history"]
      assert_received {:feedback_request, request}
      assert Enum.map(request.criteria, & &1.id) == ["history", "exam"]
    end

    test "an invalid criterion is retried while valid ones are reused", %{session_id: id} do
      respond_with(fn _request -> {:ok, %{"exam" => @generated["exam"]}} end)
      attach(id)
      assert_received {:feedback_request, _}

      respond_with(fn _request -> {:ok, @generated} end)
      attach(id)
      assert_received {:feedback_request, request}
      assert Enum.map(request.criteria, & &1.id) == ["history"]
    end

    test "discarding the session drops its feedback", %{session_id: id} do
      attach(id)
      assert_received {:feedback_request, _}
      :ok = Stations.discard_session(id)

      attach(id)
      assert_received {:feedback_request, _}
    end
  end

  describe "config/runtime.exs" do
    @runtime_config Path.expand("../../../config/runtime.exs", __DIR__)
    @deadline_var "LEARNER_FEEDBACK_DEADLINE_MS"

    # Evaluates the runtime configuration for `env` with the deadline variable set
    # to `value` (or unset for `nil`), without touching the running application.
    defp runtime_deadline(env, value) do
      previous = System.get_env(@deadline_var)
      if value, do: System.put_env(@deadline_var, value), else: System.delete_env(@deadline_var)

      try do
        @runtime_config
        |> Config.Reader.read!(env: env)
        |> Keyword.get(:backend, [])
        |> Keyword.fetch(:learner_feedback_deadline_ms)
      after
        if previous,
          do: System.put_env(@deadline_var, previous),
          else: System.delete_env(@deadline_var)
      end
    end

    test "a positive integer overrides the deadline" do
      assert runtime_deadline(:dev, "45000") == {:ok, 45_000}
      assert runtime_deadline(:dev, " 65000 ") == {:ok, 65_000}
    end

    test "a value above 65 s is capped so the 80 s web wait still covers the request" do
      assert runtime_deadline(:dev, "90000") == {:ok, 65_000}
      assert runtime_deadline(:dev, "3600000") == {:ok, 65_000}
    end

    test "without the variable the configured default stays" do
      assert runtime_deadline(:dev, nil) == :error
    end

    test "an invalid value keeps the configured default" do
      for value <- ["", "0", "-5", "60s", "1.5", "soon"] do
        assert runtime_deadline(:dev, value) == :error
      end
    end

    test "the test environment reads none of it" do
      assert runtime_deadline(:test, "45000") == :error
    end
  end
end
