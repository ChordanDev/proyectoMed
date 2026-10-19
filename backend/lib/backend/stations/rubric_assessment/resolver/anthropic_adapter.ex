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
