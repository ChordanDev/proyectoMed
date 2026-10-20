/** Learner-facing "cenário de atuação" and the ordered station tasks. */
export interface CandidateBrief {
  scenario: string;
  tasks: string[];
}

/**
 * The single voice experience the deployment offers (#270): the real-time
 * LiveKit panel, the turn-based record/play buttons, or no voice at all.
 */
export type VoiceMode = "realtime" | "turn" | "off";

const voiceModes: readonly VoiceMode[] = ["realtime", "turn", "off"];

export interface ActiveStation {
  station_id: string;
  version: string;
  display_title: string;
  language: string;
  candidate_brief: CandidateBrief;
  voice_mode: VoiceMode;
}

export interface StartSessionRequest {
  audio_consent: boolean;
}

export interface Session {
  session_id: string;
  station_id: string;
  station_version: string;
  audio_consent: boolean;
  started_at: string;
  expires_at: string;
  deadline_at: string;
  server_now: string;
}

export type SessionStatus = "active" | "completed";

export interface SessionMessage {
  role: "learner" | "patient";
  text: string;
}

export interface SessionDetail extends Session {
  status: SessionStatus;
  completion_reason: string | null;
  messages: SessionMessage[];
}

export interface SendMessageRequest {
  role: "learner";
  modality: "voice" | "text";
  text: string;
}

/** A verified patient reply. An older backend sends no `outcome`. */
export interface PatientMessageReply {
  outcome?: "patient_reply";
  reply_text: string;
  reply_audio_url?: string | null;
  server_now: string;
}

/**
 * A learner turn addressed to the examiner (#274): the backend kept it without
 * generating a patient reply.
 */
export interface ExaminerAcknowledgedReply {
  outcome: "examiner_acknowledged";
  reply_text: null;
  learner_turn: SessionMessage;
  server_now: string;
}

export type MessageReply = PatientMessageReply | ExaminerAcknowledgedReply;

export interface VoiceSession {
  url: string;
  token: string;
  room: string;
  identity: string;
  expires_at: string;
}

export type FinishReason = "user" | "timer";

export interface CompletedSession {
  session_id: string;
  status: "completed";
  completed_at: string;
}

export type LegacyCriterionStatus = "met" | "omitted" | "uncertain";

export interface LegacyResultCriterion {
  id: string;
  status: LegacyCriterionStatus;
  evidence: string[];
  recommendation: string;
}

export interface TranscriptionResult {
  text: string;
  duration_seconds?: number | null;
  transcribed_at: string;
}

export interface LegacySessionResult {
  session_id: string;
  status: "completed";
  criteria: LegacyResultCriterion[];
}

export type CriterionStatus = "assessed" | "uncertain" | "not_observable" | "not_applicable";
export interface ResultEvidence { id: string; role: "learner" | "patient"; text: string }
interface CriterionBase {
  id: string;
  description: string;
  max_points: string;
  evidence_ids: string[];
  evidence: ResultEvidence[];
  recommendation: string;
}
export type ResultCriterion = CriterionBase & (
  | { status: "assessed"; reason: null; level: string; level_description: string; points: string }
  | { status: "uncertain" | "not_observable" | "not_applicable"; reason: string }
);
export interface SessionResult {
  schema_version: "2";
  session_id: string;
  status: "completed";
  placeholder: boolean;
  criteria: ResultCriterion[];
  coverage: Record<CriterionStatus, number>;
  estimates: {
    total: string | null;
    scored_subtotal: string;
    scored_max: string;
    eligible_max: string;
    unresolved: { id: string; status: "uncertain" | "not_observable" }[];
  };
}

export interface Impresso {
  id: string;
  title: string;
  category: string;
  content: string;
}

export interface RequestImpressoRequest {
  text: string;
  request_id?: string;
}

export type ImpressoDecision = "released" | "already_released" | "unavailable";

export interface RequestImpressoResponse {
  request_id: string;
  decision: ImpressoDecision;
  released_impressos: Impresso[];
  newly_released: Impresso[];
  feedback_message: string;
}

export interface ListImpressosResponse {
  released_impressos: Impresso[];
}

