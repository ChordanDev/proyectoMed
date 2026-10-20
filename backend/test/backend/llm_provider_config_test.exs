defmodule Backend.LLMProviderConfigTest do
  # Edits the operating system environment: not async.
  use ExUnit.Case, async: false

  alias Backend.Stations.LearnerFeedback
  alias Backend.Stations.PatientAdjudicator
  alias Backend.Stations.RubricAssessment.Resolver
  alias Backend.Stations.StationAI

  @runtime_config Path.expand("../../config/runtime.exs", __DIR__)
  @variables ~w(LLM_PROVIDER RUBRIC_RESOLVER RUBRIC_RESOLVER_MODEL ANTHROPIC_API_KEY ANTHROPIC_BASE_URL ANTHROPIC_MODEL ANTHROPIC_PATIENT_MODEL ANTHROPIC_ADJUDICATOR_MODEL PATIENT_ADJUDICATOR PATIENT_ADJUDICATOR_DEADLINE_MS PATIENT_ADJUDICATOR_REGENERATION_EXTENSION_MS RUBRIC_RESOLVER_DEADLINE_MS LEARNER_FEEDBACK_DEADLINE_MS)

  setup do
    previous = Map.new(@variables, &{&1, System.get_env(&1)})
    Enum.each(@variables, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(previous, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)
  end

  defp runtime(env \\ :dev, variables) do
    Enum.each(variables, fn {name, value} -> System.put_env(name, value) end)

    @runtime_config
    |> Config.Reader.read!(env: env, target: :host)
    |> Keyword.get(:backend, [])
  end

  describe "without LLM_PROVIDER" do
    test "the OpenAI seams stay selected and no Anthropic configuration is written" do
      backend = runtime(%{"RUBRIC_RESOLVER" => "openai"})

      refute Keyword.has_key?(backend, :station_ai_adapter)
      refute Keyword.has_key?(backend, :learner_feedback_adapter)
      assert backend[:rubric_resolver_adapter] == Resolver.OpenAIAdapter
      refute Keyword.has_key?(backend, StationAI.AnthropicClient)

      # The compile-time defaults (config.exs) are the OpenAI ones.
      assert Application.get_env(:backend, :station_ai_adapter, StationAI.OpenAIAdapter) ==
               StationAI.OpenAIAdapter
    end

    test "an unknown provider keeps OpenAI" do
      backend = runtime(%{"LLM_PROVIDER" => "gemini", "RUBRIC_RESOLVER" => "openai"})

      refute Keyword.has_key?(backend, :station_ai_adapter)
      refute Keyword.has_key?(backend, :learner_feedback_adapter)
      assert backend[:rubric_resolver_adapter] == Resolver.OpenAIAdapter
    end

    test "without RUBRIC_RESOLVER the resolver stays disabled" do
      refute Keyword.has_key?(runtime(%{}), :rubric_resolver_adapter)
    end
  end

  describe "undecided-verdict adjudicator (issue #290)" do
    test "is off without LLM_PROVIDER=anthropic" do
      refute Keyword.has_key?(runtime(%{}), :patient_adjudicator_adapter)

      assert Application.get_env(:backend, :patient_adjudicator_adapter) ==
               PatientAdjudicator.DisabledAdapter
    end

    test "runs on Claude with LLM_PROVIDER=anthropic unless PATIENT_ADJUDICATOR=off" do
      assert runtime(%{"LLM_PROVIDER" => "anthropic"})[:patient_adjudicator_adapter] ==
               PatientAdjudicator.AnthropicAdapter

      refute Keyword.has_key?(
               runtime(%{"LLM_PROVIDER" => "anthropic", "PATIENT_ADJUDICATOR" => "off"}),
               :patient_adjudicator_adapter
             )
    end

    test "ANTHROPIC_ADJUDICATOR_MODEL and PATIENT_ADJUDICATOR_DEADLINE_MS are read" do
      backend =
        runtime(%{
          "LLM_PROVIDER" => "anthropic",
          "ANTHROPIC_ADJUDICATOR_MODEL" => "claude-haiku-5-5",
          "PATIENT_ADJUDICATOR_DEADLINE_MS" => "900"
        })

      assert backend[StationAI.AnthropicClient][:adjudicator_model] == "claude-haiku-5-5"
      assert backend[:patient_adjudicator_deadline_ms] == 900
    end

    test "PATIENT_ADJUDICATOR_REGENERATION_EXTENSION_MS is read as a non-negative integer" do
      assert runtime(%{"PATIENT_ADJUDICATOR_REGENERATION_EXTENSION_MS" => "1200"})[
               :patient_adjudicator_regeneration_extension_ms
             ] == 1_200

      assert runtime(%{"PATIENT_ADJUDICATOR_REGENERATION_EXTENSION_MS" => "0"})[
               :patient_adjudicator_regeneration_extension_ms
             ] == 0

      for raw <- ["-5", "fast", "1.5", ""] do
        refute Keyword.has_key?(
                 runtime(%{"PATIENT_ADJUDICATOR_REGENERATION_EXTENSION_MS" => raw}),
                 :patient_adjudicator_regeneration_extension_ms
               )
      end
    end

    test "a deadline that is not a positive integer keeps the default" do
      for raw <- ["0", "-5", "fast", "1.5"] do
        refute Keyword.has_key?(
                 runtime(%{"PATIENT_ADJUDICATOR_DEADLINE_MS" => raw}),
                 :patient_adjudicator_deadline_ms
               )
      end
    end
  end

  describe "educational result deadlines (issue #301)" do
    test "RUBRIC_RESOLVER_DEADLINE_MS and LEARNER_FEEDBACK_DEADLINE_MS are read" do
      backend =
        runtime(%{
          "RUBRIC_RESOLVER_DEADLINE_MS" => "20000",
          "LEARNER_FEEDBACK_DEADLINE_MS" => "40000"
        })

      assert backend[:rubric_resolver_deadline_ms] == 20_000
      assert backend[:learner_feedback_deadline_ms] == 40_000
    end

    test "a deadline that is not a positive integer keeps the default" do
      for raw <- ["0", "-5", "fast", "1.5"] do
        backend =
          runtime(%{
            "RUBRIC_RESOLVER_DEADLINE_MS" => raw,
            "LEARNER_FEEDBACK_DEADLINE_MS" => raw
          })

        refute Keyword.has_key?(backend, :rubric_resolver_deadline_ms)
        refute Keyword.has_key?(backend, :learner_feedback_deadline_ms)
      end
    end

    test "overrides are capped so resolver and feedback fit the result budget" do
      backend =
        runtime(%{
          "RUBRIC_RESOLVER_DEADLINE_MS" => "999999",
          "LEARNER_FEEDBACK_DEADLINE_MS" => "999999"
        })

      assert backend[:rubric_resolver_deadline_ms] == 40_000
      assert backend[:learner_feedback_deadline_ms] == 40_000

      # Against the default resolver deadline (30 s), feedback gets the rest.
      System.delete_env("RUBRIC_RESOLVER_DEADLINE_MS")

      backend = runtime(%{"LEARNER_FEEDBACK_DEADLINE_MS" => "999999"})
      assert backend[:learner_feedback_deadline_ms] == 50_000
    end
  end

  describe "LLM_PROVIDER=anthropic" do
    test "selects Claude for the patient, the resolver and learner feedback" do
      backend =
        runtime(%{
          "LLM_PROVIDER" => "anthropic",
          "RUBRIC_RESOLVER" => "on",
          "ANTHROPIC_API_KEY" => "sk-ant-boot",
          "ANTHROPIC_BASE_URL" => "https://anthropic.example.test",
          "ANTHROPIC_MODEL" => "claude-opus-5-5",
          "ANTHROPIC_PATIENT_MODEL" => "claude-sonnet-5-5"
        })

      assert backend[:station_ai_adapter] == StationAI.AnthropicAdapter
      assert backend[:learner_feedback_adapter] == LearnerFeedback.AnthropicAdapter
      assert backend[:rubric_resolver_adapter] == Resolver.AnthropicAdapter

      assert backend[StationAI.AnthropicClient] == [
               api_key: "sk-ant-boot",
               base_url: "https://anthropic.example.test",
               model: "claude-opus-5-5",
               patient_model: "claude-sonnet-5-5"
             ]
    end

    test "RUBRIC_RESOLVER=openai still turns the resolver on, on Claude" do
      backend = runtime(%{"LLM_PROVIDER" => "anthropic", "RUBRIC_RESOLVER" => "openai"})
      assert backend[:rubric_resolver_adapter] == Resolver.AnthropicAdapter
    end

    test "without RUBRIC_RESOLVER the resolver stays disabled" do
      backend = runtime(%{"LLM_PROVIDER" => "anthropic"})

      refute Keyword.has_key?(backend, :rubric_resolver_adapter)
      assert backend[:station_ai_adapter] == StationAI.AnthropicAdapter
    end

    test "the test environment reads none of it" do
      backend = runtime(:test, %{"LLM_PROVIDER" => "anthropic", "ANTHROPIC_API_KEY" => "k"})

      refute Keyword.has_key?(backend, :station_ai_adapter)
      refute Keyword.has_key?(backend, :learner_feedback_adapter)
      refute Keyword.has_key?(backend, StationAI.AnthropicClient)
    end
  end
end
