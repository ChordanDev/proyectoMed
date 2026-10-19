defmodule Backend.Stations.StationAI.AnthropicAdapter do
  @moduledoc """
  `Backend.Stations.StationAI` adapter backed by Anthropic's Messages API
  (issue #252), selected with `LLM_PROVIDER=anthropic`.

  The system prompt is the package safety prompt built by
  `Backend.Stations.StationAI.system_prompt/2` (withheld facts included), and
  the conversation is sent as alternating `user` (learner) and `assistant`
  (patient) messages. The reply is a plain text candidate: the caller still
  bounds it (`BoundedReply`) and the CandidateGate and Jev still verify it.

  The patient runs on its own model setting (`:patient_model`, default
  `claude-sonnet-5-5`, issue #256) at `output_config.effort` `low` with
  thinking at its lowest setting (`between_tools` on Sonnet 5.5) for
  latency. Like the
  OpenAI patient adapter it sets no receive timeout of its own (Req's default
  applies). Errors are the client's vocabulary (see
  `Backend.Stations.StationAI.AnthropicClient`); a refusal is
  `{:error, :refused}`, a technical failure, and its text is never returned.
  """

  @behaviour Backend.Stations.StationAI

  alias Backend.Stations.StationAI
  alias Backend.Stations.StationAI.AnthropicClient

  @effort "low"
  @max_tokens 4_096

  @impl true
  def next_reply(package, context), do: next_reply(package, context, [])

  @doc "Same as `next_reply/2`, with client option overrides (tests, per-role tuning)."
  @spec next_reply(StationAI.package(), StationAI.context(), keyword()) ::
          {:ok, %{text: String.t()}} | {:error, AnthropicClient.error()}
  def next_reply(package, context, opts) do
    config =
      AnthropicClient.config(opts, effort: @effort, model_key: :patient_model, thinking: :lowest)

    request = %{
      system: StationAI.system_prompt(package, context),
      messages: messages(context),
      max_tokens: @max_tokens
    }

    with {:ok, text} <- AnthropicClient.create_message(config, request) do
      {:ok, %{text: text}}
    end
  end

  defp messages(context) do
    (context[:conversation] || Map.get(context, "conversation", []))
    |> Enum.map(&format_message/1)
  end

  defp format_message(msg) do
    role =
      case msg[:role] || msg["role"] do
        r when r in [:student, "student"] -> "user"
        r when r in [:patient, "patient"] -> "assistant"
        other -> to_string(other)
      end

    %{"role" => role, "content" => msg[:text] || msg["text"]}
  end
end