export interface DiscardSessionOptions {
  keepalive?: boolean;
}

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    // The learner turn the backend kept although it refused the patient reply.
    readonly learnerTurn?: SessionMessage,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

type JsonObject = Record<string, unknown>;

const invalid = (label: string): never => {
  throw new Error(`Invalid ${label} response`);
};

const objectValue = (value: unknown, label: string): JsonObject =>
  typeof value === "object" && value !== null
    ? (value as JsonObject)
    : invalid(label);

const stringValue = (body: JsonObject, key: string, label: string): string =>
  typeof body[key] === "string" ? body[key] : invalid(label);

const booleanValue = (body: JsonObject, key: string, label: string): boolean =>
  typeof body[key] === "boolean" ? body[key] : invalid(label);

const literalValue = <T extends string>(
  body: JsonObject,
  key: string,
  allowed: readonly T[],
  label: string,
): T => {
  const value = body[key];
  return typeof value === "string" && allowed.includes(value as T)
    ? (value as T)
    : invalid(label);
};

const stringList = (body: JsonObject, key: string, label: string): string[] => {
  const value = body[key];
  return Array.isArray(value) && value.every((item) => typeof item === "string")
    ? value
    : invalid(label);
};

const decodeCandidateBrief = (value: unknown): CandidateBrief => {
  const body = objectValue(value, "candidate brief");
  const tasks = stringList(body, "tasks", "candidate brief");
  return {
    scenario: stringValue(body, "scenario", "candidate brief"),
    tasks: tasks.length > 0 ? tasks : invalid("candidate brief"),
  };
};

const decodeActiveStation = (value: unknown): ActiveStation => {
  const body = objectValue(value, "active station");
  return {
    station_id: stringValue(body, "station_id", "active station"),
    version: stringValue(body, "version", "active station"),
    display_title: stringValue(body, "display_title", "active station"),
    language: stringValue(body, "language", "active station"),
    candidate_brief: decodeCandidateBrief(body.candidate_brief),
    // An older backend sends no voice_mode: keep the turn-based experience.
    voice_mode: voiceModes.includes(body.voice_mode as VoiceMode)
      ? (body.voice_mode as VoiceMode)
      : "turn",
  };
};

const decodeSession = (value: unknown): Session => {
  const body = objectValue(value, "session");
  return {
    session_id: stringValue(body, "session_id", "session"),
    station_id: stringValue(body, "station_id", "session"),
    station_version: stringValue(body, "station_version", "session"),
    audio_consent: booleanValue(body, "audio_consent", "session"),
    started_at: stringValue(body, "started_at", "session"),
    expires_at: stringValue(body, "expires_at", "session"),
    deadline_at: stringValue(body, "deadline_at", "session"),
    server_now: stringValue(body, "server_now", "session"),
  };
};

const sessionStatuses: readonly SessionStatus[] = ["active", "completed"];

const decodeSessionMessage = (value: unknown): SessionMessage => {
  const body = objectValue(value, "session message");
  return {
    role: literalValue(
      body,
      "role",
      ["learner", "patient"],
      "session message",
    ),
    text: stringValue(body, "text", "session message"),
  };
};

const decodeSessionDetail = (value: unknown): SessionDetail => {
  const body = objectValue(value, "session detail");
  const messages = Array.isArray(body.messages)
    ? body.messages
    : invalid("session detail");
  const completionReason = body.completion_reason;
  if (completionReason !== null && typeof completionReason !== "string") {
    invalid("session detail");
  }

  return {
    ...decodeSession(value),
    status: literalValue(body, "status", sessionStatuses, "session detail"),
    completion_reason: completionReason as string | null,
    messages: messages.map(decodeSessionMessage),
  };
};

