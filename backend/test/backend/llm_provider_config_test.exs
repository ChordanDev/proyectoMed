defmodule Backend.LLMProviderConfigTest do
  # Edits the operating system environment: not async.
  use ExUnit.Case, async: false

  alias Backend.Stations.LearnerFeedback
  alias Backend.Stations.RubricAssessment.Resolver
  alias Backend.Stations.StationAI

  @runtime_config Path.expand("../../config/runtime.exs", __DIR__)
  @variables ~w(LLM_PROVIDER RUBRIC_RESOLVER RUBRIC_RESOLVER_MODEL ANTHROPIC_API_KEY ANTHROPIC_BASE_URL ANTHROPIC_MODEL)

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

  describe "LLM_PROVIDER=anthropic" do
    test "selects Claude for the patient, the resolver and learner feedback" do
      backend =
        runtime(%{
          "LLM_PROVIDER" => "anthropic",
          "RUBRIC_RESOLVER" => "on",
          "ANTHROPIC_API_KEY" => "sk-ant-boot",
          "ANTHROPIC_BASE_URL" => "https://anthropic.example.test",
          "ANTHROPIC_MODEL" => "claude-sonnet-5-5"
        })

      assert backend[:station_ai_adapter] == StationAI.AnthropicAdapter
      assert backend[:learner_feedback_adapter] == LearnerFeedback.AnthropicAdapter
      assert backend[:rubric_resolver_adapter] == Resolver.AnthropicAdapter

      assert backend[StationAI.AnthropicClient] == [
               api_key: "sk-ant-boot",
               base_url: "https://anthropic.example.test",
               model: "claude-sonnet-5-5"
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
