defmodule Backend.Stations.StationAI.AnthropicAdapter do
  @moduledoc """
  `Backend.Stations.StationAI` adapter backed by Anthropic's Messages API
  (issue #252), selected with `LLM_PROVIDER=anthropic`.

  The system prompt is the package safety prompt built by
  `Backend.Stations.StationAI.system_prompt/2` (withheld facts included), and
  the conversation is sent as alternating `user` (learner) and `assistant`
  (patient) messages. The package part of the prompt is the cached prompt
  prefix (issue #272): it is byte-identical on every turn of a station, while
  the withheld-facts section of a regeneration follows it uncached and the
  conversation stays in `messages`. The reply is a plain text candidate: the caller still
  bounds it (`BoundedReply`) and the CandidateGate and Jev still verify it.

  The patient runs on its own model setting (`:patient_model`,
  `ANTHROPIC_PATIENT_MODEL`, issue #256; default `claude-haiku-5-5` since
  issue #308) at `output_config.effort` `low` with thinking at its lowest
  setting (`disabled` on Haiku 5.5, `between_tools` on Sonnet 5.5) for
  latency. The resolver and learner feedback keep `:model`. Like the
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
    with {:ok, text} <- AnthropicClient.create_message(config(opts), request(package, context)) do
      {:ok, %{text: text}}
    end
  end

  @impl true
  def stream_reply(package, context, on_text), do: stream_reply(package, context, on_text, [])

  @doc """
  Streams the same patient request (issue #271), calling `on_text` with each
  text delta as it arrives. Every delta is unverified candidate text: the
  caller verifies it sentence by sentence before anything is spoken or stored.
  """
  @spec stream_reply(StationAI.package(), StationAI.context(), (String.t() -> any()), keyword()) ::
          {:ok, %{text: String.t()}} | {:error, AnthropicClient.error()}
  def stream_reply(package, context, on_text, opts) do
    with {:ok, text} <-
           AnthropicClient.stream_message(config(opts), request(package, context), on_text) do
      {:ok, %{text: text}}
    end
  end

  defp config(opts),
    do:
      AnthropicClient.config(opts, effort: @effort, model_key: :patient_model, thinking: :lowest)

  defp request(package, context) do
    {stable_prompt, per_turn_prompt} = StationAI.system_prompt_parts(package, context)

    %{
      system: stable_prompt,
      system_suffix: per_turn_prompt,
      messages: messages(context),
      max_tokens: @max_tokens
    }
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