const decodeMessageReply = (value: unknown): MessageReply => {
  const body = objectValue(value, "message");
  const hasAudioUrl = Object.prototype.hasOwnProperty.call(
    body,
    "reply_audio_url",
  );
  const audioUrl = body.reply_audio_url;

  if (hasAudioUrl && audioUrl !== null && typeof audioUrl !== "string") {
    invalid("message");
  }

  if (body.outcome === "examiner_acknowledged") {
    const learnerTurn = decodeKeptLearnerTurn(body);
    return {
      outcome: "examiner_acknowledged",
      reply_text: null,
      learner_turn: learnerTurn ?? invalid("message"),
      server_now: stringValue(body, "server_now", "message"),
    };
  }

  return {
    ...(body.outcome === "patient_reply" ? { outcome: "patient_reply" as const } : {}),
    reply_text: stringValue(body, "reply_text", "message"),
    server_now: stringValue(body, "server_now", "message"),
    ...(hasAudioUrl ? { reply_audio_url: audioUrl as string | null } : {}),
  };
};

const decodeVoiceSession = (value: unknown): VoiceSession => {
  const body = objectValue(value, "voice session");
  return {
    url: stringValue(body, "url", "voice session"),
    token: stringValue(body, "token", "voice session"),
    room: stringValue(body, "room", "voice session"),
    identity: stringValue(body, "identity", "voice session"),
    expires_at: stringValue(body, "expires_at", "voice session"),
  };
};

const decodeCompletedSession = (value: unknown): CompletedSession => {
  const body = objectValue(value, "completed session");
  return {
    session_id: stringValue(body, "session_id", "completed session"),
    status: literalValue(body, "status", ["completed"], "completed session"),
    completed_at: stringValue(body, "completed_at", "completed session"),
  };
};

const legacyCriterionStatuses: readonly LegacyCriterionStatus[] = [
  "met",
  "omitted",
  "uncertain",
];

const decodeAudio = (value: unknown): Blob => {
  if (!(value instanceof Blob) || value.size === 0) throw new Error("audio");
  return value;
};

const decodeTranscriptionResult = (value: unknown): TranscriptionResult => {
  const body = objectValue(value, "transcription");
  const duration = body.duration_seconds;
  if (
    duration !== undefined &&
    duration !== null &&
    typeof duration !== "number"
  ) {
    invalid("transcription");
  }

  const result: TranscriptionResult = {
    text: stringValue(body, "text", "transcription"),
    transcribed_at: stringValue(body, "transcribed_at", "transcription"),
  };
  if (duration !== undefined) {
    result.duration_seconds = duration as number | null;
  }
  return result;
};

const decodeLegacyCriterion = (value: unknown): LegacyResultCriterion => {
  const body = objectValue(value, "result criterion");
  return {
    id: stringValue(body, "id", "result criterion"),
    status: literalValue(body, "status", legacyCriterionStatuses, "result criterion"),
    evidence: stringList(body, "evidence", "result criterion"),
    recommendation: stringValue(body, "recommendation", "result criterion"),
  };
};

const decodeLegacySessionResult = (value: unknown): LegacySessionResult => {
  const body = objectValue(value, "session result");
  const criteria = Array.isArray(body.criteria)
    ? body.criteria
    : invalid("session result");

  return {
    session_id: stringValue(body, "session_id", "session result"),
    status: literalValue(body, "status", ["completed"], "session result"),
    criteria: criteria.map(decodeLegacyCriterion),
  };
};

