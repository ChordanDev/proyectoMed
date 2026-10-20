defmodule Backend.Stations.LearnerFeedback.AnthropicAdapter do
  @moduledoc """
  `Backend.Stations.LearnerFeedback.Adapter` backed by Anthropic's Messages API
  (issue #252), selected with `LLM_PROVIDER=anthropic`.

  It sends one request carrying the graded record as the user message (never
  the conversation) and asks, through structured outputs
  (`output_config.format`), for `{"feedback": [{"criterion_id", "text"}]}`.
  Structured outputs need every object closed (`additionalProperties: false`),
  so the answer is a list of entries rather than a map keyed by criterion id;
  the adapter turns it into the seam's `%{criterion_id => text}` map. Texts
  are passed through as-is: `Backend.Stations.LearnerFeedback` validates each
  one and falls back to the authored text per criterion.

  The fixed system prompt is the cached prompt prefix (issue #272, see
  `Backend.Stations.StationAI.AnthropicClient`); the graded record stays in the
  user message, after the breakpoint. The prompt alone may be shorter than the
  512-token minimum, in which case it silently does not cache.

  The effort is `medium`. The HTTP receive timeout sits just below
  `:learner_feedback_deadline_ms`, which `Backend.Stations.LearnerFeedback`
  enforces as the hard deadline. Configuration and errors are those of
  `Backend.Stations.StationAI.AnthropicClient`; a refusal is
  `{:error, :refused}` and keeps the authored texts. Provider text is never
  logged.
  """

  @behaviour Backend.Stations.LearnerFeedback.Adapter

  alias Backend.Stations.StationAI.AnthropicClient

  @effort "medium"
  @max_tokens 8_192
  @default_deadline_ms 60_000
  @timeout_margin_ms 250
  @min_receive_timeout_ms 500

  @system_prompt """
  You write short educational feedback for a medical learner after a simulated clinical station.
  The user message is a JSON object with a `language` and a list of `criteria` that were already graded.
  Each criterion has an `id`, a `description`, the obtained `level` and its description, the `next_level` (null when the obtained level is the highest), `points` and `max_points`, the `performed_actions`, the `missing_actions` and the learner `evidence` that the grading cited.

  Rules:
  - Write every feedback text in the request `language`.
  - Write one text per criterion: 1 to 3 sentences and at most 400 characters.
  - Explain the given graded outcome. Never contradict or change the level, points or status.
  - Suggest what to practise next using the missing actions and the next level.
  - Never mention a global or total score, pass or fail, approval, readiness or certification.
  - Use only the provided data. Do not invent findings, actions or evidence.

  Answer with one `feedback` entry for every criterion id in the request: its `criterion_id` and its `text`.
  """

  @impl true
  def write_feedback(request), do: write_feedback(request, [])

  @doc "Same as `write_feedback/1`, with client option overrides for tests."
  @spec write_feedback(Backend.Stations.LearnerFeedback.Adapter.request(), keyword()) ::
          {:ok, map()} | {:error, atom()}
  def write_feedback(request, opts) do
    config = AnthropicClient.config(opts, effort: @effort, receive_timeout: receive_timeout())

    message = %{
      system: @system_prompt,
      messages: [%{"role" => "user", "content" => Jason.encode!(request)}],
      max_tokens: @max_tokens,
      schema: schema()
    }

    with {:ok, text} <- AnthropicClient.create_message(config, message) do
      decode(text)
    end
  end

  @doc "The JSON schema of the provider's answer."
  @spec schema() :: map()
  def schema do
    entry = %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["criterion_id", "text"],
      "properties" => %{
        "criterion_id" => %{"type" => "string"},
        "text" => %{"type" => "string"}
      }
    }

    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["feedback"],
      "properties" => %{"feedback" => %{"type" => "array", "items" => entry}}
    }
  end

  defp decode(text) do
    with {:ok, %{"feedback" => entries}} when is_list(entries) <- Jason.decode(text),
         true <- Enum.all?(entries, &entry?/1) do
      {:ok, Map.new(entries, &{&1["criterion_id"], &1["text"]})}
    else
      _invalid -> {:error, :malformed_response}
    end
  end

  defp entry?(%{"criterion_id" => id, "text" => _text}) when is_binary(id), do: true
  defp entry?(_entry), do: false

  defp receive_timeout do
    deadline_ms =
      Application.get_env(:backend, :learner_feedback_deadline_ms, @default_deadline_ms)

    max(deadline_ms - @timeout_margin_ms, @min_receive_timeout_ms)
  end
end
