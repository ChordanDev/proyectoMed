defmodule Backend.Stations.JevDecisionTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias Backend.Stations.JevDecision

  # ============================================================================
  # Test Fixtures & Deterministic Double
  # ============================================================================

  defmodule DeterministicDouble do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(request) do
      case Map.get(request, :candidate_text) do
        "sleep" ->
          Process.sleep(request.deadline_ms + 50)
          {:ok, %{status: :verified}}

        "verified" ->
          {:ok, %{status: :verified, rationale: "Grounded in facts", used_fact_ids: ["fact-1"]}}

        "semantic_refusal" ->
          {:ok, %{status: :semantic_refusal, rationale: "Out of scope"}}

        "low_confidence" ->
          {:ok, %{status: :low_confidence, rationale: "Unclear grounding"}}

        "string_status" ->
          {:ok, %{"status" => "verified"}}

        "invalid_status" ->
          {:ok, %{status: :uncertain}}

        "leaking_status" ->
          {:ok, %{status: "CANDIDATE_SECRET_TEXT_LEAK_IN_STATUS"}}

        "malformed_map" ->
          {:ok, "not a map"}

        "topic_slug_instead_of_id" ->
          # "onset" is the topic of fact-1, but canonical id is "fact-1"
          {:ok, %{status: :verified, used_fact_ids: ["onset"]}}

        "nonexistent_fact" ->
          {:ok, %{status: :verified, used_fact_ids: ["nonexistent-fact-99"]}}

        "upstream_500" ->
          {:error, {:upstream_error, 500}}

        "upstream_503" ->
          {:error, {:upstream_5xx, 503}}

        "upstream_raw_body_leak" ->
          {:error, {:upstream_error, "LEAKED_INTERNAL_SENSITIVE_UPSTREAM_BODY_789"}}

        "timeout_error" ->
          {:error, :timeout}

        "crash" ->
          raise "Boom! Simulated crash containing CANDIDATE_LEAKED_TEXT_456"

        "throw" ->
          throw(:simulated_throw_error)

        _other ->
          {:ok, %{status: :verified}}
      end
    end

    @impl true
    def decide_rubric(request) do
      case request.criterion.id do
        "sleep" ->
          Process.sleep(request.deadline_ms + 50)
          {:ok, %{classification: "adequado", evidence_ids: []}}

        "valid_adequado" ->
          {:ok,
           %{
             classification: "adequado",
             evidence_ids: ["turn-1"],
             rationale: "Matched presentation criterion"
           }}

        "string_keys" ->
          {:ok,
           %{
             "classification" => "adequado",
             "evidence_ids" => ["turn-1"]
           }}

        "disallowed_class" ->
          {:ok,
           %{
             classification: "not_in_allowed_classes",
             evidence_ids: ["turn-1"]
           }}

        "leaking_disallowed_class" ->
          {:ok,
           %{
             classification: "LEAKED_SENSITIVE_STUDENT_PROSE_CLASSIFICATION",
             evidence_ids: ["turn-1"]
           }}

        "hallucinated_evidence" ->
          {:ok,
           %{
             classification: "adequado",
             evidence_ids: ["turn-1", "turn-hallucinated-999"]
           }}

        "leaking_hallucinated_evidence" ->
          {:ok,
           %{
             classification: "adequado",
             evidence_ids: ["turn-1", "LEAKED_CANDIDATE_TEXT_AS_EVIDENCE_ID"]
           }}

        "invalid_evidence_type" ->
          {:ok,
           %{
             classification: "adequado",
             evidence_ids: "turn-1"
           }}

        "malformed_output" ->
          {:ok, 42}

        "upstream_500" ->
          {:error, {:upstream_error, 500}}

        "timeout_error" ->
          {:error, :timeout}

        "crash" ->
          raise "Simulated crash in rubric evaluation"

        _ ->
          {:ok, %{classification: hd(request.allowed_classes), evidence_ids: []}}
      end
    end
  end

  defmodule EchoAdapter do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(request) do
      decide_patient(request, [])
    end

    def decide_patient(request, opts) do
      if pid = opts[:test_pid], do: send(pid, {:echo_patient_request, request})
      {:ok, %{status: :verified}}
    end

    @impl true
    def decide_rubric(request) do
      decide_rubric(request, [])
    end

    def decide_rubric(request, opts) do
      if pid = opts[:test_pid], do: send(pid, {:echo_rubric_request, request})
      {:ok, %{classification: hd(request.allowed_classes), evidence_ids: []}}
    end
  end

  defp sample_package do
    %{
      "station_id" => "cardio-01",
      "version" => "2.0.0",
      "language" => "pt-BR",
      "display_title" => "Dor Torácica",
      "patient_profile" => %{
        "persona" => "João Silva",
        "age" => 55,
        "tone" => "ansioso",
        "presenting_context" => "Pronto-socorro"
      },
      "revealable_facts" => [
        %{
          "id" => "fact-1",
          "topic" => "onset",
          "content" => "A dor começou há 2 horas",
          "disclosure_condition" => "on_request"
        },
        %{
          "id" => "fact-2",
          "topic" => "character",
          "content" => "Aperto no peito",
          "disclosure_condition" => "after_action"
        }
      ],
      "response_rules" => [
        %{"id" => "rule-1", "instruction" => "Se perguntar sobre dor, descrever o aperto"}
      ],
      "rubric" => [%{"id" => "crit-1", "levels" => []}],
      "internal_unrelated_metadata" => "should_be_stripped"
    }
  end

  defp sample_conversation do
    [
      %{role: :student, text: "Olá, bom dia. O que o senhor está sentindo?", session_id: "s-1"},
      %{role: :patient, text: "Doutor, estou com uma dor no peito.", audio_consent: true}
    ]
  end

  # ============================================================================
  # Disabled by Default
  # ============================================================================

  describe "disabled by default adapter" do
    test "decide_patient defaults to DisabledAdapter and returns typed failure" do
      request = %{
        candidate_text: "Sinto uma dor forte no peito há duas horas.",
        package: sample_package(),
        conversation: sample_conversation()
      }

      assert {:error, {:adapter_disabled, message}} = JevDecision.decide_patient(request)
      assert message =~ "disabled by default"
      assert message =~ "human qualification pending"
      assert JevDecision.technical_failure?({:adapter_disabled, message})
    end

    test "decide_rubric defaults to DisabledAdapter and returns typed failure" do
      request = %{
        criterion: %{id: "crit-1", description: "Avaliar caracterização da dor"},
        allowed_classes: ["inadequado", "parcialmente_adequado", "adequado"],
        allowed_evidence_ids: ["turn-1", "turn-2"],
        evidence_pool: [
          %{id: "turn-1", role: "student", text: "Quando começou a dor?"},
          %{id: "turn-2", role: "patient", text: "Começou há 2 horas"}
        ]
      }

      assert {:error, {:adapter_disabled, message}} = JevDecision.decide_rubric(request)
      assert message =~ "disabled by default"
      assert message =~ "human qualification pending"
      assert JevDecision.technical_failure?({:adapter_disabled, message})
    end
  end

  # ============================================================================
  # Patient Decision: Valid Outputs & Strict Output Validation
  # ============================================================================

  describe "decide_patient/2 output validation" do
    test "accepts :verified status with rationale and valid fact IDs" do
      request = %{
        candidate_text: "verified",
        package: sample_package(),
        conversation: sample_conversation()
      }

      assert {:ok, decision} = JevDecision.decide_patient(request, adapter: DeterministicDouble)
      assert decision.status == :verified
      assert decision.rationale == "Grounded in facts"
      assert decision.used_fact_ids == ["fact-1"]
    end

    test "accepts :semantic_refusal status" do
      request = %{
        candidate_text: "semantic_refusal",
        package: sample_package(),
        conversation: sample_conversation()
      }

      assert {:ok, decision} = JevDecision.decide_patient(request, adapter: DeterministicDouble)
      assert decision.status == :semantic_refusal
      assert decision.rationale == "Out of scope"
    end

    test "accepts :low_confidence status" do
      request = %{
        candidate_text: "low_confidence",
        package: sample_package(),
        conversation: sample_conversation()
      }

      assert {:ok, decision} = JevDecision.decide_patient(request, adapter: DeterministicDouble)
      assert decision.status == :low_confidence
    end

    test "normalizes string status to atom" do
      request = %{
        candidate_text: "string_status",
        package: sample_package(),
        conversation: sample_conversation()
      }

      assert {:ok, decision} = JevDecision.decide_patient(request, adapter: DeterministicDouble)
      assert decision.status == :verified
    end

    test "rejects unrecognized status as typed failure (does not treat as uncertainty)" do
      request = %{
        candidate_text: "invalid_status",
        package: sample_package(),
        conversation: sample_conversation()
      }

      assert {:error, {:invalid_response, :unrecognized_patient_status}} =
               JevDecision.decide_patient(request, adapter: DeterministicDouble)
    end

    test "rejects nonexistent fact IDs returned by adapter" do
      request = %{
        candidate_text: "nonexistent_fact",
        package: sample_package(),
        conversation: sample_conversation()
      }

      assert {:error, {:invalid_response, :nonexistent_fact_ids}} =
               JevDecision.decide_patient(request, adapter: DeterministicDouble)
    end

    test "rejects malformed adapter response as typed failure" do
      request = %{
        candidate_text: "malformed_map",
        package: sample_package(),
        conversation: sample_conversation()
      }

      assert {:error, {:malformed_output, :expected_map}} =
               JevDecision.decide_patient(request, adapter: DeterministicDouble)
    end
  end

  # ============================================================================
  # Regression (2): Fact ID Canonical Validation (Reject Topic Slug)
  # ============================================================================

  describe "canonical fact ID validation" do
    test "strictly rejects fact topic slug when canonical fact ID differs" do
      # "onset" is the topic of fact-1, but the canonical ID is "fact-1"
      request = %{
        candidate_text: "topic_slug_instead_of_id",
        package: sample_package(),
        conversation: sample_conversation()
      }

      assert {:error, {:invalid_response, :nonexistent_fact_ids}} =
               JevDecision.decide_patient(request, adapter: DeterministicDouble)
    end
  end

  # ============================================================================
  # Regression (3): Error Sanitization (Zero Leakage)
  # ============================================================================

  describe "error sanitization (zero leakage of candidate/learner/upstream text)" do
    test "adapter crash does not leak raw exception message" do
      request = %{
        candidate_text: "crash",
        package: sample_package(),
        conversation: sample_conversation()
      }

      # Result must be sanitized atom, not carrying the exception string with leaked text
      assert {:error, {:technical_failure, :adapter_crashed}} =
               JevDecision.decide_patient(request, adapter: DeterministicDouble)
    end

    test "adapter throwing an unhandled throw returns technical failure without killing caller" do
      request = %{
        candidate_text: "throw",
        package: sample_package(),
        conversation: sample_conversation()
      }

      assert {:error, {:technical_failure, :adapter_threw}} =
               JevDecision.decide_patient(request, adapter: DeterministicDouble)
    end

    test "unrecognized model status does not leak candidate text in error tuple" do
      request = %{
        candidate_text: "leaking_status",
        package: sample_package(),
        conversation: sample_conversation()
      }

      assert {:error, {:invalid_response, :unrecognized_patient_status}} =
               JevDecision.decide_patient(request, adapter: DeterministicDouble)
    end

    test "disallowed rubric classification does not leak classification prose" do
      request = %{
        criterion: %{id: "leaking_disallowed_class", description: "Desc"},
        allowed_classes: ["inadequado", "adequado"],
        allowed_evidence_ids: ["turn-1"],
        evidence_pool: [%{id: "turn-1", role: "student", text: "Texto"}]
      }

      assert {:error, {:invalid_response, :disallowed_classification}} =
               JevDecision.decide_rubric(request, adapter: DeterministicDouble)
    end

    test "hallucinated evidence ID does not leak arbitrary ID prose" do
      request = %{
        criterion: %{id: "leaking_hallucinated_evidence", description: "Desc"},
        allowed_classes: ["inadequado", "adequado"],
        allowed_evidence_ids: ["turn-1"],
        evidence_pool: [%{id: "turn-1", role: "student", text: "Texto"}]
      }

      assert {:error, {:invalid_response, :nonexistent_evidence_ids}} =
               JevDecision.decide_rubric(request, adapter: DeterministicDouble)
    end

    test "upstream error body does not leak raw upstream response string" do
      request = %{
        candidate_text: "upstream_raw_body_leak",
        package: sample_package(),
        conversation: sample_conversation()
      }

      assert {:error, :upstream_error} =
               JevDecision.decide_patient(request, adapter: DeterministicDouble)
    end
  end

  # ============================================================================
  # Regression (4): Monotonic Absolute Deadline & Budget Sharing
  # ============================================================================

  describe "monotonic absolute deadline & remaining budget" do
    test "immediately returns {:error, :timeout} if monotonic deadline is already expired" do
      expired_deadline = JevDecision.monotonic_now_ms() - 50

      request = %{
        candidate_text: "verified",
        package: sample_package(),
        conversation: sample_conversation()
      }

      assert {:error, :timeout} =
               JevDecision.decide_patient(
                 request,
                 adapter: DeterministicDouble,
                 deadline_at_monotonic_ms: expired_deadline
               )
    end

    test "immediately returns {:error, :timeout} if remaining budget is non-positive" do
      request = %{
        candidate_text: "verified",
        package: sample_package(),
        conversation: sample_conversation(),
        remaining_budget_ms: 0
      }

      assert {:error, :timeout} =
               JevDecision.decide_patient(request, adapter: DeterministicDouble)
    end

    test "monotonic deadline budget is shared across sequential attempts and prevents new 3s window" do
      # Set a total budget of 120ms
      deadline_at = JevDecision.monotonic_deadline_at(120)

      request = %{
        candidate_text: "verified",
        package: sample_package(),
        conversation: sample_conversation()
      }

      # Attempt 1: succeeds and consumes some time
      assert {:ok, _} =
               JevDecision.decide_patient(
                 request,
                 adapter: DeterministicDouble,
                 deadline_at_monotonic_ms: deadline_at
               )

      # Attempt 2 (single retry simulation): uses the same deadline_at.
      # If candidate_text is "sleep", the double attempts to sleep for deadline_ms + 50.
      # It must time out based on the remaining budget, NEVER getting a fresh 3_000ms window!
      sleep_request = %{request | candidate_text: "sleep"}

      t_before = JevDecision.monotonic_now_ms()

      assert {:error, :timeout} =
               JevDecision.decide_patient(
                 sleep_request,
                 adapter: DeterministicDouble,
                 deadline_at_monotonic_ms: deadline_at
               )

      t_after = JevDecision.monotonic_now_ms()
      elapsed = t_after - t_before

      # Elapsed time should be well under 300ms (verifying it did NOT get a fresh 3,000ms window)
      assert elapsed < 300
    end

    test "monotonic helper functions calculate remaining budget correctly" do
      now = JevDecision.monotonic_now_ms()
      future_deadline = JevDecision.monotonic_deadline_at(500)

      assert future_deadline >= now + 490
      assert JevDecision.remaining_budget_ms(future_deadline) > 0
      assert JevDecision.remaining_budget_ms(now - 100) == 0
    end
  end

  # ============================================================================
  # Regression (1): Minimized Patient Request Detail (package_id, version, trust, seq, disclosure_condition)
  # ============================================================================

  describe "regression (1): context minimization and labelling" do
    test "provides package_id, package_version, latest_learner_turn, seq, and trust markers" do
      turns = [
        %{role: :student, text: "Primeira pergunta", session_id: "s-1"},
        %{role: :patient, text: "Primeira resposta", session_id: "s-1"},
        %{role: :student, text: "Segunda pergunta do estudante", session_id: "s-1"}
      ]

      request = %{
        candidate_text: "verified",
        package: sample_package(),
        conversation: turns
      }

      assert {:ok, _} =
               JevDecision.decide_patient(
                 request,
                 adapter: EchoAdapter,
                 test_pid: self()
               )

      assert_received {:echo_patient_request, echo}

      # 1. Package ID and version present at top-level and in package
      assert echo.package_id == "cardio-01"
      assert echo.package_version == "2.0.0"
      assert echo.package["station_id"] == "cardio-01"
      assert echo.package["version"] == "2.0.0"

      # 2. Latest learner turn identified
      assert echo.latest_learner_turn.role == :student
      assert echo.latest_learner_turn.text == "Segunda pergunta do estudante"
      assert echo.latest_learner_turn.seq == 3
      assert echo.latest_learner_turn.trust == :untrusted

      # 3. Seq and trust explicitly assigned to all conversation turns
      assert length(echo.conversation) == 3
      [t1, t2, t3] = echo.conversation

      assert t1.seq == 1
      assert t1.role == :student
      assert t1.trust == :untrusted

      assert t2.seq == 2
      assert t2.role == :patient
      assert t2.trust == :trusted

      assert t3.seq == 3
      assert t3.role == :student
      assert t3.trust == :untrusted

      # 4. Authored disclosure_condition preserved on revealable_facts
      facts = echo.package["revealable_facts"]
      assert length(facts) == 2

      f1 = Enum.find(facts, &(&1["id"] == "fact-1"))
      assert f1["disclosure_condition"] == "on_request"
      assert f1["content"] == "A dor começou há 2 horas"

      f2 = Enum.find(facts, &(&1["id"] == "fact-2"))
      assert f2["disclosure_condition"] == "after_action"
      assert f2["content"] == "Aperto no peito"
    end
  end

  # ============================================================================
  # Patient Decision: Technical Failures (5xx, Timeout, Crash)
  # ============================================================================

  describe "decide_patient/2 technical failure handling" do
    test "upstream 500 error returns typed technical failure rather than uncertainty" do
      request = %{
        candidate_text: "upstream_500",
        package: sample_package(),
        conversation: sample_conversation()
      }

      assert {:error, {:upstream_5xx, 500}} =
               JevDecision.decide_patient(request, adapter: DeterministicDouble)

      assert JevDecision.technical_failure?({:upstream_5xx, 500})
    end

    test "upstream 503 error returns typed technical failure" do
      request = %{
        candidate_text: "upstream_503",
        package: sample_package(),
        conversation: sample_conversation()
      }

      assert {:error, {:upstream_5xx, 503}} =
               JevDecision.decide_patient(request, adapter: DeterministicDouble)
    end

    test "adapter timeout error returns typed failure" do
      request = %{
        candidate_text: "timeout_error",
        package: sample_package(),
        conversation: sample_conversation()
      }

      assert {:error, :timeout} =
               JevDecision.decide_patient(request, adapter: DeterministicDouble)

      assert JevDecision.technical_failure?(:timeout)
    end

    test "deadline expiration halts execution and returns typed :timeout" do
      request = %{
        candidate_text: "sleep",
        package: sample_package(),
        conversation: sample_conversation(),
        deadline_ms: 30
      }

      assert {:error, :timeout} =
               JevDecision.decide_patient(request, adapter: DeterministicDouble, deadline_ms: 30)
    end
  end

  # ============================================================================
  # Patient Decision: Strict Input Validation
  # ============================================================================

  describe "decide_patient/2 input validation" do
    test "rejects non-map request" do
      assert {:error, {:invalid_request, :expected_map}} =
               JevDecision.decide_patient("invalid", adapter: DeterministicDouble)
    end

    test "rejects missing or empty candidate text" do
      assert {:error, {:invalid_request, :invalid_candidate_text}} =
               JevDecision.decide_patient(
                 %{package: sample_package(), conversation: []},
                 adapter: DeterministicDouble
               )

      assert {:error, {:invalid_request, :invalid_candidate_text}} =
               JevDecision.decide_patient(
                 %{candidate_text: "   ", package: sample_package(), conversation: []},
                 adapter: DeterministicDouble
               )
    end

    test "rejects candidate text exceeding max_characters" do
      long_text = String.duplicate("a", 2_005)

      assert {:error, {:invalid_request, :context_limit_exceeded}} =
               JevDecision.decide_patient(
                 %{candidate_text: long_text, package: sample_package(), conversation: []},
                 adapter: DeterministicDouble
               )
    end

    test "rejects invalid package" do
      assert {:error, {:invalid_request, :invalid_package}} =
               JevDecision.decide_patient(
                 %{candidate_text: "Valid text", package: nil, conversation: []},
                 adapter: DeterministicDouble
               )
    end

    test "rejects invalid conversation" do
      assert {:error, {:invalid_request, :invalid_conversation}} =
               JevDecision.decide_patient(
                 %{
                   candidate_text: "Valid text",
                   package: sample_package(),
                   conversation: :not_list
                 },
                 adapter: DeterministicDouble
               )
    end

    test "rejects invalid deadline" do
      assert {:error, {:invalid_request, :invalid_deadline}} =
               JevDecision.decide_patient(
                 %{
                   candidate_text: "Valid text",
                   package: sample_package(),
                   conversation: [],
                   deadline_ms: -100
                 },
                 adapter: DeterministicDouble
               )
    end
  end

  # ============================================================================
  # Rubric Decision: Closed-Set Classification & Reject Nonexistent Evidence IDs
  # ============================================================================

  describe "decide_rubric/2 output validation" do
    test "accepts valid closed-set classification and subset of allowed evidence IDs" do
      request = %{
        criterion: %{id: "valid_adequado", description: "Avaliar caracterização da dor"},
        allowed_classes: ["inadequado", "parcialmente_adequado", "adequado"],
        allowed_evidence_ids: ["turn-1", "turn-2"],
        evidence_pool: [
          %{id: "turn-1", role: "student", text: "Quando começou a dor?"},
          %{id: "turn-2", role: "patient", text: "Começou há 2 horas"}
        ]
      }

      assert {:ok, decision} = JevDecision.decide_rubric(request, adapter: DeterministicDouble)
      assert decision.classification == "adequado"
      assert decision.evidence_ids == ["turn-1"]
      assert decision.rationale == "Matched presentation criterion"
    end

    test "accepts string keys in adapter output" do
      request = %{
        criterion: %{id: "string_keys", description: "Desc"},
        allowed_classes: ["inadequado", "adequado"],
        allowed_evidence_ids: ["turn-1"],
        evidence_pool: [%{id: "turn-1", role: "student", text: "Texto"}]
      }

      assert {:ok, decision} = JevDecision.decide_rubric(request, adapter: DeterministicDouble)
      assert decision.classification == "adequado"
      assert decision.evidence_ids == ["turn-1"]
    end

    test "strictly rejects classification not in allowed_classes" do
      request = %{
        criterion: %{id: "disallowed_class", description: "Desc"},
        allowed_classes: ["inadequado", "adequado"],
        allowed_evidence_ids: ["turn-1"],
        evidence_pool: [%{id: "turn-1", role: "student", text: "Texto"}]
      }

      assert {:error, {:invalid_response, :disallowed_classification}} =
               JevDecision.decide_rubric(request, adapter: DeterministicDouble)
    end

    test "strictly rejects nonexistent evidence IDs returned by model/adapter" do
      request = %{
        criterion: %{id: "hallucinated_evidence", description: "Desc"},
        allowed_classes: ["inadequado", "adequado"],
        allowed_evidence_ids: ["turn-1"],
        evidence_pool: [%{id: "turn-1", role: "student", text: "Texto"}]
      }

      assert {:error, {:invalid_response, :nonexistent_evidence_ids}} =
               JevDecision.decide_rubric(request, adapter: DeterministicDouble)
    end

    test "rejects non-list evidence_ids returned by adapter" do
      request = %{
        criterion: %{id: "invalid_evidence_type", description: "Desc"},
        allowed_classes: ["inadequado", "adequado"],
        allowed_evidence_ids: ["turn-1"],
        evidence_pool: [%{id: "turn-1", role: "student", text: "Texto"}]
      }

      assert {:error, {:invalid_response, :invalid_evidence_ids}} =
               JevDecision.decide_rubric(request, adapter: DeterministicDouble)
    end

    test "rejects malformed output not matching map" do
      request = %{
        criterion: %{id: "malformed_output", description: "Desc"},
        allowed_classes: ["inadequado", "adequado"],
        allowed_evidence_ids: ["turn-1"],
        evidence_pool: [%{id: "turn-1", role: "student", text: "Texto"}]
      }

      assert {:error, {:malformed_output, :expected_map}} =
               JevDecision.decide_rubric(request, adapter: DeterministicDouble)
    end
  end

  # ============================================================================
  # Rubric Decision: Technical Failures
  # ============================================================================

  describe "decide_rubric/2 technical failure handling" do
    test "upstream 500 returns typed technical failure rather than uncertainty" do
      request = %{
        criterion: %{id: "upstream_500", description: "Desc"},
        allowed_classes: ["inadequado", "adequado"],
        allowed_evidence_ids: ["turn-1"],
        evidence_pool: [%{id: "turn-1", role: "student", text: "Texto"}]
      }

      assert {:error, {:upstream_5xx, 500}} =
               JevDecision.decide_rubric(request, adapter: DeterministicDouble)
    end

    test "timeout returns typed technical failure" do
      request = %{
        criterion: %{id: "timeout_error", description: "Desc"},
        allowed_classes: ["inadequado", "adequado"],
        allowed_evidence_ids: ["turn-1"],
        evidence_pool: [%{id: "turn-1", role: "student", text: "Texto"}]
      }

      assert {:error, :timeout} =
               JevDecision.decide_rubric(request, adapter: DeterministicDouble)
    end

    test "deadline expiration terminates execution and returns :timeout" do
      request = %{
        criterion: %{id: "sleep", description: "Desc"},
        allowed_classes: ["inadequado", "adequado"],
        allowed_evidence_ids: ["turn-1"],
        evidence_pool: [%{id: "turn-1", role: "student", text: "Texto"}],
        deadline_ms: 30
      }

      assert {:error, :timeout} =
               JevDecision.decide_rubric(request, adapter: DeterministicDouble, deadline_ms: 30)
    end

    test "adapter crash returns typed technical failure" do
      request = %{
        criterion: %{id: "crash", description: "Desc"},
        allowed_classes: ["inadequado", "adequado"],
        allowed_evidence_ids: ["turn-1"],
        evidence_pool: [%{id: "turn-1", role: "student", text: "Texto"}]
      }

      assert {:error, {:technical_failure, :adapter_crashed}} =
               JevDecision.decide_rubric(request, adapter: DeterministicDouble)
    end
  end

  # ============================================================================
  # Rubric Decision: Strict Input Validation
  # ============================================================================

  describe "decide_rubric/2 input validation" do
    test "rejects non-map request" do
      assert {:error, {:invalid_request, :expected_map}} =
               JevDecision.decide_rubric(123, adapter: DeterministicDouble)
    end

    test "rejects missing or invalid criterion" do
      assert {:error, {:invalid_request, :invalid_criterion}} =
               JevDecision.decide_rubric(
                 %{
                   criterion: %{},
                   allowed_classes: ["a"],
                   allowed_evidence_ids: [],
                   evidence_pool: []
                 },
                 adapter: DeterministicDouble
               )
    end

    test "rejects empty or invalid allowed_classes" do
      assert {:error, {:invalid_request, :invalid_allowed_classes}} =
               JevDecision.decide_rubric(
                 %{
                   criterion: %{id: "c1"},
                   allowed_classes: [],
                   allowed_evidence_ids: [],
                   evidence_pool: []
                 },
                 adapter: DeterministicDouble
               )

      assert {:error, {:invalid_request, :invalid_allowed_classes}} =
               JevDecision.decide_rubric(
                 %{
                   criterion: %{id: "c1"},
                   allowed_classes: [:not_a_string],
                   allowed_evidence_ids: [],
                   evidence_pool: []
                 },
                 adapter: DeterministicDouble
               )
    end

    test "rejects non-list allowed_evidence_ids" do
      assert {:error, {:invalid_request, :invalid_allowed_evidence_ids}} =
               JevDecision.decide_rubric(
                 %{
                   criterion: %{id: "c1"},
                   allowed_classes: ["a"],
                   allowed_evidence_ids: "not_a_list",
                   evidence_pool: []
                 },
                 adapter: DeterministicDouble
               )
    end

    test "rejects non-list evidence_pool" do
      assert {:error, {:invalid_request, :invalid_evidence_pool}} =
               JevDecision.decide_rubric(
                 %{
                   criterion: %{id: "c1"},
                   allowed_classes: ["a"],
                   allowed_evidence_ids: [],
                   evidence_pool: :not_a_list
                 },
                 adapter: DeterministicDouble
               )
    end
  end

  # ============================================================================
  # Context Minimization and Bounding: Rubric
  # ============================================================================

  describe "context minimization: rubric" do
    test "minimizes rubric criterion and evidence pool" do
      request = %{
        criterion: %{
          id: "c-1",
          description: "Desc",
          extra_internal_field: "strip_this"
        },
        allowed_classes: ["adequado"],
        allowed_evidence_ids: ["t-1"],
        evidence_pool: [
          %{
            id: "t-1",
            role: "student",
            text: "Texto",
            extra_session_token: "secret-123"
          }
        ]
      }

      assert {:ok, _} =
               JevDecision.decide_rubric(request, adapter: EchoAdapter, test_pid: self())

      assert_received {:echo_rubric_request, echo}

      refute Map.has_key?(echo.criterion, :extra_internal_field)
      assert echo.criterion.id == "c-1"

      evidence_item = hd(echo.evidence_pool)
      refute Map.has_key?(evidence_item, :extra_session_token)
      assert evidence_item.id == "t-1"
    end
  end

  # ============================================================================
  # Privacy-Safe Logging
  # ============================================================================

  describe "privacy-safe logging" do
    test "logs warnings for technical failures without leaking patient or learner content" do
      sensitive_candidate = "SENSITIVE_PATIENT_CLINICAL_DISCLOSURE_98765"
      sensitive_student = "SENSITIVE_STUDENT_INQUIRY_12345"

      request = %{
        candidate_text: sensitive_candidate,
        package: sample_package(),
        conversation: [%{role: :student, text: sensitive_student}]
      }

      log =
        capture_log(fn ->
          # Triggers upstream_500 on candidate "upstream_500"
          req_500 = %{request | candidate_text: "upstream_500"}
          JevDecision.decide_patient(req_500, adapter: DeterministicDouble)

          # Triggers timeout
          req_timeout = %{request | candidate_text: "timeout_error"}
          JevDecision.decide_patient(req_timeout, adapter: DeterministicDouble)
        end)

      # Log contains error types and system markers
      assert log =~ "[JevDecision]"
      assert log =~ "Upstream HTTP 5xx: 500"
      assert log =~ "Request timed out"

      # Log strictly NEVER contains learner or patient content
      refute log =~ sensitive_candidate
      refute log =~ sensitive_student
      refute log =~ "SENSITIVE"
    end
  end
end