const assessmentStatuses: readonly CriterionStatus[] = ["assessed", "uncertain", "not_observable", "not_applicable"];
const decimalValue = (body: JsonObject, key: string): string => {
  const value = stringValue(body, key, "educational result");
  // The shortest exact representation of non-negative integer fortieths (multiples of 0.025).
  return /^(0|[1-9]\d*)(\.\d{0,2}[1-9])?$/.test(value) && thousandths(value) % 25n === 0n ? value : invalid("educational result");
};
const thousandths = (value: string): bigint => {
  const [whole, fraction = ""] = value.split(".");
  return BigInt(whole) * 1000n + BigInt(fraction.padEnd(3, "0"));
};
const fortieths = (value: string): bigint => thousandths(value) / 25n;
const decodeEducationalCriterion = (value: unknown): ResultCriterion => {
  const body = objectValue(value, "educational criterion");
  const status = literalValue(body, "status", assessmentStatuses, "educational criterion");
  const evidence = Array.isArray(body.evidence) ? body.evidence.map((item) => {
    const excerpt = objectValue(item, "evidence");
    return { id: stringValue(excerpt, "id", "evidence"), role: literalValue(excerpt, "role", ["learner", "patient"] as const, "evidence"), text: stringValue(excerpt, "text", "evidence") };
  }) : invalid("evidence");
  const base: CriterionBase = {
    id: stringValue(body, "id", "educational criterion"),
    description: stringValue(body, "description", "educational criterion"),
    max_points: decimalValue(body, "max_points"),
    evidence_ids: stringList(body, "evidence_ids", "educational criterion"),
    evidence,
    recommendation: stringValue(body, "recommendation", "educational criterion"),
  };
  if (base.evidence_ids.length !== evidence.length || evidence.some((item, index) => item.id !== base.evidence_ids[index])) invalid("evidence");
  if (status === "assessed") {
    if (body.reason !== null) invalid("educational criterion");
    const points = decimalValue(body, "points");
    if (fortieths(points) > fortieths(base.max_points)) invalid("educational criterion");
    return { ...base, status, reason: null, level: stringValue(body, "level", "educational criterion"), level_description: stringValue(body, "level_description", "educational criterion"), points };
  }
  // Only an uncertain criterion may report evidence: what the learner asked (issue #291).
  if ("points" in body || "level" in body || "level_description" in body || (status !== "uncertain" && evidence.length > 0)) invalid("educational criterion");
  const reasons = { uncertain: "assessment_unresolved", not_observable: "required_modality_unavailable", not_applicable: "authored_exclusion" };
  if (body.reason !== reasons[status]) invalid("educational criterion");
  return { ...base, status, reason: reasons[status] };
};
const decodeSessionResult = (value: unknown): SessionResult => {
  const body = objectValue(value, "educational result");
  const criteria = Array.isArray(body.criteria) ? body.criteria.map(decodeEducationalCriterion) : invalid("educational result");
  if (new Set(criteria.map((item) => item.id)).size !== criteria.length) invalid("educational result");
  const coverageBody = objectValue(body.coverage, "coverage");
  const coverage = {} as Record<CriterionStatus, number>;
  for (const status of assessmentStatuses) {
    const count = coverageBody[status];
    if (!Number.isSafeInteger(count) || count !== criteria.filter((item) => item.status === status).length) invalid("coverage");
    coverage[status] = count as number;
  }
  const estimatesBody = objectValue(body.estimates, "estimates");
  const unresolved = Array.isArray(estimatesBody.unresolved) ? estimatesBody.unresolved.map((item) => {
    const entry = objectValue(item, "unresolved");
    return { id: stringValue(entry, "id", "unresolved"), status: literalValue(entry, "status", ["uncertain", "not_observable"] as const, "unresolved") };
  }) : invalid("estimates");
  const expectedUnresolved = criteria.filter((item) => item.status === "uncertain" || item.status === "not_observable");
  if (unresolved.length !== expectedUnresolved.length || unresolved.some((item, index) => item.id !== expectedUnresolved[index].id || item.status !== expectedUnresolved[index].status)) invalid("estimates");
  const estimates = {
    total: estimatesBody.total === null ? null : decimalValue(estimatesBody, "total"),
    scored_subtotal: decimalValue(estimatesBody, "scored_subtotal"),
    scored_max: decimalValue(estimatesBody, "scored_max"),
    eligible_max: decimalValue(estimatesBody, "eligible_max"),
    unresolved,
  };
  const assessed = criteria.filter((item) => item.status === "assessed");
  const eligible = criteria.filter((item) => item.status !== "not_applicable");
  const sum = (values: string[]) => values.reduce((total, item) => total + fortieths(item), 0n);
  if (fortieths(estimates.scored_subtotal) !== sum(assessed.map((item) => item.points)) || fortieths(estimates.scored_max) !== sum(assessed.map((item) => item.max_points)) || fortieths(estimates.eligible_max) !== sum(eligible.map((item) => item.max_points))) invalid("estimates");
  const complete = eligible.length > 0 && unresolved.length === 0;
  if (complete ? estimates.total !== estimates.scored_subtotal : estimates.total !== null) invalid("estimates");
  return {
    schema_version: literalValue(body, "schema_version", ["2"], "educational result"),
    session_id: stringValue(body, "session_id", "educational result"),
    status: literalValue(body, "status", ["completed"], "educational result"),
    placeholder: booleanValue(body, "placeholder", "educational result"),
    criteria, coverage, estimates,
  };
};

