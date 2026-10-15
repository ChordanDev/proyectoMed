defmodule Backend.Stations.LearnerFeedback.OpenAIAdapter do
  @moduledoc """
  `Backend.Stations.LearnerFeedback.Adapter` backed by OpenAI's Chat
  Completions API (issue #215).

  It sends one `POST /v1/chat/completions` request carrying the graded record
  as the user message (never the conversation) and asks for a JSON object of
  the shape `{"feedback": {"<criterion_id>": "<text>"}}`.

  Configuration is shared with the patient adapter
  (`Backend.Stations.StationAI.OpenAIAdapter.config/1`): `OPENAI_API_KEY`,
  `OPENAI_BASE_URL` and `OPENAI_MODEL` (default `gpt-4o-mini`). Requests use
  `retry: false` and a receive timeout just below
  `:learner_feedback_deadline_ms`, which `Backend.Stations.LearnerFeedback`
  enforces as the hard deadline.

  ## Contract

    * `{:ok, feedback}` - the `feedback` object as decoded, keyed by criterion
      id. Values are passed through as-is; `Backend.Stations.LearnerFeedback`
      validates every text (type, length, forbidden language) and falls back
      to the authored text per criterion.
    * `{:error, :missing_credentials}` - API key is absent or blank
    * `{:error, :upstream_error}` - non-2xx HTTP response from OpenAI
    * `{:error, :timeout}` - request timed out
    * `{:error, :network_error}` - transport or connection failure
    * `{:error, :malformed_response}` - the completion, its content JSON or its
      `feedback` object is missing or invalid

  The API key and provider text are never logged.
  """

  @behaviour Backend.Stations.LearnerFeedback.Adapter

  alias Backend.Stations.StationAI.OpenAIAdapter, as: OpenAI

  @default_deadline_ms 3_000
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

  Respond with a JSON object only, of the shape {"feedback": {"<criterion id>": "<feedback text>"}}, with one entry for every criterion id in the request.
  """

  @impl true
  def write_feedback(request), do: write_feedback(request, [])

  @doc "Same as `write_feedback/1`, with OpenAI config overrides for tests."
  @spec write_feedback(Backend.Stations.LearnerFeedback.Adapter.request(), keyword()) ::
          {:ok, map()} | {:error, atom()}
  def write_feedback(request, opts) do
    config =
      opts
      |> OpenAI.config()
      |> Map.update!(:req_options, &Keyword.put_new(&1, :receive_timeout, receive_timeout()))

    with :ok <- OpenAI.validate_credentials(config.api_key),
         {:ok, body} <- OpenAI.post_chat_completion(config, payload(request, config.model)) do
      parse_response(body)
    end
  end

  defp payload(request, model) do
    %{
      "model" => model,
      "response_format" => %{"type" => "json_object"},
      "messages" => [
        %{"role" => "system", "content" => @system_prompt},
        %{"role" => "user", "content" => Jason.encode!(request)}
      ]
    }
  end

  defp receive_timeout do
    deadline_ms =
      Application.get_env(:backend, :learner_feedback_deadline_ms, @default_deadline_ms)

    max(deadline_ms - @timeout_margin_ms, @min_receive_timeout_ms)
  end

  defp parse_response(%{"choices" => [%{"message" => %{"content" => content}} | _]})
       when is_binary(content) do
    case Jason.decode(content) do
      {:ok, %{"feedback" => feedback}} when is_map(feedback) -> {:ok, feedback}
      _invalid -> {:error, :malformed_response}
    end
  end

  defp parse_response(_body), do: {:error, :malformed_response}
end
