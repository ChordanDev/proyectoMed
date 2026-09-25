defmodule Backend.Stations.CandidateGateTest do
  use ExUnit.Case, async: true

  alias Backend.Stations.CandidateGate
  alias Backend.Stations.JevDecision
  alias Backend.Stations.StationAI.BoundedReply

  # ============================================================================
  # Test Adapter Doubles
  # ============================================================================

  defmodule DoubleAdapter do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(request) do
      decide_candidate(Map.get(request, :candidate_text), request)
    end

    defp decide_candidate("verified_text", _req) do
      {:ok, %{status: :verified, rationale: "Well-grounded in facts", used_fact_ids: ["fact-1"]}}
    end

    defp decide_candidate("ungrounded_hallucination", _req) do
      {:ok, %{status: :semantic_refusal, rationale: "Hallucination outside package facts"}}
    end

    defp decide_candidate("contradicts_history", _req) do
      {:ok, %{status: :semantic_refusal, rationale: "Contradicts medical history"}}
    end

    defp decide_candidate("premature_disclosure", _req) do
      {:ok, %{status: :semantic_refusal, rationale: "Discloses ECG results prematurely"}}
    end

    defp decide_candidate("role_violation_doctor", _req) do
      {:ok, %{status: :semantic_refusal, rationale: "Patient candidate acts as doctor"}}
    end

    defp decide_candidate("prompt_injection_attempt", _req) do
      {:ok, %{status: :semantic_refusal, rationale: "Prompt injection detected in candidate"}}
    end

    defp decide_candidate("low_confidence_text", _req) do
      {:ok, %{status: :low_confidence, rationale: "Uncertain clinical grounding"}}
    end

    defp decide_candidate("upstream_500", _req), do: {:error, {:upstream_5xx, 500}}
    defp decide_candidate("upstream_503", _req), do: {:error, {:upstream_5xx, 503}}
    defp decide_candidate("adapter_timeout", _req), do: {:error, :timeout}

    defp decide_candidate("adapter_disabled", _req) do
      {:error, {:adapter_disabled, "Adapter disabled in test"}}
    end

    defp decide_candidate("malformed_output", _req) do
      {:error, {:malformed_output, :missing_status}}
    end

    defp decide_candidate("sleep_beyond_deadline", request) do
      Process.sleep(request.deadline_ms + 40)
      {:ok, %{status: :verified}}
    end

    defp decide_candidate(text, _req) when is_binary(text) do
      cond do
        String.starts_with?(text, "regen_ok") ->
          {:ok, %{status: :verified}}

        String.starts_with?(text, "regen_refused") ->
          {:ok, %{status: :semantic_refusal, rationale: "Regenerated reply refused"}}

        String.starts_with?(text, "regen_low_confidence") ->
          {:ok, %{status: :low_confidence, rationale: "Regenerated reply low confidence"}}

        true ->
          {:ok, %{status: :verified}}
      end
    end

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  defmodule ExplosiveAdapter do
    @behaviour Backend.Stations.JevDecision.Adapter

    @impl true
    def decide_patient(_request) do
      raise "ExplosiveAdapter MUST NEVER be called when deny checks fire!"
    end

    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

  # ============================================================================
  # Package Helpers
  # ============================================================================

  defp base_package(custom \\ %{}) do
    Map.merge(
      %{
        "station_id" => "chest-pain-assessment",
        "version" => "2.0.0",
        "language" => "pt-BR",
        "display_title" => "Dor Torácica",
        "revealable_facts" => [
          %{
            "id" => "fact-1",
            "topic" => "onset",
            "fact" => "A dor começou há 2 horas durante caminhada.",
            "disclosure_condition" => "when asked about pain onset"
          }
        ],
        "response_rules" => [
          %{"id" => "polite"},
          %{"id" => "length-cap", "max_length" => 500}
        ],
        "approved_templates" => [
          %{
            "template_id" => "opening-summary",
            "text" => "Resuma o motivo da consulta.",
            "applicability" => "Use after opening assessment."
          },
          %{
            "template_id" => "unconditional-ack",
            "text" => "Compreendo, doutor.",
            "applicability" => "unconditional"
          },
          %{
            "template_id" => "unconditional-map",
            "text" => "Sim, estou ciente.",
            "applicability" => %{"type" => "unconditional"}
          },
          %{
            "template_id" => "predicate-template",
            "text" => "Estou pronto para o exame.",
            "applicability" => fn state -> state[:ready_for_exam] == true end
          }
        ]
      },
      custom
    )
  end

  defp sample_conversation do
    [
      %{
        "role" => "learner",
        "seq" => 1,
        "text" => "Olá, como posso ajudar?",
        "trust" => "untrusted"
      },
      %{"role" => "patient", "seq" => 2, "text" => "Estou com muita dor.", "trust" => "trusted"}
    ]
  end

  # ============================================================================
  # 1. Deny-First Check Unit Tests (BoundedReply & Precedence)
  # ============================================================================

  describe "BoundedReply.check_violations/2" do
    test "returns :ok for clean pt-BR text" do
      package = base_package()
      assert :ok = BoundedReply.check_violations("A dor começou durante uma caminhada.", package)
    end

    test "returns :ok for canonical refusal text" do
      package = base_package()

      assert :ok =
               BoundedReply.check_violations(Backend.Stations.StationAI.refusal_text(), package)
    end

    test "rejects non-binary input as malformed" do
      package = base_package()
      assert {:error, {:denied, :malformed}} = BoundedReply.check_violations(nil, package)
      assert {:error, {:denied, :malformed}} = BoundedReply.check_violations(123, package)
      assert {:error, {:denied, :malformed}} = BoundedReply.check_violations(:atom_text, package)
      assert {:error, {:denied, :malformed}} = BoundedReply.check_violations(%{}, package)
    end

    test "rejects empty and whitespace-only text as malformed" do
      package = base_package()
      assert {:error, {:denied, :malformed}} = BoundedReply.check_violations("", package)
      assert {:error, {:denied, :malformed}} = BoundedReply.check_violations("   \n\t  ", package)
    end

    test "rejects text exceeding 2000 characters as malformed" do
      package = base_package()
      long_text = String.duplicate("a", 2001)
      assert {:error, {:denied, :malformed}} = BoundedReply.check_violations(long_text, package)
    end

    test "rejects roleplay leakage patterns" do
      package = base_package()

      leakage_samples = [
        "Sou uma inteligência artificial.",
        "Sou um modelo de linguagem.",
        "Como IA, não posso responder a isso.",
        "Minhas limitações não permitem.",
        "I am an AI assistant.",
        "Sure, I'd be happy to help."
      ]

      for text <- leakage_samples do
        assert {:error, {:denied, :roleplay_leakage}} =
                 BoundedReply.check_violations(text, package)
      end
    end

    test "rejects English containment violations in pt-BR packages" do
      package = base_package(%{"language" => "pt-BR"})

      assert {:error, {:denied, :language_containment}} =
               BoundedReply.check_violations("Yes, the pain started this morning.", package)

      assert {:error, {:denied, :language_containment}} =
               BoundedReply.check_violations("No, I don't think so.", package)
    end

    test "allows English text when package language is not pt-BR" do
      package = base_package(%{"language" => "en-US"})
      assert :ok = BoundedReply.check_violations("Yes, the pain started this morning.", package)
    end

    test "rejects insults when polite response_rule is active" do
      package = base_package()

      assert {:error, {:denied, :response_rules}} =
               BoundedReply.check_violations("Cale a boca seu idiota!", package)
    end

    test "rejects text exceeding response_rule max_length / length-cap" do
      package =
        base_package(%{
          "response_rules" => [%{"id" => "length-cap", "max_length" => 10}]
        })

      assert {:error, {:denied, :response_rules}} =
               BoundedReply.check_violations("Esta frase tem mais de 10 caracteres.", package)
    end

    test "never substitutes clinical refusal on deny (returns typed error tuple)" do
      package = base_package()
      refusal = Backend.Stations.StationAI.refusal_text()

      res = BoundedReply.check_violations("Sou uma IA.", package)
      assert res != refusal
      assert res == {:error, {:denied, :roleplay_leakage}}
    end

    test "bound/2 preserves existing behavior with check_violations under the hood" do
      package = base_package()
      refusal = Backend.Stations.StationAI.refusal_text()

      # Malformed replaced with refusal
      assert BoundedReply.bound(nil, package) == refusal
      assert BoundedReply.bound("", package) == refusal
      assert BoundedReply.bound("Sou uma IA.", package) == refusal
      assert BoundedReply.bound("Yes, the pain started.", package) == refusal

      # Clean text untouched
      clean = "A dor começou durante a caminhada."
      assert BoundedReply.bound(clean, package) == clean

      # Verbatim refusal untouched
      assert BoundedReply.bound(refusal, package) == refusal
    end
  end

  # ============================================================================
  # 2. Deny Precedence Before Jev Invocation
  # ============================================================================

  describe "Deny precedence over Jev verification" do
    test "malformed candidate is rejected without calling Jev adapter" do
      package = base_package()

      assert {:error, {:denied, :malformed}} =
               CandidateGate.verify_and_deliver(
                 "",
                 package,
                 sample_conversation(),
                 adapter: ExplosiveAdapter
               )
    end

    test "roleplay leakage candidate is rejected without calling Jev adapter" do
      package = base_package()

      assert {:error, {:denied, :roleplay_leakage}} =
               CandidateGate.verify_and_deliver(
                 "Sou uma inteligência artificial criada para ajudar.",
                 package,
                 sample_conversation(),
                 adapter: ExplosiveAdapter
               )
    end

    test "English marker candidate is rejected without calling Jev adapter" do
      package = base_package()

      assert {:error, {:denied, :language_containment}} =
               CandidateGate.verify_and_deliver(
                 "Yes, the pain is sharp.",
                 package,
                 sample_conversation(),
                 adapter: ExplosiveAdapter
               )
    end

    test "response_rule violation is rejected without calling Jev adapter" do
      package = base_package()

      assert {:error, {:denied, :response_rules}} =
               CandidateGate.verify_and_deliver(
                 "Você é um idiota!",
                 package,
                 sample_conversation(),
                 adapter: ExplosiveAdapter
               )
    end
  end

  # ============================================================================
  # 3. Approved Template Check (Option B Fail Closed)
  # ============================================================================

  describe "Approved Template Check (Option B fail closed)" do
    test "byte-identical match with prose applicability fails closed to Jev" do
      package = base_package()
      # "Resuma o motivo da consulta." has prose applicability: "Use after opening assessment."
      # Per Option B, it NEVER bypasses Jev. It must route to Jev!
      assert false == CandidateGate.template_bypass?("Resuma o motivo da consulta.", package)

      # When verified through CandidateGate, Jev IS called:
      assert {:ok, "Resuma o motivo da consulta."} =
               CandidateGate.verify_and_deliver(
                 "Resuma o motivo da consulta.",
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter
               )
    end

    test "byte-identical match with explicit 'unconditional' applicability bypasses Jev" do
      package = base_package()
      text = "Compreendo, doutor."

      # Bypasses without Jev
      assert true == CandidateGate.template_bypass?(text, package)

      # Uses ExplosiveAdapter to prove Jev is NEVER called
      assert {:ok, ^text} =
               CandidateGate.verify_and_deliver(
                 text,
                 package,
                 sample_conversation(),
                 adapter: ExplosiveAdapter
               )
    end

    test "byte-identical match with %{'type' => 'unconditional'} applicability bypasses Jev" do
      package = base_package()
      text = "Sim, estou ciente."

      assert true == CandidateGate.template_bypass?(text, package)

      assert {:ok, ^text} =
               CandidateGate.verify_and_deliver(
                 text,
                 package,
                 sample_conversation(),
                 adapter: ExplosiveAdapter
               )
    end

    test "executable predicate function bypasses when evaluating to true and fails closed when false" do
      package = base_package()
      text = "Estou pronto para o exame."

      # False when case_state condition is not met
      assert false ==
               CandidateGate.template_bypass?(text, package, case_state: %{ready_for_exam: false})

      # Routes to Jev when predicate fails
      assert {:ok, ^text} =
               CandidateGate.verify_and_deliver(
                 text,
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter,
                 case_state: %{ready_for_exam: false}
               )

      # Bypasses Jev when predicate evaluates to true
      assert true ==
               CandidateGate.template_bypass?(text, package, case_state: %{ready_for_exam: true})

      assert {:ok, ^text} =
               CandidateGate.verify_and_deliver(
                 text,
                 package,
                 sample_conversation(),
                 adapter: ExplosiveAdapter,
                 case_state: %{ready_for_exam: true}
               )
    end

    test "caller-supplied predicate_evaluator function can evaluate applicability" do
      package = base_package()
      text = "Resuma o motivo da consulta."

      evaluator = fn template, _opts ->
        template["template_id"] == "opening-summary"
      end

      assert true == CandidateGate.template_bypass?(text, package, predicate_evaluator: evaluator)

      assert {:ok, ^text} =
               CandidateGate.verify_and_deliver(
                 text,
                 package,
                 sample_conversation(),
                 adapter: ExplosiveAdapter,
                 predicate_evaluator: evaluator
               )
    end

    test "altered, trailing-spaced, or interpolated text does NOT match byte-identically" do
      package = base_package()

      # Trailing space
      altered_space = "Compreendo, doutor. "
      assert false == CandidateGate.template_bypass?(altered_space, package)

      # Changed punctuation
      altered_punct = "Compreendo, doutor!"
      assert false == CandidateGate.template_bypass?(altered_punct, package)

      # Interpolated / prefixed text
      altered_prefix = "Sim, compreendo, doutor."
      assert false == CandidateGate.template_bypass?(altered_prefix, package)
    end

    test "model-provided template ID alone NEVER authorizes a bypass" do
      package = base_package()
      different_text = "Estou me sentindo melhor agora."

      # Caller passes template_id: "unconditional-ack", but text does not match byte-identically
      assert false ==
               CandidateGate.template_bypass?(
                 different_text,
                 package,
                 template_id: "unconditional-ack"
               )

      # Template ID mismatch against matching text fails bypass
      matching_text = "Compreendo, doutor."

      assert false ==
               CandidateGate.template_bypass?(
                 matching_text,
                 package,
                 template_id: "wrong-template-id"
               )
    end

    test "shortness or conversational tone NEVER authorizes a bypass" do
      package = base_package()

      # "Estou bem." is short and natural, but NOT in approved_templates
      short_text = "Estou bem."
      assert false == CandidateGate.template_bypass?(short_text, package)
    end

    test "station_id or package version mismatch fails template bypass" do
      package = base_package()
      text = "Compreendo, doutor."

      # Station ID mismatch
      assert false == CandidateGate.template_bypass?(text, package, station_id: "other-station")

      # Version mismatch
      assert false == CandidateGate.template_bypass?(text, package, version: "3.0.0")
    end
  end

  # ============================================================================
  # 4. Jev Verification Categories (Groundedness, Contradiction, Injection, etc.)
  # ============================================================================

  describe "Jev verification categories" do
    test "delivers verified grounded patient candidate" do
      package = base_package()
      candidate = "verified_text"

      assert {:ok, ^candidate} =
               CandidateGate.verify_and_deliver(
                 candidate,
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter
               )
    end

    test "rejects ungrounded hallucination" do
      package = base_package()
      candidate = "ungrounded_hallucination"

      assert {:error, {:refused, :semantic_refusal}} =
               CandidateGate.verify_and_deliver(
                 candidate,
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter,
                 can_retry?: false
               )
    end

    test "rejects candidate contradicting medical history" do
      package = base_package()
      candidate = "contradicts_history"

      assert {:error, {:refused, :semantic_refusal}} =
               CandidateGate.verify_and_deliver(
                 candidate,
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter,
                 can_retry?: false
               )
    end

    test "rejects premature clinical disclosure" do
      package = base_package()
      candidate = "premature_disclosure"

      assert {:error, {:refused, :semantic_refusal}} =
               CandidateGate.verify_and_deliver(
                 candidate,
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter,
                 can_retry?: false
               )
    end

    test "rejects patient candidate breaking role (acting as doctor)" do
      package = base_package()
      candidate = "role_violation_doctor"

      assert {:error, {:refused, :semantic_refusal}} =
               CandidateGate.verify_and_deliver(
                 candidate,
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter,
                 can_retry?: false
               )
    end

    test "rejects prompt injection attempt" do
      package = base_package()
      candidate = "prompt_injection_attempt"

      assert {:error, {:refused, :semantic_refusal}} =
               CandidateGate.verify_and_deliver(
                 candidate,
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter,
                 can_retry?: false
               )
    end

    test "rejects low confidence candidate" do
      package = base_package()
      candidate = "low_confidence_text"

      assert {:error, {:refused, :low_confidence}} =
               CandidateGate.verify_and_deliver(
                 candidate,
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter,
                 can_retry?: false
               )
    end
  end

  # ============================================================================
  # 5. Single Monotonic Semantic Retry
  # ============================================================================

  describe "Single Monotonic Semantic Retry" do
    test "semantic refusal triggers 1 regeneration; if second candidate passes -> verified" do
      package = base_package()
      test_pid = self()

      generator = fn ->
        send(test_pid, :generator_invoked)
        {:ok, "regen_ok_second_turn"}
      end

      assert {:ok, "regen_ok_second_turn"} =
               CandidateGate.verify_and_deliver(
                 "ungrounded_hallucination",
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter,
                 generator: generator,
                 test_pid: test_pid
               )

      # Generator was called exactly once
      assert_received :generator_invoked
      refute_received :generator_invoked
    end

    test "low confidence triggers 1 regeneration; if second candidate passes -> verified" do
      package = base_package()
      test_pid = self()

      generator = fn _remaining_ms ->
        send(test_pid, :generator_invoked)
        {:ok, %{text: "regen_ok_from_map"}}
      end

      assert {:ok, "regen_ok_from_map"} =
               CandidateGate.verify_and_deliver(
                 "low_confidence_text",
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter,
                 generator: generator
               )

      assert_received :generator_invoked
      refute_received :generator_invoked
    end

    test "if second candidate also fails Jev, releases NO text and returns refusal error" do
      package = base_package()
      test_pid = self()

      generator = fn ->
        send(test_pid, :generator_invoked)
        {:ok, "regen_refused_second_time"}
      end

      assert {:error, {:refused, :semantic_refusal}} =
               CandidateGate.verify_and_deliver(
                 "ungrounded_hallucination",
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter,
                 generator: generator
               )

      assert_received :generator_invoked
      refute_received :generator_invoked
    end

    test "if second candidate fails low confidence, returns low_confidence refusal error" do
      package = base_package()

      generator = fn ->
        {:ok, "regen_low_confidence_second"}
      end

      assert {:error, {:refused, :low_confidence}} =
               CandidateGate.verify_and_deliver(
                 "ungrounded_hallucination",
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter,
                 generator: generator
               )
    end

    test "if second candidate fails deny checks, returns deny error and releases NO text" do
      package = base_package()

      # Generator returns an English roleplay leakage string
      generator = fn ->
        {:ok, "I am an AI assistant and cannot help."}
      end

      assert {:error, {:denied, :roleplay_leakage}} =
               CandidateGate.verify_and_deliver(
                 "ungrounded_hallucination",
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter,
                 generator: generator
               )
    end

    test "never performs more than 1 retry under any circumstances" do
      package = base_package()
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      generator = fn ->
        Agent.update(counter, &(&1 + 1))
        {:ok, "regen_refused_text"}
      end

      assert {:error, {:refused, :semantic_refusal}} =
               CandidateGate.verify_and_deliver(
                 "ungrounded_hallucination",
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter,
                 generator: generator
               )

      # Generator call count must be exactly 1
      assert Agent.get(counter, & &1) == 1
    end

    test "second candidate can bypass Jev if it matches an unconditional approved template" do
      package = base_package()

      # Generator produces an approved unconditional template
      generator = fn ->
        {:ok, "Compreendo, doutor."}
      end

      assert {:ok, "Compreendo, doutor."} =
               CandidateGate.verify_and_deliver(
                 "ungrounded_hallucination",
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter,
                 generator: generator
               )
    end

    test "generator error fails safely with typed error tuple without releasing text" do
      package = base_package()

      generator = fn ->
        {:error, :model_overloaded}
      end

      assert {:error, :model_overloaded} =
               CandidateGate.verify_and_deliver(
                 "ungrounded_hallucination",
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter,
                 generator: generator
               )
    end

    test "generator crash fails safely with typed error tuple without releasing text" do
      package = base_package()

      generator = fn ->
        raise "LLM service connection reset"
      end

      assert {:error, {:generator_crash, _msg}} =
               CandidateGate.verify_and_deliver(
                 "ungrounded_hallucination",
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter,
                 generator: generator
               )
    end

    test "nil generator defaults to StationAI.next_reply passing map context without crashing" do
      package = base_package()

      # Under test environment without OpenAI keys, StationAI returns {:error, :missing_credentials}
      # rather than crashing with BadMapError/ArgumentError when building payload.
      assert {:error, :missing_credentials} =
               CandidateGate.verify_and_deliver(
                 "ungrounded_hallucination",
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter,
                 generator: nil
               )
    end
  end

  # ============================================================================
  # 6. Monotonic Deadline Shared Across Attempts
  # ============================================================================

  describe "Monotonic deadline sharing" do
    test "initial check halts with :timeout when deadline already expired" do
      package = base_package()
      past_deadline = JevDecision.monotonic_now_ms() - 100

      assert {:error, :timeout} =
               CandidateGate.verify_and_deliver(
                 "verified_text",
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter,
                 deadline_at_monotonic_ms: past_deadline
               )
    end

    test "timeout during generator regeneration halts without releasing text" do
      package = base_package()
      deadline_at = JevDecision.monotonic_now_ms() + 40

      generator = fn ->
        # Sleep beyond the monotonic deadline
        Process.sleep(60)
        {:ok, "regen_ok_too_late"}
      end

      assert {:error, :timeout} =
               CandidateGate.verify_and_deliver(
                 "ungrounded_hallucination",
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter,
                 generator: generator,
                 deadline_at_monotonic_ms: deadline_at
               )
    end

    test "relative deadline_ms times out if adapter sleeps past it" do
      package = base_package()

      assert {:error, :timeout} =
               CandidateGate.verify_and_deliver(
                 "sleep_beyond_deadline",
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter,
                 deadline_ms: 30
               )
    end
  end

  # ============================================================================
  # 7. Technical Errors Invalidate Attempt (No Fallback Fabricated)
  # ============================================================================

  describe "Technical errors invalidate attempt immediately" do
    test "upstream 500 returns typed error tuple immediately" do
      package = base_package()

      assert {:error, {:upstream_5xx, 500}} =
               CandidateGate.verify_and_deliver(
                 "upstream_500",
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter
               )
    end

    test "upstream 503 returns typed error tuple immediately" do
      package = base_package()

      assert {:error, {:upstream_5xx, 503}} =
               CandidateGate.verify_and_deliver(
                 "upstream_503",
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter
               )
    end

    test "adapter timeout returns :timeout immediately" do
      package = base_package()

      assert {:error, :timeout} =
               CandidateGate.verify_and_deliver(
                 "adapter_timeout",
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter
               )
    end

    test "disabled adapter returns adapter_disabled tuple immediately" do
      package = base_package()

      assert {:error, {:adapter_disabled, _}} =
               CandidateGate.verify_and_deliver(
                 "adapter_disabled",
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter
               )
    end

    test "malformed output from Jev returns typed error immediately" do
      package = base_package()

      assert {:error, :malformed_output} =
               CandidateGate.verify_and_deliver(
                 "malformed_output",
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter
               )
    end

    test "technical failures NEVER fabricate fallback clinical text or convert to uncertainty" do
      package = base_package()
      refusal = Backend.Stations.StationAI.refusal_text()

      res_500 =
        CandidateGate.verify_and_deliver(
          "upstream_500",
          package,
          sample_conversation(),
          adapter: DoubleAdapter
        )

      assert res_500 != {:ok, refusal}
      assert res_500 == {:error, {:upstream_5xx, 500}}

      res_to =
        CandidateGate.verify_and_deliver(
          "adapter_timeout",
          package,
          sample_conversation(),
          adapter: DoubleAdapter
        )

      assert res_to != {:ok, refusal}
      assert res_to == {:error, :timeout}
    end
  end

  # ============================================================================
  # 8. Security & No-Leak Invariants
  # ============================================================================

  describe "Security and no-leak invariants" do
    test "rejected candidate text is never passed into generator arguments" do
      package = base_package()
      test_pid = self()
      rejected_candidate = "ungrounded_hallucination"

      generator = fn _pkg, conv ->
        # Verify that rejected_candidate is not in conversation history or package
        Enum.each(conv, fn turn ->
          turn_text = turn["text"] || turn[:text]
          assert turn_text != rejected_candidate
        end)

        send(test_pid, :history_clean)
        {:ok, "regen_ok_clean"}
      end

      assert {:ok, "regen_ok_clean"} =
               CandidateGate.verify_and_deliver(
                 rejected_candidate,
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter,
                 generator: generator
               )

      assert_received :history_clean
    end

    test "errors never leak candidate text in error payload" do
      package = base_package()
      secret_rejected = "ungrounded_hallucination"

      {:error, error_payload} =
        CandidateGate.verify_and_deliver(
          secret_rejected,
          package,
          sample_conversation(),
          adapter: DoubleAdapter,
          can_retry?: false
        )

      inspected = inspect(error_payload)
      refute inspected =~ secret_rejected
    end

    test "verify_patient_reply/4 alias delegates correctly" do
      package = base_package()

      assert {:ok, "verified_text"} =
               CandidateGate.verify_patient_reply(
                 "verified_text",
                 package,
                 sample_conversation(),
                 adapter: DoubleAdapter
               )
    end
  end
end