const impressoDecisions: readonly ImpressoDecision[] = [
  "released",
  "already_released",
  "unavailable",
];

const decodeImpresso = (value: unknown): Impresso => {
  const body = objectValue(value, "impresso");
  return {
    id: stringValue(body, "id", "impresso"),
    title: stringValue(body, "title", "impresso"),
    category: stringValue(body, "category", "impresso"),
    content: stringValue(body, "content", "impresso"),
  };
};

const impressoList = (body: JsonObject, key: string, label: string): Impresso[] => {
  const value = body[key];
  return Array.isArray(value) ? value.map(decodeImpresso) : invalid(label);
};

const decodeRequestImpressoResponse = (
  value: unknown,
): RequestImpressoResponse => {
  const body = objectValue(value, "impresso request");
  return {
    request_id: stringValue(body, "request_id", "impresso request"),
    decision: literalValue(
      body,
      "decision",
      impressoDecisions,
      "impresso request",
    ),
    released_impressos: impressoList(
      body,
      "released_impressos",
      "impresso request",
    ),
    newly_released: impressoList(body, "newly_released", "impresso request"),
    feedback_message: stringValue(
      body,
      "feedback_message",
      "impresso request",
    ),
  };
};

const decodeListImpressosResponse = (value: unknown): ListImpressosResponse => {
  const body = objectValue(value, "impresso list");
  return {
    released_impressos: impressoList(
      body,
      "released_impressos",
      "impresso list",
    ),
  };
};

const decodeApiError = (status: number, value: unknown): ApiError => {
  const body =
    typeof value === "object" && value !== null ? (value as JsonObject) : {};
  const code = typeof body.error === "string" ? body.error : "http_error";
  const message =
    typeof body.message === "string" ? body.message : "A solicitação falhou.";

  return new ApiError(status, code, message, decodeKeptLearnerTurn(body));
};

// A refused patient reply keeps the learner turn (`learner_turn`). Anything
// that is not a well-formed learner turn is ignored, never trusted.
const decodeKeptLearnerTurn = (body: JsonObject): SessionMessage | undefined => {
  const turn = body.learner_turn;
  if (typeof turn !== "object" || turn === null) return undefined;
  const { role, text } = turn as JsonObject;
  return role === "learner" && typeof text === "string"
    ? { role, text }
    : undefined;
};

// The educational result runs the rubric resolver (30 s deadline) and then
// generates learner feedback (45 s deadline) before answering, so its first
// fetch may take over a minute; later fetches are served from the session.
// The backend keeps resolver + feedback within 80 s of this wait (issue #301,
// `backend/config/runtime.exs`). Every other request keeps `timeoutMs`.
const EDUCATIONAL_RESULT_TIMEOUT_MS = 95_000;

