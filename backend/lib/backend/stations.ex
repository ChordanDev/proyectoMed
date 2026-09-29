defmodule Backend.Stations do
  @moduledoc """
  Public context boundary for the Station domain.

  This module serves as the single public entry point for clinical stations,
  conversations, package loading, AI patient generation, evaluation, and speech
  synthesis/transcription.

  Internal modules reside strictly under `Backend.Stations.*` and are not called
  directly by `BackendWeb` controllers.
  """

  alias Backend.Stations.CandidateGate
  alias Backend.Stations.Conversation
  alias Backend.Stations.Evaluator
  alias Backend.Stations.JevDecision
  alias Backend.Stations.StationAI
  alias Backend.Stations.StationLoader
  alias Backend.Stations.Transcription
  alias Backend.Stations.TTS

  # ============================================================================
  # Station Package & Metadata
  # ============================================================================

  @doc """
  Returns the active station public metadata (`station_id`, `version`, `language`, `display_title`).
  """
  @spec get_active_station() :: map()
  def get_active_station do
    package = get_active_package()
    Map.take(package, ["station_id", "version", "language", "display_title"])
  end

  @doc """
  Returns the full validated active Station Package.
  """
  @spec get_active_package() :: map()
  def get_active_package do
    StationLoader.active_package()
  end

  @doc """
  Returns the version string of the active Station Package.
  """
  @spec active_version() :: String.t()
  def active_version do
    StationLoader.active_version()
  end

  # ============================================================================
  # Session Lifecycle
  # ============================================================================

  @doc """
  Starts a new station session.

  Accepts `attrs` map or keyword list with `:audio_consent`. Automatically
  defaults `station_id` and `station_version` from the active package when omitted.
  """
  @spec create_session(map() | keyword()) :: Conversation.session()
  def create_session(attrs \\ %{}) do
    attrs = if is_list(attrs), do: Enum.into(attrs, %{}), else: attrs
    package = get_active_package()

    merged_attrs =
      attrs
      |> Map.put_new(:station_id, package["station_id"])
      |> Map.put_new(:station_version, package["version"])

    Conversation.start(merged_attrs)
  end

  @doc """
  Starts a new station session (alias for `create_session/1`).
  """
  @spec start_session(map() | keyword()) :: Conversation.session()
  def start_session(attrs \\ %{}), do: create_session(attrs)

  @doc """
  Fetches a session by id from ephemeral storage.
  """
  @spec get_session(String.t()) ::
          {:ok, Conversation.session()} | {:error, :not_found | :expired}
  def get_session(session_id) do
    Conversation.fetch(session_id)
  end

  @doc """
  Fetches a session by id (alias for `get_session/1`).
  """
  @spec fetch_session(String.t()) ::
          {:ok, Conversation.session()} | {:error, :not_found | :expired}
  def fetch_session(session_id), do: get_session(session_id)

  @doc """
  Completes a session with a completion reason (`:user` or `:timer`).
  """
  @spec complete_session(String.t(), :user | :timer | term()) ::
          {:ok, Conversation.session()} | {:error, :not_found | :expired}
  def complete_session(session_id, reason \\ :user) do
    Conversation.complete(session_id, reason)
  end

  @doc """
  Completes a session (alias for `complete_session/2`).
  """
  @spec finish_session(String.t(), :user | :timer | term()) ::
          {:ok, Conversation.session()} | {:error, :not_found | :expired}
  def finish_session(session_id, reason \\ :user), do: complete_session(session_id, reason)

  # ============================================================================
  # Conversation & Message Exchange
  # ============================================================================

  @doc """
  Posts a learner message to the session conversation and generates the next patient reply.

  Encapsulates:
    1. Appending the learner's message to the session conversation.
    2. Preparing the conversation context with active package rules.
    3. Generating the next bounded patient reply via Station AI.
    4. Passing through the Jev verification seam (`verify_patient_reply/3`).
    5. Appending the patient's reply to the session conversation.
    6. Returning `{:ok, reply_map}` or an error.
  """
  @spec create_message(String.t(), map()) ::
          {:ok, map()}
          | {:error, :not_found | :expired | :completed | :station_ai_unavailable | term()}
  def create_message(session_id, params) do
    role = Map.get(params, :role) || Map.get(params, "role") || :learner
    modality = normalize_modality(Map.get(params, :modality) || Map.get(params, "modality"))
    text = Map.get(params, :text) || Map.get(params, "text")

    learner_message = %{
      role: normalize_role(role),
      modality: modality,
      text: text
    }

    with {:ok, _session} <- Conversation.append_message(session_id, learner_message),
         package = get_active_package(),
         {:ok, current_session} <- Conversation.fetch(session_id) do
      context = format_context(current_session, package)

      deliver_generated_reply(
        session_id,
        package,
        current_session,
        context,
        learner_message,
        params
      )
    end
  end

  defp deliver_generated_reply(
         session_id,
         package,
         current_session,
         context,
         learner_message,
         params
       ) do
    case generate_patient_reply(package, context) do
      {:ok, ai_reply} ->
        verify_and_append_reply(
          session_id,
          package,
          current_session,
          context,
          ai_reply,
          learner_message,
          params
        )

      {:error, _gen_error} ->
        _ = rollback_learner_message(session_id, learner_message)
        {:error, :station_ai_unavailable}
    end
  end

  defp verify_and_append_reply(
         session_id,
         package,
         current_session,
         context,
         ai_reply,
         learner_message,
         params
       ) do
    verify_opts = build_verify_opts(package, current_session, context, params)

    case verify_patient_reply(package, ai_reply, verify_opts) do
      {:ok, verified_reply} ->
        commit_patient_reply(session_id, verified_reply)

      {:error, reason} ->
        _ = rollback_learner_message(session_id, learner_message)
        {:error, reason}
    end
  end

  defp commit_patient_reply(session_id, verified_reply) do
    verified_text = extract_reply_text(verified_reply)
    used_facts = extract_used_facts(verified_reply)

    case append_patient_reply(session_id, verified_text) do
      {:ok, _session} ->
        {:ok,
         %{
           reply_text: verified_text,
           reply_audio_url: nil,
           used_facts: used_facts
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Posts a learner message (alias for `create_message/2`).
  """
  @spec post_message(String.t(), map()) ::
          {:ok, map()}
          | {:error, :not_found | :expired | :completed | :station_ai_unavailable | term()}
  def post_message(session_id, params), do: create_message(session_id, params)

  # ============================================================================
  # Result Evaluation
  # ============================================================================

  @doc """
  Evaluates a completed station session transcript against the active package rubric.

  Returns `{:ok, result}` if the session is completed, or `{:error, reason}` if
  active, expired, or not found.
  """
  @spec get_session_result(String.t()) ::
          {:ok, map()}
          | {:error, :session_not_finished | :not_found | :expired}
  def get_session_result(session_id) do
    case Conversation.fetch(session_id) do
      {:ok, %{status: :completed} = session} ->
        package = get_active_package()
        evaluation = Evaluator.evaluate(package, session)

        criteria =
          Enum.map(evaluation.criteria, fn criterion ->
            %{
              id: criterion.id,
              status: to_string(criterion.status),
              evidence: serialize_evidence(criterion.evidence),
              recommendation: criterion.recommendation
            }
          end)

        {:ok,
         %{
           session_id: session.session_id,
           status: "completed",
           criteria: criteria
         }}

      {:ok, %{status: :active}} ->
        {:error, :session_not_finished}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, :expired} ->
        {:error, :expired}
    end
  end

  @doc """
  Evaluates a session result (alias for `get_session_result/1`).
  """
  @spec evaluate_session(String.t()) ::
          {:ok, map()}
          | {:error, :session_not_finished | :not_found | :expired}
  def evaluate_session(session_id), do: get_session_result(session_id)

  # ============================================================================
  # Audio & Speech Operations
  # ============================================================================

  @doc """
  Transcribes an uploaded audio binary for a given session.
  """
  @spec transcribe_audio(String.t(), binary(), String.t(), keyword()) ::
          {:ok, Transcription.result()} | {:error, Transcription.error()}
  def transcribe_audio(session_id, audio, format, opts \\ []) do
    Transcription.transcribe(session_id, audio, format, opts)
  end

  @doc """
  Synthesizes speech audio for a text string in the context of an active session.
  """
  @spec synthesize_speech(String.t(), String.t(), String.t() | nil, keyword()) ::
          {:ok, TTS.result()} | {:error, TTS.error()}
  def synthesize_speech(session_id, text, voice \\ nil, opts \\ []) do
    TTS.synthesize(session_id, text, voice, opts)
  end

  @doc """
  Returns the list of allowed TTS voices.
  """
  @spec allowed_tts_voices() :: [String.t()]
  def allowed_tts_voices do
    TTS.allowed_voices()
  end

  # ============================================================================
  # Extension Points (ADR-007, Impressos #105, Voice #116, Jev #125, Discard #134)
  # ============================================================================

  @doc """
  Idempotently discards all ephemeral session data when the learner exits.

  Stable extension point for Ticket 16 (#134).
  """
  @spec discard_session(String.t()) :: :ok
  def discard_session(session_id) do
    Conversation.discard(session_id)
  end

  @doc """
  Checks if a session is within its authoritative deadline.

  Stable extension point for Ticket 133 (ten-minute station deadline).
  """
  @spec check_session_deadline(String.t()) ::
          {:ok, :within_deadline} | {:error, :session_time_elapsed | :not_found | :expired}
  def check_session_deadline(session_id) do
    case Conversation.fetch(session_id) do
      {:ok, %{status: :active}} -> {:ok, :within_deadline}
      {:ok, %{status: :completed}} -> {:error, :session_time_elapsed}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Evaluates and releases requested clinical Impressos (physical exam & complementary tests).

  Stable extension point for Ticket 12 / ADR-008 (#105, #107).
  """
  @spec request_impresso(String.t(), map()) ::
          {:ok, map()} | {:error, :not_implemented | term()}
  def request_impresso(_session_id, _request_params) do
    {:error, :not_implemented}
  end

  @doc """
  Creates or joins a real-time conversational voice session via LiveKit/WebRTC.

  Stable extension point for Ticket 13 / ADR-009 (#116, #117).
  """
  @spec create_voice_session(String.t(), keyword()) ::
          {:ok, map()} | {:error, :not_implemented | term()}
  def create_voice_session(_session_id, _opts \\ []) do
    {:error, :not_implemented}
  end

  @doc """
  Verification seam for generated patient replies before display or synthesis.

  Wires directly to `Backend.Stations.CandidateGate.verify_and_deliver/4`.

  Derives trusted case state once per call from the conversation it receives
  (`opts[:conversation]`, an explicitly empty-safe source: absent or malformed
  conversation data projects to `%{learner_turns: 0}`). A caller-supplied
  `:case_state` always wins, so the derived map stays identical across gate
  retries.
  """
  @spec verify_patient_reply(map(), map() | String.t(), keyword()) ::
          {:ok, map() | String.t()} | {:error, term()}
  def verify_patient_reply(package, reply, opts \\ []) do
    candidate_text = extract_reply_text(reply)
    conversation = Keyword.get(opts, :conversation, [])

    gate_opts =
      opts
      |> Keyword.delete(:conversation)
      |> Keyword.put_new(:station_id, package["station_id"] || package[:station_id])
      |> Keyword.put_new(:version, package["version"] || package[:version])
      |> Keyword.put_new(:case_state, project_case_state(conversation))

    case CandidateGate.verify_and_deliver(candidate_text, package, conversation, gate_opts) do
      {:ok, verified_text} ->
        cond do
          verified_text != candidate_text and is_map(reply) ->
            reply = update_reply_text(reply, verified_text)
            {:ok, put_used_facts(reply, [])}

          is_map(reply) ->
            {:ok, update_reply_text(reply, verified_text)}

          true ->
            {:ok, verified_text}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Internal Helpers
  # ============================================================================

  defp build_verify_opts(package, session, context, params) do
    deadline_at = resolve_verify_deadline(params)
    generator = resolve_verify_generator(params, package, context)
    custom_opts = resolve_custom_verify_opts(params)

    base_opts = [
      conversation: session.messages,
      context: context,
      station_id: package["station_id"] || package[:station_id],
      package_id: package["station_id"] || package[:station_id],
      version: package["version"] || package[:version],
      package_version: package["version"] || package[:version],
      deadline_at_monotonic_ms: deadline_at,
      generator: generator,
      case_state: project_case_state(session.messages)
    ]

    base_opts = maybe_put_adapter_opt(base_opts, params)
    Keyword.merge(base_opts, custom_opts)
  end

  # Trusted case-state projection (issue #147): derived once per verification
  # call, before the gate runs, so the Jev retry/recheck path observes the
  # identical map. Only message ROLE labels are trusted; learner message text
  # is never read.
  @learner_role_labels [:learner, "learner", :student, "student"]

  @spec project_case_state(term()) :: %{learner_turns: non_neg_integer()}
  defp project_case_state(messages) when is_list(messages) do
    %{learner_turns: Enum.count(messages, &learner_role_message?/1)}
  end

  defp project_case_state(_other), do: %{learner_turns: 0}

  defp learner_role_message?(%{role: role}), do: role in @learner_role_labels
  defp learner_role_message?(%{"role" => role}), do: role in @learner_role_labels
  defp learner_role_message?(_other), do: false

  defp resolve_verify_deadline(params) do
    case Map.get(params, :deadline_at_monotonic_ms) ||
           Map.get(params, "deadline_at_monotonic_ms") do
      d when is_integer(d) -> d
      _ -> resolve_fallback_deadline(params)
    end
  end

  defp resolve_fallback_deadline(params) do
    case Map.get(params, :deadline_ms) || Map.get(params, "deadline_ms") do
      ms when is_integer(ms) and ms > 0 -> JevDecision.monotonic_deadline_at(ms)
      _ -> JevDecision.monotonic_deadline_at()
    end
  end

  defp resolve_verify_generator(params, package, context) do
    case Map.get(params, :generator) || Map.get(params, "generator") do
      gen when is_function(gen) -> gen
      _ -> fn -> generate_patient_reply(package, context) end
    end
  end

  defp resolve_custom_verify_opts(params) do
    case Map.get(params, :verify_opts) || Map.get(params, "verify_opts") do
      opts when is_list(opts) -> opts
      _ -> []
    end
  end

  defp maybe_put_adapter_opt(base_opts, params) do
    case Map.get(params, :adapter) || Map.get(params, "adapter") do
      adapter when not is_nil(adapter) -> Keyword.put(base_opts, :adapter, adapter)
      _ -> base_opts
    end
  end

  defp extract_reply_text(%{text: text}) when is_binary(text), do: text
  defp extract_reply_text(%{"text" => text}) when is_binary(text), do: text
  defp extract_reply_text(text) when is_binary(text), do: text
  defp extract_reply_text(other), do: other

  defp extract_used_facts(%{used_facts: facts}) when is_list(facts), do: facts
  defp extract_used_facts(%{"used_facts" => facts}) when is_list(facts), do: facts
  defp extract_used_facts(_), do: []

  defp update_reply_text(reply, text) do
    cond do
      is_map(reply) and Map.has_key?(reply, "text") -> Map.put(reply, "text", text)
      is_map(reply) -> Map.put(reply, :text, text)
      true -> text
    end
  end

  defp put_used_facts(reply, facts) do
    cond do
      is_map(reply) and Map.has_key?(reply, "used_facts") -> Map.put(reply, "used_facts", facts)
      is_map(reply) -> Map.put(reply, :used_facts, facts)
      true -> reply
    end
  end

  defp resolve_station_ai_adapter do
    case Application.get_env(
           :backend,
           :station_ai_adapter,
           StationAI.OpenAIAdapter
         ) do
      Backend.StationAI.OpenAIAdapter -> StationAI.OpenAIAdapter
      Backend.StationAI.NoOpAdapter -> StationAI.NoOpAdapter
      other -> other
    end
  end

  defp generate_patient_reply(package, context) do
    adapter = resolve_station_ai_adapter()

    case adapter.next_reply(package, context) do
      {:ok, %{text: text, used_facts: used_facts}} when is_list(used_facts) ->
        {:ok, %{text: text, used_facts: used_facts}}

      {:ok, %{text: text}} ->
        {:ok, %{text: text, used_facts: []}}

      {:ok, text} when is_binary(text) ->
        {:ok, %{text: text, used_facts: []}}

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:invalid_adapter_output, other}}
    end
  end

  defp append_patient_reply(session_id, reply_text) do
    case Conversation.append_message(session_id, %{
           role: :patient,
           modality: :text,
           text: reply_text
         }) do
      {:ok, session} -> {:ok, session}
      {:error, :completed} -> {:ok, :completed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp rollback_learner_message(session_id, learner_message) do
    Conversation.pop_last_message(session_id, learner_message)
  end

  defp format_context(session, package) do
    conversation =
      Enum.map(session.messages, fn msg ->
        role =
          case msg.role do
            r when r in [:learner, "learner", :student, "student"] -> :student
            r when r in [:patient, "patient"] -> :patient
            _ -> :student
          end

        %{role: role, text: msg.text}
      end)

    %{
      conversation: conversation,
      language: package["language"] || "pt-BR"
    }
  end

  defp normalize_modality("voice"), do: :voice
  defp normalize_modality(:voice), do: :voice
  defp normalize_modality(_), do: :text

  defp normalize_role("learner"), do: :learner
  defp normalize_role(:learner), do: :learner
  defp normalize_role(other), do: other

  defp serialize_evidence(evidence) when is_list(evidence) do
    Enum.map(evidence, fn
      %{text: text} -> text
      %{"text" => text} -> text
      text when is_binary(text) -> text
      other -> to_string(other)
    end)
  end

  defp serialize_evidence(_), do: []
end
