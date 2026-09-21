export interface ActiveStation {
  station_id: string;
  version: string;
  display_title: string;
  language: string;
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
  server_now: string;
}

export interface SendMessageRequest {
  role: "learner";
  modality: "voice" | "text";
  text: string;
}

export interface MessageReply {
  reply_text: string;
  reply_audio_url?: string | null;
  server_now: string;
}

export type FinishReason = "user" | "timer";

export interface CompletedSession {
  session_id: string;
  status: "completed";
  completed_at: string;
}

export type CriterionStatus = "met" | "omitted" | "uncertain";

export interface ResultCriterion {
  id: string;
  status: CriterionStatus;
  evidence: string[];
  recommendation: string;
}

export interface TranscriptionResult {
  text: string;
  duration_seconds?: number | null;
  transcribed_at: string;
}

export interface SessionResult {
  session_id: string;
  status: "completed";
  criteria: ResultCriterion[];
}

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
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

const decodeActiveStation = (value: unknown): ActiveStation => {
  const body = objectValue(value, "active station");
  return {
    station_id: stringValue(body, "station_id", "active station"),
    version: stringValue(body, "version", "active station"),
    display_title: stringValue(body, "display_title", "active station"),
    language: stringValue(body, "language", "active station"),
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
    server_now: stringValue(body, "server_now", "session"),
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

  return {
    reply_text: stringValue(body, "reply_text", "message"),
    server_now: stringValue(body, "server_now", "message"),
    ...(hasAudioUrl ? { reply_audio_url: audioUrl as string | null } : {}),
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

const criterionStatuses: readonly CriterionStatus[] = [
  "met",
  "omitted",
  "uncertain",
];

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

const decodeCriterion = (value: unknown): ResultCriterion => {
  const body = objectValue(value, "result criterion");
  return {
    id: stringValue(body, "id", "result criterion"),
    status: literalValue(body, "status", criterionStatuses, "result criterion"),
    evidence: stringList(body, "evidence", "result criterion"),
    recommendation: stringValue(body, "recommendation", "result criterion"),
  };
};

const decodeSessionResult = (value: unknown): SessionResult => {
  const body = objectValue(value, "session result");
  const criteria = Array.isArray(body.criteria)
    ? body.criteria
    : invalid("session result");

  return {
    session_id: stringValue(body, "session_id", "session result"),
    status: literalValue(body, "status", ["completed"], "session result"),
    criteria: criteria.map(decodeCriterion),
  };
};

const decodeApiError = (status: number, value: unknown): ApiError => {
  const body =
    typeof value === "object" && value !== null ? (value as JsonObject) : {};
  const code = typeof body.error === "string" ? body.error : "http_error";
  const message =
    typeof body.message === "string" ? body.message : "A solicitação falhou.";

  return new ApiError(status, code, message);
};

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
    }, timeoutMs);

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
        body = await response.json();
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
    fetchResult: (sessionId: string) =>
      request(
        `${sessionPath(sessionId)}/result`,
        { method: "GET" },
        decodeSessionResult,
      ),
  };
};

const defaultClient = createApiClient({
  baseUrl: import.meta.env.VITE_API_URL ?? "",
  fetch: (...args) => fetch(...args),
});

export const {
  getActiveStation,
  startSession,
  sendMessage,
  finishSession,
  transcribeAudio,
  fetchResult,
} = defaultClient;