export const createApiClient = ({
  baseUrl,
  fetch: fetchImpl = fetch,
  timeoutMs = 15_000,
}: {
  baseUrl: string;
  fetch?: typeof fetch;
  timeoutMs?: number;
}) => {
  const normalizedBaseUrl = baseUrl.replace(/\/$/, "");

  const request = async <T>(
    path: string,
    init: RequestInit,
    decode: (value: unknown) => T,
    readBody: (response: Response) => Promise<unknown> = (response) =>
      response.status === 204 ? Promise.resolve(null) : response.json(),
    requestTimeoutMs: number = timeoutMs,
  ): Promise<T> => {
    const controller = new AbortController();
    let timedOut = false;
    const timeoutError = () =>
      new ApiError(
        0,
        "request_timeout",
        "A solicitação excedeu o tempo limite.",
      );
    const timeout = setTimeout(() => {
      timedOut = true;
      controller.abort();
    }, requestTimeoutMs);

    try {
      let response: Response;

      try {
        response = await fetchImpl(`${normalizedBaseUrl}${path}`, {
          ...init,
          signal: controller.signal,
        });
      } catch {
        if (timedOut) throw timeoutError();

        throw new ApiError(
          0,
          "network_error",
          "Não foi possível conectar ao servidor.",
        );
      }

      let body: unknown;
      try {
        body = await (response.ok ? readBody(response) : response.json());
      } catch {
        if (timedOut) throw timeoutError();

        throw new ApiError(
          response.status,
          "invalid_response",
          "O servidor retornou uma resposta inválida.",
        );
      }

      if (!response.ok) throw decodeApiError(response.status, body);

      try {
        return decode(body);
      } catch {
        throw new ApiError(
          response.status,
          "invalid_response",
          "O servidor retornou uma resposta inválida.",
        );
      }
    } finally {
      clearTimeout(timeout);
    }
  };

  const sessionPath = (sessionId: string) =>
    `/api/stations/active/sessions/${encodeURIComponent(sessionId)}`;
  const jsonPost = (body: unknown): RequestInit => ({
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  return {
    getActiveStation: () =>
      request("/api/stations/active", { method: "GET" }, decodeActiveStation),
    startSession: (body: StartSessionRequest) =>
      request("/api/stations/active/sessions", jsonPost(body), decodeSession),
    getSession: (sessionId: string) =>
      request(sessionPath(sessionId), { method: "GET" }, decodeSessionDetail),
    sendMessage: (sessionId: string, body: SendMessageRequest) =>
      request(
        `${sessionPath(sessionId)}/messages`,
        jsonPost(body),
        decodeMessageReply,
      ),
    finishSession: (sessionId: string, reason: FinishReason = "user") =>
      request(
        `${sessionPath(sessionId)}/finish`,
        jsonPost({ reason }),
        decodeCompletedSession,
      ),
    createVoiceSession: (sessionId: string) =>
      request(
        `${sessionPath(sessionId)}/voice`,
        { method: "POST" },
        decodeVoiceSession,
      ),
    transcribeAudio: (
      sessionId: string,
      audioBlob: Blob,
      filename = "audio.webm",
    ) => {
      const formData = new FormData();
      formData.append("audio", audioBlob, filename);
      return request(
        `${sessionPath(sessionId)}/transcribe`,
        {
          method: "POST",
          body: formData,
        },
        decodeTranscriptionResult,
      );
    },
    synthesizeSpeech: (sessionId: string, text: string, voice?: string) =>
      request(
        `${sessionPath(sessionId)}/synthesize`,
        jsonPost(voice === undefined ? { text } : { text, voice }),
        decodeAudio,
        (response) => response.blob(),
      ),
    fetchResult: (sessionId: string) =>
      request(
        `/api/v2/stations/active/sessions/${encodeURIComponent(sessionId)}/result`,
        { method: "GET" },
        decodeSessionResult,
        undefined,
        EDUCATIONAL_RESULT_TIMEOUT_MS,
      ),
    fetchLegacyResult: (sessionId: string) =>
      request(`${sessionPath(sessionId)}/result`, { method: "GET" }, decodeLegacySessionResult),
    requestImpresso: (sessionId: string, body: RequestImpressoRequest) =>
      request(
        `${sessionPath(sessionId)}/impressos/request`,
        jsonPost(body),
        decodeRequestImpressoResponse,
      ),
    getImpressos: (sessionId: string) =>
      request(
        `${sessionPath(sessionId)}/impressos`,
        { method: "GET" },
        decodeListImpressosResponse,
      ),
    discardSession: (
      sessionId: string,
      options?: DiscardSessionOptions,
    ): Promise<void> => {
      const init: RequestInit = { method: "POST" };
      if (options?.keepalive) {
        init.keepalive = true;
      }
      return request(
        `${sessionPath(sessionId)}/discard`,
        init,
        () => undefined,
        async () => undefined,
      );
    },
  };
};

const defaultClient = createApiClient({
  baseUrl: import.meta.env.VITE_API_URL ?? "",
  fetch: (...args) => fetch(...args),
});

export const {
  getActiveStation,
  startSession,
  getSession,
  sendMessage,
  finishSession,
  transcribeAudio,
  synthesizeSpeech,
  fetchResult,
  createVoiceSession,
  requestImpresso,
  getImpressos,
  discardSession,
} = defaultClient;
