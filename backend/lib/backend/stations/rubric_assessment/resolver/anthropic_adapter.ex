defmodule Backend.Stations.RubricAssessment.Resolver.AnthropicAdapter do
  @moduledoc """
  Rubric resolver backed by Anthropic's Messages API (issue #252), with
  structured outputs (`output_config.format`, JSON schema).

  It asks exactly what the OpenAI resolver asks: the same system prompt,
  user content and JSON schema
  (`Backend.Stations.RubricAssessment.Resolver.OpenAIAdapter`), and decodes the
  answer with the same strict decoder. `Backend.Stations.RubricAssessment.Resolver`
  still validates and merges every decision; nothing here grants credit.
  Thinking stays adaptive, so there is no `temperature`; the effort is `medium`.

  The model is the client's `:resolver_model` (`ANTHROPIC_RESOLVER_MODEL`,
  default `claude-haiku-5-5`, issue #343, chosen by measured agreement and cost
  in `docs/research/resolver-model-comparison.md`). On Haiku 5.5 the request
  carries no `fallbacks` (it has none) and no `thinking` field, which is the
  shape that comparison measured.

  The fixed system prompt is the cached prompt prefix (issue #272, see
  `Backend.Stations.StationAI.AnthropicClient`); the per-request user content
  (criteria to decide and the learner evidence) stays after the breakpoint.

  The HTTP receive timeout sits just below the resolver deadline
  (`Backend.Stations.RubricAssessment.Resolver.deadline_ms/1`), which the
  resolver enforces as the hard limit.

  Configuration and errors are those of
  `Backend.Stations.StationAI.AnthropicClient`; a refusal is
  `{:error, :refused}` and leaves every undecided action uncertain.
  """

  @behaviour Backend.Stations.RubricAssessment.Resolver

  alias Backend.Stations.RubricAssessment.Resolver
  alias Backend.Stations.RubricAssessment.Resolver.OpenAIAdapter, as: Prompt
  alias Backend.Stations.StationAI.AnthropicClient

  @effort "medium"
  @max_tokens 8_192
  @timeout_margin_ms 250
  @min_receive_timeout_ms 500

  @impl true
  def resolve(request, opts) do
    config =
      AnthropicClient.config(opts,
        effort: @effort,
        model_key: :resolver_model,
        receive_timeout: receive_timeout(opts)
      )

    message = %{
      system: Prompt.system_prompt(),
      messages: [%{"role" => "user", "content" => Jason.encode!(Prompt.user_content(request))}],
      max_tokens: @max_tokens,
      schema: Prompt.schema()
    }

    with {:ok, text} <- AnthropicClient.create_message(config, message) do
      Prompt.decode_answer(text)
    end
  end

  defp receive_timeout(opts) do
    max(Resolver.deadline_ms(opts) - @timeout_margin_ms, @min_receive_timeout_ms)
  end
end
