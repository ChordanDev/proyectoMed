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

  alias Backend.Stations.CandidateGate
  alias Backend.Stations.Conversation
  alias Backend.Stations.Evaluator
  alias Backend.Stations.Impressos
  alias Backend.Stations.JevDecision
  alias Backend.Stations.LiveKit
  alias Backend.Stations.LiveKit.RoomService
  alias Backend.Stations.MediaSession
  alias Backend.Stations.Qualification
  alias Backend.Stations.RubricAssessment
  alias Backend.Stations.StationAI
  alias Backend.Stations.StationLoader
  alias Backend.Stations.Transcription
  alias Backend.Stations.TTS

  @early_timer_finish_tolerance_ms 2_000
  @default_learner_message_max_characters 2_000

  # ============================================================================
  # Station Package & Metadata
  # ============================================================================

  @doc """
  Returns the active station public metadata (`station_id`, `version`, `language`,
  `display_title`) and the learner-facing `candidate_brief`, projected to its
  `scenario` and `tasks` so nothing examiner-only reaches the learner's client.
  """
  @spec get_active_station() :: map()
  def get_active_station do
    package = get_active_package()

    package
    |> Map.take(["station_id", "version", "language", "display_title"])
    |> Map.put("candidate_brief", Map.take(package["candidate_brief"], ["scenario", "tasks"]))
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
          complete_and_cleanup_voice_room(session_id, :timer)
        else
          {:error, :deadline_not_reached}
        end

      {:ok, %{status: :completed} = session} ->
        cleanup_voice_room(session_id)
        {:ok, session}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def complete_session(session_id, reason) do
    complete_and_cleanup_voice_room(session_id, reason)
  end

  defp complete_and_cleanup_voice_room(session_id, reason) do
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

  A message whose text exceeds the learner message limit (2,000 characters by
  default, config `:learner_message_max_characters`) is rejected with
  `{:error, :message_too_long}` before it enters the conversation or reaches
  Jev. It is never truncated.

  Encapsulates:
    1. Appending the learner's message to the session conversation.
    2. Preparing the conversation context with active package rules.
    3. Generating the next bounded patient reply via Station AI.
    4. Passing through the Jev verification seam (`verify_patient_reply/3`).
    5. Appending the patient's reply to the session conversation.
    6. Returning `{:ok, reply_map}` or an error.

  When Jev refuses the patient reply (`low_confidence` or `semantic_refusal`),
  the learner turn is kept without a patient reply and
  `{:error, {:refused, reason, learner_turn}}` is returned. This also applies
  when the single regeneration after a refusal cannot be verified within the
  deadline (issue #256). Technical failures, including a timeout with no prior
  refusal, roll the learner turn back, so a retry does not duplicate it.
  """
  @spec create_message(String.t(), map()) ::
          {:ok, map()}
          | {:error,
             :not_found
             | :expired
             | :completed
             | :station_time_elapsed
             | :station_ai_unavailable
             | :message_too_long
             | {:refused, :low_confidence | :semantic_refusal, Conversation.message()}
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

    with :ok <- validate_learner_message_length(text),
         {:ok, _session, token} <- Conversation.begin_turn(session_id, learner_message) do
      generate_and_resolve_turn(session_id, token, params)
    end
  end

  # Domain policy: an oversized message would be resent to Jev on every later
  # turn of the session, so it is rejected before it enters the conversation.
  defp validate_learner_message_length(text) when is_binary(text) do
    if String.length(text) > learner_message_max_characters() do
      {:error, :message_too_long}
    else
      :ok
    end
  end

  defp validate_learner_message_length(_text), do: :ok

  defp learner_message_max_characters do
    Application.get_env(
      :backend,
      :learner_message_max_characters,
      @default_learner_message_max_characters
    )
  end

  defp generate_and_resolve_turn(session_id, token, params) do
    package = get_active_package()

    with {:ok, current_session} <- Conversation.fetch(session_id),
         context = format_context(current_session, package),
         {:ok, ai_reply} <- generate_patient_reply(package, context) do
      verify_and_resolve_turn(
        session_id,
        token,
        package,
        current_session,
        context,
        ai_reply,
        params
      )
    else
      {:error, _reason} ->
        rollback_turn(session_id, token, :station_ai_unavailable)
    end
  end

  defp verify_and_resolve_turn(
         session_id,
         token,
         package,
         current_session,
         context,
         ai_reply,
         params
       ) do
    verify_opts = build_verify_opts(package, current_session, context, params)

    case verify_patient_reply(package, ai_reply, verify_opts) do
      {:ok, verified_reply} ->
        commit_patient_reply(session_id, token, verified_reply)

      {:error, {:refused, refusal}} ->
        keep_learner_turn(session_id, token, refusal)

      {:error, reason} ->
        rollback_turn(session_id, token, reason)
    end
  end

  # A refused patient reply is dropped, but the learner turn is real rubric
  # evidence, so it is committed without a reply (issue #235). The refused
  # text is never stored or returned.
  defp keep_learner_turn(session_id, token, refusal) do
    case Conversation.resolve_turn(session_id, token, :keep_learner_turn) do
      {:ok, session} ->
        {:error, {:refused, refusal, List.last(session.messages)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp commit_patient_reply(session_id, token, verified_reply) do
    verified_text = extract_reply_text(verified_reply)
    used_facts = extract_used_facts(verified_reply)
    patient_message = %{role: :patient, modality: :text, text: verified_text}

    case Conversation.resolve_turn(session_id, token, {:ok, patient_message}) do
      {:ok, _session} ->
        {:ok,
         %{
           reply_text: verified_text,
           reply_audio_url: nil,
           used_facts: used_facts
         }}

      {:error, :station_time_elapsed} ->
        {:error, :station_time_elapsed}

      {:error, _reason} ->
        rollback_turn(session_id, token, :station_ai_unavailable)
    end
  end

  # Rolls back the pending learner turn. A turn already settled by the deadline
  # grace timer reports `:station_time_elapsed`, which wins over `reason`.
  defp rollback_turn(session_id, token, reason) do
    case Conversation.resolve_turn(session_id, token, :rollback) do
      {:error, :station_time_elapsed} -> {:error, :station_time_elapsed}
      _ -> {:error, reason}
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

  @doc """
  Assesses a completed station session against the active package rubric with
  grounded evidence and exact point estimates (issue #128).

  Uses the same session lookup and completed-session requirement as
  `get_session_result/1`. `opts` are passed to
  `Backend.Stations.RubricAssessment.assess/3`.

  Returns `{:error, {:invalid_attempt, reason}}`, with no partial criteria,
  when the decision provider fails technically or the rubric cannot be
  assessed exactly. The legacy endpoint keeps `get_session_result/1`;
  the versioned educational endpoint uses `get_educational_result/1`.
  """
  @spec assess_session(String.t(), keyword()) ::
          {:ok, RubricAssessment.t()}
          | {:error,
             :session_not_finished
             | :not_found
             | :expired
             | {:invalid_attempt, RubricAssessment.attempt_error()}}
  def assess_session(session_id, opts \\ []) do
    with {:ok, session} <- fetch_completed_session(session_id) do
      RubricAssessment.assess(get_active_package(), session, opts)
    end
  end

  @doc """
  Returns the explicit v2 educational result, without provider diagnostics or persistence.

  After grading, `Backend.Stations.LearnerFeedback` replaces the
  `recommendation` of each assessed criterion with generated learner feedback
  (issue #215), cached with the session and bound to the graded outcome. Any
  feedback failure keeps the authored `practice_recommendation`; grading is
  never changed.
  """
  @spec get_educational_result(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_educational_result(session_id, opts \\ []) do
    with {:ok, assessment} <- assess_session(session_id, opts) do
      package = get_active_package()
      assessment = Backend.Stations.LearnerFeedback.attach(assessment, package, session_id)
      {:ok, Backend.Stations.EducationalResult.serialize(session_id, assessment, package)}
    end
  end

  defp fetch_completed_session(session_id) do
    case Conversation.fetch(session_id) do
      {:ok, %{status: :completed} = session} -> {:ok, session}
      {:ok, %{status: :active}} -> {:error, :session_not_finished}
      {:error, reason} -> {:error, reason}
    end
  end

  # ============================================================================
  # Qualification
  # ============================================================================

  @doc """
  Runs the fictional qualification cases of `station_id` through the Jev
  dialogue gate and the rubric assessment (issue #130).

  The summary holds identifiers and outcome labels only, and never a verdict.
  See `Backend.Stations.Qualification`.
  """
  @spec run_qualification(String.t(), keyword()) ::
          {:ok, Qualification.summary()} | {:error, Qualification.load_error()}
  def run_qualification(station_id, opts \\ []), do: Qualification.run(station_id, opts)

  @doc "Renders a qualification summary as a label-level plain-text report."
  @spec render_qualification(Qualification.summary()) :: String.t()
  def render_qualification(summary), do: Qualification.render(summary)

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
  Matches a learner's Impresso request text against the active package's
  authored impressos and atomically records the outcome on the session.

  `request_params` accepts `"text"` (required, non-blank, at most the learner
  message limit, otherwise `{:error, :message_too_long}`) and an optional
  `"request_id"` for idempotent retries; the server generates one when
  omitted.

  Returns `{:ok, %{request_id, decision, released_impressos, newly_released,
  feedback_message}}`, where `decision` is `"released"`, `"already_released"`,
  or `"unavailable"`.

  Stable extension point for Ticket 12 / ADR-008 (#105, #107).
  """
  @spec request_impresso(String.t(), map()) ::
          {:ok, map()}
          | {:error, :not_found | :expired | :completed | :invalid_request | :message_too_long}
  def request_impresso(session_id, request_params) do
    text = get_param(request_params, :text)

    # The request text enters the rubric evidence pool, so it shares the
    # learner message limit and is rejected (never truncated) before recording.
    with :ok <- validate_impresso_text(text),
         :ok <- validate_learner_message_length(text) do
      package = get_active_package()
      normalized_text = Impressos.normalize(text)
      matched_ids = Impressos.match(package["impressos"] || [], normalized_text)
      request_id = resolve_request_id(request_params)

      case Conversation.record_impresso_request(session_id, request_id, matched_ids, text) do
        {:ok, %{event: event, session: session}} ->
          {:ok, build_impresso_response(package, event, session)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Lists the impressos currently released for a session, in release order.

  Allowed for both active and completed sessions.
  """
  @spec list_impressos(String.t()) ::
          {:ok, %{released_impressos: [map()]}} | {:error, :not_found | :expired}
  def list_impressos(session_id) do
    case Conversation.fetch(session_id) do
      {:ok, session} ->
        package = get_active_package()

        {:ok,
         %{
           released_impressos:
             to_impresso_objects(index_impressos(package), session.released_impressos)
         }}

      {:error, reason} ->
        {:error, reason}
    end
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
  `last_turn_id` is the committed learner cursor. `turn_id_floor` also covers
  cancelled turn IDs; a fresh worker must allocate strictly above this floor.
  """
  @spec voice_worker_context(String.t()) ::
          {:ok,
           %{
             session_id: String.t(),
             language: String.t(),
             keyterms: [String.t()],
             last_turn_id: non_neg_integer(),
             turn_id_floor: non_neg_integer()
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
         last_turn_id: Map.get(session, :last_voice_turn_id, 0),
         turn_id_floor:
           max(
             Map.get(session, :last_voice_turn_id, 0),
             Map.get(session, :cancelled_voice_turn_id, 0)
           )
       }}
    end
  end

  @doc """
  Commits one final learner transcript from the voice worker as a learner
  turn, at most once per monotonic `turn_id` (#118). Generating the patient
  reply is #119.

  Follows the station deadline like `process_voice_turn/3`: a new turn at or
  after the deadline, or any turn on a session the timer completed, returns
  `{:error, :station_time_elapsed}` and appends nothing.
  """
  @spec commit_voice_transcript(String.t(), pos_integer(), String.t()) ::
          {:ok, :committed | :duplicate}
          | {:error,
             :not_found
             | :expired
             | :completed
             | :no_consent
             | :stale_generation
             | :station_time_elapsed}
  def commit_voice_transcript(session_id, turn_id, text) do
    with {:ok, session} <- Conversation.fetch(session_id),
         :ok <- ensure_voice_turn_open(session),
         :ok <- ensure_audio_consent(session) do
      Conversation.commit_voice_turn(session_id, turn_id, text)
    end
  end

  @doc """
  Processes a real-time learner voice turn (#119).

  Encapsulates:
    1. Validating active session state and audio consent.
    2. Atomically committing the learner turn via `Conversation.begin_voice_turn/3`
       which assigns a session-scoped monotonic generation identity and enforces
       the station deadline.
       Returns `{:ok, :duplicate}` if the turn is not newer than the last committed turn,
       except retries of the latest failed generation preserve its technical failure.
    3. Formatting role-labelled context from the active package and session messages.
    4. Generating the next bounded patient reply via `StationAI.next_reply/2`.
    5. Passing through the `verify_patient_reply/3` seam, the single authority on
       what the patient may say on both channels. The verified reply is used as
       returned, exactly as the text path does; there is no voice-only filter.
    6. Failing closed: a reply that is denied, refused, or left without usable
       text fails the generation as `:station_ai_unavailable` and commits no
       patient content.
    7. Atomically resolving only matching generation via `Conversation.resolve_patient_reply/3`.
    8. Returning `{:ok, %{reply_text: text, turn_id: turn_id, generation_id: generation_id, used_facts: facts}}`
       solely on success. Stale, cancelled, completed, or expired generations never return text.

  The station deadline is enforced in `Backend.Stations.Conversation`, not here.
  A new turn at or after the deadline, or any turn on a session the timer
  completed, returns `{:error, :station_time_elapsed}` and appends nothing; a
  session completed for any other reason still returns `{:error, :completed}`.
  A generation in flight when the deadline fires keeps the grace window: a reply
  resolved inside it is a normal success on a session that is then completed
  with reason `:timer`, and one resolved after it returns
  `{:error, :station_time_elapsed}` without being recorded as a failed generation.
  """
  @spec process_voice_turn(String.t(), pos_integer(), String.t()) ::
          {:ok,
           %{
             reply_text: String.t(),
             turn_id: pos_integer(),
             generation_id: pos_integer(),
             used_facts: StationAI.revealable_facts()
           }}
          | {:ok, :duplicate}
          | {:error,
             :not_found
             | :expired
             | :completed
             | :no_consent
             | :stale_generation
             | :invalid_transcript
             | :station_time_elapsed
             | :station_ai_unavailable
             | term()}
  def process_voice_turn(session_id, turn_id, text)
      when is_binary(session_id) and is_integer(turn_id) and turn_id > 0 and is_binary(text) do
    case String.trim(text) do
      "" ->
        {:error, :invalid_transcript}

      trimmed_text ->
        with {:ok, session} <- Conversation.fetch(session_id),
             :ok <- ensure_voice_turn_open(session),
             :ok <- ensure_audio_consent(session),
             {:ok, :committed, generation_id} <-
               Conversation.begin_voice_turn(session_id, turn_id, trimmed_text) do
          process_voice_reply(session_id, turn_id, generation_id)
        else
          {:ok, :duplicate} ->
            {:ok, :duplicate}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  def process_voice_turn(_session_id, _turn_id, _text), do: {:error, :invalid_transcript}

  @doc """
  Explicitly cancels a pending voice turn generation (#119).

  Supports:
    * `cancel_voice_turn(session_id)` — cancels active generation unconditionally.
    * `cancel_voice_turn(session_id, generation_id)` when integer — cancels if generation matches (keeps generation cancel behavior for existing tests).
    * `cancel_voice_turn(session_id, criteria)` when keyword list or map — cancels by expected `turn_id` and/or `generation_id`, e.g. `[turn_id: 1]`, `%{turn_id: 1}`, `%{expected_turn_id: 1}`.

  Turn-only criteria atomically fence future admission through the monotonic turn
  ID, including delayed POSTs and retries. `:stale_generation` still means there
  was no matching active generation, but the admission fence is established.
  Newer independent active turns are untouched. Generation-qualified criteria
  install a fence only on a match; integer generation-only behavior is unchanged.
  """
  @spec cancel_voice_turn(String.t(), pos_integer() | keyword() | map() | nil) ::
          {:ok, :cancelled}
          | {:error, :not_found | :expired | :completed | :stale_generation}
  def cancel_voice_turn(session_id, criteria \\ nil)

  def cancel_voice_turn(session_id, nil) do
    Conversation.cancel_generation(session_id, nil)
  end

  def cancel_voice_turn(session_id, generation_id)
      when is_integer(generation_id) and generation_id > 0 do
    Conversation.cancel_generation(session_id, generation_id)
  end

  def cancel_voice_turn(session_id, criteria) when is_list(criteria) or is_map(criteria) do
    Conversation.cancel_voice_turn(session_id, criteria)
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

  # Voice turns name the timer as the reason a session is closed, as the
  # conversation does. The deadline of a still-active session is checked there.
  defp ensure_voice_turn_open(%{status: :completed, completion_reason: :timer}),
    do: {:error, :station_time_elapsed}

  defp ensure_voice_turn_open(session), do: ensure_active(session)

  defp ensure_audio_consent(%{audio_consent: true}), do: :ok
  defp ensure_audio_consent(_session), do: {:error, :no_consent}

  defp process_voice_reply(session_id, turn_id, generation_id) do
    package = get_active_package()

    with {:ok, current_session} <- Conversation.fetch(session_id),
         :ok <- ensure_voice_turn_open(current_session),
         context = format_context(current_session, package),
         {:ok, ai_reply} <- generate_patient_reply(package, context),
         verify_opts = build_verify_opts(package, current_session, context, %{}),
         {:ok, verified_reply} <- verify_patient_reply(package, ai_reply, verify_opts),
         verified_text = extract_reply_text(verified_reply),
         {:ok, _session} <-
           Conversation.resolve_patient_reply(session_id, generation_id, verified_text) do
      {:ok,
       %{
         reply_text: verified_text,
         turn_id: turn_id,
         generation_id: generation_id,
         used_facts: extract_used_facts(verified_reply)
       }}
    else
      {:error, :stale_generation} ->
        {:error, :stale_generation}

      # The deadline cut this generation off: an end of session, not a failure.
      {:error, :station_time_elapsed} ->
        {:error, :station_time_elapsed}

      {:error, :completed} ->
        {:error, :completed}

      {:error, :expired} ->
        {:error, :expired}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, _reason} ->
        case Conversation.fail_generation(session_id, generation_id, :station_ai_unavailable) do
          {:ok, :failed} -> {:error, :station_ai_unavailable}
          {:error, reason} -> {:error, reason}
        end
    end
  end

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
      _ -> fn _pkg, _conv, _remaining_ms, guidance -> regenerate(package, context, guidance) end
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

  # The gate's single regeneration: `guidance.withheld_fact_ids` names, by authored
  # id, the on-request facts the refused candidate stated without being asked
  # (issue #242). The refused text itself never reaches the regeneration.
  defp regenerate(package, context, %{withheld_fact_ids: [_ | _] = ids}) do
    generate_patient_reply(package, Map.put(context, :withheld_fact_ids, ids))
  end

  defp regenerate(package, context, _guidance), do: generate_patient_reply(package, context)

  # Every patient generation (the first candidate and the gate's regeneration)
  # logs its latency at debug level so live runs can tune the Jev budget
  # (issue #256). Only the outcome category and milliseconds are logged:
  # never the prompt, the learner text or the patient text.
  defp generate_patient_reply(package, context) do
    started_at = JevDecision.monotonic_now_ms()
    result = run_patient_adapter(package, context)
    outcome = if match?({:ok, _}, result), do: "ok", else: "error"

    Logger.debug(
      "[Stations] patient_generation latency_ms=#{JevDecision.monotonic_now_ms() - started_at} outcome=#{outcome}"
    )

    result
  end

  defp run_patient_adapter(package, context) do
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

  defp get_param(params, key) do
    Map.get(params, key) || Map.get(params, Atom.to_string(key))
  end

  defp validate_impresso_text(text) when is_binary(text) do
    if String.trim(text) == "" do
      {:error, :invalid_request}
    else
      :ok
    end
  end

  defp validate_impresso_text(_text), do: {:error, :invalid_request}

  defp resolve_request_id(params) do
    case get_param(params, :request_id) do
      id when is_binary(id) and id != "" -> id
      _ -> Impressos.generate_request_id()
    end
  end

  defp build_impresso_response(package, event, session) do
    impressos_by_id = index_impressos(package)

    %{
      request_id: event.request_id,
      decision: to_string(event.decision),
      released_impressos: to_impresso_objects(impressos_by_id, session.released_impressos),
      newly_released: to_impresso_objects(impressos_by_id, event.released_ids),
      feedback_message: impresso_feedback_message(event, impressos_by_id)
    }
  end

  defp impresso_feedback_message(%{decision: :unavailable}, _impressos_by_id) do
    "Exame não disponível nesta estação"
  end

  defp impresso_feedback_message(%{decision: :released, released_ids: ids}, impressos_by_id) do
    "Impresso liberado: #{impresso_titles(impressos_by_id, ids)}"
  end

  defp impresso_feedback_message(
         %{decision: :already_released, matched_ids: ids},
         impressos_by_id
       ) do
    "Impresso já liberado: #{impresso_titles(impressos_by_id, ids)}"
  end

  defp impresso_titles(impressos_by_id, ids) do
    Enum.map_join(ids, ", ", fn id -> impressos_by_id[id]["title"] end)
  end

  defp index_impressos(package) do
    (package["impressos"] || [])
    |> Enum.into(%{}, fn impresso -> {impresso["id"], impresso} end)
  end

  defp to_impresso_objects(impressos_by_id, ids) do
    Enum.map(ids, fn id ->
      impresso = impressos_by_id[id]

      %{
        id: impresso["id"],
        title: impresso["title"],
        category: impresso["category"],
        content: impresso["content"]
      }
    end)
  end
end
