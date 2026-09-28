defmodule Backend.Stations do
  @moduledoc """
  Public context boundary for the Station domain.

  This module serves as the single public entry point for clinical stations,
  conversations, package loading, AI patient generation, evaluation, and speech
  synthesis/transcription.

  Internal modules reside strictly under `Backend.Stations.*` and are not called
  directly by `BackendWeb` controllers.
  """

  require Logger

  alias Backend.Stations.Conversation
  alias Backend.Stations.Evaluator
  alias Backend.Stations.LiveKit
  alias Backend.Stations.LiveKit.RoomService
  alias Backend.Stations.MediaSession
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
    case Conversation.complete(session_id, reason) do
      {:ok, session} ->
        cleanup_voice_room(session_id)
        {:ok, session}

      {:error, reason} ->
        {:error, reason}
    end
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
         {:ok, current_session} <- Conversation.fetch(session_id),
         context = format_context(current_session, package),
         {:ok, ai_reply} <- generate_patient_reply(package, context),
         {:ok, verified_reply} <- verify_patient_reply(package, ai_reply),
         {:ok, _session} <- append_patient_reply(session_id, verified_reply.text) do
      {:ok,
       %{
         reply_text: verified_reply.text,
         reply_audio_url: nil,
         used_facts: Map.get(verified_reply, :used_facts, [])
       }}
    else
      {:error, :not_found} ->
        {:error, :not_found}

      {:error, :expired} ->
        {:error, :expired}

      {:error, :completed} ->
        {:error, :completed}

      {:error, _reason} ->
        _ = rollback_learner_message(session_id, learner_message)
        {:error, :station_ai_unavailable}
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
    :ok = Conversation.discard(session_id)
    cleanup_voice_room(session_id)
    :ok
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
  Issues a short-lived, session-scoped LiveKit access token so the learner's
  browser can join the voice room over WebRTC.

  Requires an active, unexpired session with audio consent and a configured
  LiveKit deployment; enforces a per-session issuance rate limit.

  Ticket 13 / ADR-009 (#116, #117).
  """
  @spec create_voice_session(String.t(), keyword()) ::
          {:ok,
           %{
             url: String.t(),
             token: String.t(),
             room: String.t(),
             identity: String.t(),
             expires_at: DateTime.t()
           }}
          | {:error,
             :not_found | :expired | :completed | :no_consent | :voice_unavailable | :rate_limited}
  def create_voice_session(session_id, _opts \\ []) do
    with {:ok, session} <- Conversation.fetch(session_id),
         :ok <- ensure_active(session),
         :ok <- ensure_audio_consent(session),
         {:ok, config} <- LiveKit.config(),
         :ok <- MediaSession.check_rate_limit(session_id) do
      {token, expires_at} = LiveKit.learner_token(config, session_id, session.expires_at)

      {:ok,
       %{
         url: config.url,
         token: token,
         room: LiveKit.room_name(session_id),
         identity: LiveKit.identity(session_id),
         expires_at: expires_at
       }}
    else
      {:error, :not_configured} -> {:error, :voice_unavailable}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Context the voice worker needs before streaming a session's audio to the
  speech-to-text provider (#118). Only consented, active sessions qualify.
  Keyterms come from the station package's optional `stt_keyterms`, so they
  stay server-side.
  """
  @spec voice_worker_context(String.t()) ::
          {:ok,
           %{
             session_id: String.t(),
             language: String.t(),
             keyterms: [String.t()],
             last_turn_id: non_neg_integer()
           }}
          | {:error, :not_found | :expired | :completed | :no_consent}
  def voice_worker_context(session_id) do
    with {:ok, session} <- Conversation.fetch(session_id),
         :ok <- ensure_active(session),
         :ok <- ensure_audio_consent(session) do
      package = get_active_package()

      {:ok,
       %{
         session_id: session_id,
         language: package["language"] || "pt-BR",
         keyterms: Enum.filter(List.wrap(package["stt_keyterms"]), &is_binary/1),
         last_turn_id: Map.get(session, :last_voice_turn_id, 0)
       }}
    end
  end

  @doc """
  Commits one final learner transcript from the voice worker as a learner
  turn, at most once per monotonic `turn_id` (#118). Generating the patient
  reply is #119.
  """
  @spec commit_voice_transcript(String.t(), pos_integer(), String.t()) ::
          {:ok, :committed | :duplicate}
          | {:error, :not_found | :expired | :completed | :no_consent}
  def commit_voice_transcript(session_id, turn_id, text) do
    with {:ok, session} <- Conversation.fetch(session_id),
         :ok <- ensure_active(session),
         :ok <- ensure_audio_consent(session) do
      Conversation.commit_voice_turn(session_id, turn_id, text)
    end
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

  # Best-effort LiveKit room cleanup: a RoomService failure never fails
  # completion/discard. Only the session id and an error atom are noted,
  # never the token, audio, or transcript.
  defp cleanup_voice_room(session_id) do
    if LiveKit.configured?() do
      room = LiveKit.room_name(session_id)

      case RoomService.delete_room(room) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "LiveKit room cleanup failed for session #{session_id}: #{inspect(reason)}"
          )
      end

      MediaSession.clear_rate_limit(session_id)
    end

    :ok
  end

  defp ensure_active(%{status: :active}), do: :ok
  defp ensure_active(%{status: :completed}), do: {:error, :completed}

  defp ensure_audio_consent(%{audio_consent: true}), do: :ok
  defp ensure_audio_consent(_session), do: {:error, :no_consent}

  defp generate_patient_reply(package, context) do
    StationAI.next_reply(package, context)
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
