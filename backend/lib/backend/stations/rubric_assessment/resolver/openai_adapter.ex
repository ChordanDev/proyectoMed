defmodule Backend.Stations.RubricAssessment.Resolver.OpenAIAdapter do
  @moduledoc """
  Rubric resolver backed by OpenAI's Chat Completions API with strict
  structured output (`response_format` `json_schema`).

  The provider sees the resolver request as JSON, reshaped so the work is
  explicit: each criterion lists the actions to `decide` (Jev left them
  uncertain) apart from its `context_actions` (Jev's final classifications,
  context only), next to the learner-only evidence pool and the exact number
  of decisions expected. It answers one decision per action to decide. The
  strict JSON schema is static on purpose, so the provider can cache it.
  `Backend.Stations.RubricAssessment.Resolver` validates and merges the answer;
  nothing here grants credit.

  ## Configuration

  The API key and base URL are the ones of the station OpenAI adapter
  (`config :backend, Backend.StationAI.OpenAIAdapter`, written by
  `config/runtime.exs` from `OPENAI_API_KEY` and `OPENAI_BASE_URL`). The model
  is `config :backend, Backend.Stations.RubricAssessment.Resolver.OpenAIAdapter,
  model: ...` (`RUBRIC_RESOLVER_MODEL`), falling back to the station OpenAI
  model and then to `gpt-4o-mini`.
  Options (`:api_key`, `:base_url`, `:model`, `:plug`, `:retry`,
  `:req_options`) override the configuration. The operating system environment
  is never read here.

  ## Errors

    * `{:error, :missing_credentials}` - the API key is absent or blank;
    * `{:error, :upstream_error}` - a non-2xx HTTP response;
    * `{:error, :timeout}` - the request timed out;
    * `{:error, :network_error}` - a transport or connection failure;
    * `{:error, :refused}` - the model refused to answer;
    * `{:error, :malformed_response}` - an unparseable completion, invalid
      JSON, or JSON that does not match the schema.
  """

  @behaviour Backend.Stations.RubricAssessment.Resolver

  @default_model "gpt-4o-mini"
  @default_base_url "https://api.openai.com"
  @classes ["performed", "not_performed", "uncertain"]
  @decision_keys ["criterion_id", "id", "classification", "evidence_ids"]

  @system_prompt """
  You assess a medical student's simulated consultation against rubric actions.
  Each criterion lists the actions you must decide under "decide". \
  Its "context_actions" are already decided and are context only: never return them.
  Return exactly one entry per action in "decide", with its criterion_id and id, \
  and nothing else: the answer holds exactly decision_count entries.
  Answer "performed" only when evidence items show the student did the action, \
  and cite the ids of those items in evidence_ids.
  Cite only ids from evidence_pool. It holds the student's own turns and requests; \
  never cite anything else.
  Answer "not_performed", with no citations, when the evidence shows the action was not done.
  When you are unsure, answer "uncertain".
  """

  @impl true
  def resolve(request, opts) do
    config = config(opts)

    with :ok <- validate_credentials(config.api_key),
         {:ok, body} <- post(config, payload(request, config.model)) do
      parse(body)
    end
  end

  @doc "The system prompt sent with every request."
  @spec system_prompt() :: String.t()
  def system_prompt, do: @system_prompt

  @doc "The strict JSON schema of the provider's answer."
  @spec schema() :: map()
  def schema do
    decision = %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => @decision_keys,
      "properties" => %{
        "criterion_id" => %{"type" => "string"},
        "id" => %{"type" => "string"},
        "classification" => %{"type" => "string", "enum" => @classes},
        "evidence_ids" => %{"type" => "array", "items" => %{"type" => "string"}}
      }
    }

    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["actions"],
      "properties" => %{"actions" => %{"type" => "array", "items" => decision}}
    }
  end

  defp config(opts) do
    station =
      Keyword.merge(
        Application.get_env(:backend, Backend.StationAI.OpenAIAdapter, []),
        Application.get_env(:backend, Backend.Stations.StationAI.OpenAIAdapter, [])
      )

    own = Application.get_env(:backend, __MODULE__, [])

    %{
      api_key: opts[:api_key] || station[:api_key],
      base_url: opts[:base_url] || station[:base_url] || @default_base_url,
      model: opts[:model] || own[:model] || station[:model] || @default_model,
      req_options:
        own
        |> Keyword.get(:req_options, [])
        |> Keyword.merge(Keyword.get(opts, :req_options, []))
        |> Keyword.merge(Keyword.take(opts, [:plug, :retry]))
    }
  end

  defp validate_credentials(key) when is_binary(key) do
    if String.trim(key) == "", do: {:error, :missing_credentials}, else: :ok
  end

  defp validate_credentials(_key), do: {:error, :missing_credentials}

  defp payload(request, model) do
    %{
      "model" => model,
      "messages" => [
        %{"role" => "system", "content" => @system_prompt},
        %{"role" => "user", "content" => Jason.encode!(user_content(request))}
      ],
      "response_format" => %{
        "type" => "json_schema",
        "json_schema" => %{
          "name" => "rubric_action_decisions",
          "strict" => true,
          "schema" => schema()
        }
      }
    }
  end

  @doc """
  The user message sent for a resolver request: per criterion, the actions to
  `decide` apart from the already decided `context_actions`, the learner
  evidence pool and the number of decisions expected.
  """
  @spec user_content(map()) :: map()
  def user_content(%{criteria: criteria, evidence_pool: evidence_pool}) do
    criteria = Enum.map(criteria, &prompt_criterion/1)

    %{
      "criteria" => criteria,
      "evidence_pool" => Enum.map(evidence_pool, &%{"id" => &1.id, "text" => &1.text}),
      "decision_count" => Enum.sum(Enum.map(criteria, &length(&1["decide"])))
    }
  end

  defp prompt_criterion(criterion) do
    decidable = MapSet.new(criterion.decidable_action_ids)
    {decide, context} = Enum.split_with(criterion.actions, &MapSet.member?(decidable, &1.id))

    %{
      "criterion_id" => criterion.id,
      "description" => criterion.description,
      "decide" => Enum.map(decide, &%{"id" => &1.id, "description" => &1.description}),
      "context_actions" =>
        Enum.map(
          context,
          &%{
            "id" => &1.id,
            "description" => &1.description,
            "classification" => &1.classification
          }
        )
    }
  end

  defp post(config, payload) do
    url = String.trim_trailing(config.base_url, "/") <> "/v1/chat/completions"

    req_opts =
      Keyword.merge(
        [auth: {:bearer, config.api_key}, json: payload, retry: false],
        config.req_options
      )

    case Req.post(url, req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %Req.Response{}} -> {:error, :upstream_error}
      {:error, %Req.TransportError{reason: reason}} -> transport_error(reason)
      {:error, _exception} -> {:error, :network_error}
    end
  end

  defp transport_error(reason) when reason in [:timeout, :connect_timeout],
    do: {:error, :timeout}

  defp transport_error({:timeout, _detail}), do: {:error, :timeout}
  defp transport_error(_reason), do: {:error, :network_error}

  defp parse(%{"choices" => [%{"message" => %{"refusal" => refusal}} | _]})
       when is_binary(refusal),
       do: {:error, :refused}

  defp parse(%{"choices" => [%{"message" => %{"content" => content}} | _]})
       when is_binary(content) do
    with {:ok, %{"actions" => actions}} when is_list(actions) <- Jason.decode(content),
         decisions when is_list(decisions) <- decisions(actions) do
      {:ok, %{actions: decisions}}
    else
      _malformed -> {:error, :malformed_response}
    end
  end

  defp parse(_body), do: {:error, :malformed_response}

  defp decisions(actions) do
    Enum.reduce_while(actions, [], fn action, acc ->
      case decision(action) do
        {:ok, decision} -> {:cont, [decision | acc]}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      :error -> :error
      reversed -> Enum.reverse(reversed)
    end
  end

  defp decision(
         %{
           "criterion_id" => criterion_id,
           "id" => id,
           "classification" => classification,
           "evidence_ids" => evidence_ids
         } = action
       )
       when is_binary(criterion_id) and is_binary(id) and classification in @classes and
              is_list(evidence_ids) and map_size(action) == 4 do
    if Enum.all?(evidence_ids, &is_binary/1) do
      {:ok,
       %{
         criterion_id: criterion_id,
         id: id,
         classification: classification,
         evidence_ids: evidence_ids
       }}
    else
      :error
    end
  end

  defp decision(_action), do: :error
end
