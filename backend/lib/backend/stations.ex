defmodule Backend.Stations do
  @moduledoc """
  Public context boundary for the Station domain.

  This module serves as the single public entry point for clinical stations,
  conversations, package loading, AI patient generation, evaluation, and speech
  synthesis/transcription.

  Internal modules reside strictly under `Backend.Stations.*` and are not called
  directly by `BackendWeb` controllers.
  """

  alias Backend.Stations.Conversation
  alias Backend.Stations.Evaluator
  alias Backend.Stations.StationAI
  alias Backend.Stations.StationLoader
  alias Backend.Stations.Transcription
  alias Backend.Stations.TTS

  @early_timer_finish_tolerance_ms 2_000

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

  A `:timer` completion is only accepted at or after `deadline_at` (with a
  small tolerance): a client-driven timer finish arriving more than
  `@early_timer_finish_tolerance_ms` before the deadline is rejected with
  `{:error, :deadline_not_reached}`.
  """
  @spec complete_session(String.t(), :user | :timer | term()) ::
          {:ok, Conversation.session()} | {:error, :not_found | :expired | :deadline_not_reached}
  def complete_session(session_id, reason \\ :user)

  def complete_session(session_id, :timer) do
    case Conversation.fetch(session_id) do
      {:ok, %{status: :active} = session} ->
        if timer_finish_allowed?(session) do
          Conversation.complete(session_id, :timer)
        else
          {:error, :deadline_not_reached}
        end

      {:ok, %{status: :completed} = session} ->
        {:ok, session}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def complete_session(session_id, reason) do
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
          | {:error,
             :not_found
             | :expired
             | :completed
             | :station_time_elapsed
             | :station_ai_unavailable
             | term()}
  def create_message(session_id, params) do
    role = Map.get(params, :role) || Map.get(params, "role") || :learner
    modality = normalize_modality(Map.get(params, :modality) || Map.get(params, "modality"))
    text = Map.get(params, :text) || Map.get(params, "text")

    learner_message = %{
      role: normalize_role(role),
      modality: modality,
      text: text
    }

    case Conversation.begin_turn(session_id, learner_message) do
      {:ok, _session, token} -> generate_and_resolve_turn(session_id, token)
      {:error, reason} -> {:error, reason}
    end
  end

  defp generate_and_resolve_turn(session_id, token) do
    package = get_active_package()

    with {:ok, current_session} <- Conversation.fetch(session_id),
         context = format_context(current_session, package),
         {:ok, ai_reply} <- generate_patient_reply(package, context),
         {:ok, verified_reply} <- verify_patient_reply(package, ai_reply),
         patient_message = %{role: :patient, modality: :text, text: verified_reply.text},
         {:ok, _session} <- Conversation.resolve_turn(session_id, token, {:ok, patient_message}) do
      {:ok,
       %{
         reply_text: verified_reply.text,
         reply_audio_url: nil,
         used_facts: Map.get(verified_reply, :used_facts, [])
       }}
    else
      {:error, :station_time_elapsed} ->
        {:error, :station_time_elapsed}

      {:error, _reason} ->
        case Conversation.resolve_turn(session_id, token, :rollback) do
          {:error, :station_time_elapsed} -> {:error, :station_time_elapsed}
          _ -> {:error, :station_ai_unavailable}
        end
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
  Checks whether a session is within its authoritative ten-minute deadline.

  Returns `{:error, :session_time_elapsed}` once `deadline_at` has passed, even
  if the session has not yet been auto-completed by the timer.
  """
  @spec check_session_deadline(String.t()) ::
          {:ok, :within_deadline} | {:error, :session_time_elapsed | :not_found | :expired}
  def check_session_deadline(session_id) do
    case Conversation.fetch(session_id) do
      {:ok, %{status: :completed}} ->
        {:error, :session_time_elapsed}

      {:ok, %{status: :active} = session} ->
        if DateTime.compare(DateTime.utc_now(), session.deadline_at) == :lt do
          {:ok, :within_deadline}
        else
          {:error, :session_time_elapsed}
        end

      {:error, reason} ->
        {:error, reason}
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

  Stable extension point for Ticket 14 / ADR-011 (#125, #127) Jev verification.
  """
  @spec verify_patient_reply(map(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def verify_patient_reply(_package, reply, _opts \\ []) do
    {:ok, reply}
  end

  # ============================================================================
  # Internal Helpers
  # ============================================================================

  defp generate_patient_reply(package, context) do
    StationAI.next_reply(package, context)
  end

  defp timer_finish_allowed?(session) do
    DateTime.diff(session.deadline_at, DateTime.utc_now(), :millisecond) <=
      @early_timer_finish_tolerance_ms
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
