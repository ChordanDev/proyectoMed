/**
 * Events the real-time voice worker publishes on the LiveKit data topic
 * `transcript` (voice-worker/worker.py and transcripts.py, #118, #120, #269, #271,
 * #281).
 * Parsing is strict: anything malformed, or bound to another session, is
 * dropped. Nothing here logs transcript or patient text.
 */
export type VoiceTranscriptEvent =
  /** The learner's speech: an interim caption, or the final turn transcript. */
  | { type: "learner"; turnId: number; final: boolean; text: string }
  /**
   * The verified patient reply, as spoken (stage directions removed). A streamed
   * reply arrives one sentence at a time, each with its `segment` index (#271).
   */
  | { type: "patient"; turnId: number; text: string; segment?: number }
  /** Every sentence of a streamed reply was published; carries no text (#281). */
  | { type: "patient-complete"; turnId: number }
  /** The patient reply was refused; Phoenix kept the learner turn. */
  | { type: "examiner-kept"; turnId: number }
  /** A turn-level failure (e.g. synthesis_failed); the session goes on. */
  | { type: "turn-failure"; turnId: number; failure: string }
  /** The worker stopped transcribing this session. */
  | { type: "fatal"; error: string };

export const VOICE_TRANSCRIPT_TOPIC = "transcript";
export const VOICE_WORKER_IDENTITY = "voice-worker";

const decoder = new TextDecoder();

const isTurnId = (value: unknown): value is number =>
  typeof value === "number" && Number.isInteger(value) && value > 0;

const isSegment = (value: unknown): value is number =>
  typeof value === "number" && Number.isInteger(value) && value >= 0;

const nonBlank = (value: unknown): value is string =>
  typeof value === "string" && value.trim() !== "";

export const parseVoiceTranscriptEvent = (
  payload: Uint8Array,
  sessionId: string,
): VoiceTranscriptEvent | null => {
  let body: unknown;
  try {
    body = JSON.parse(decoder.decode(payload));
  } catch {
    return null;
  }
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return null;
  }
  const event = body as Record<string, unknown>;
  if (event.session_id !== sessionId) return null;

  if (nonBlank(event.error) && event.turn_id === undefined) {
    return { type: "fatal", error: event.error };
  }

  const turnId = event.turn_id;
  if (!isTurnId(turnId)) return null;

  if (nonBlank(event.failure)) {
    return { type: "turn-failure", turnId, failure: event.failure };
  }
  if (event.role === "patient") {
    if (event.status === "complete") return { type: "patient-complete", turnId };
    if (!nonBlank(event.text)) return null;
    if (event.segment === undefined) return { type: "patient", turnId, text: event.text };
    return isSegment(event.segment)
      ? { type: "patient", turnId, text: event.text, segment: event.segment }
      : null;
  }
  if (event.role === "examiner") {
    return event.status === "kept" ? { type: "examiner-kept", turnId } : null;
  }
  if (event.role !== undefined || typeof event.final !== "boolean") return null;
  if (typeof event.text !== "string") return null;
  if (event.final && !nonBlank(event.text)) return null;
  return { type: "learner", turnId, final: event.final, text: event.text };
};
