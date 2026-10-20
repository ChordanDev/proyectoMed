import type { SessionMessage } from "../api/client";
import type { DisplayMessage } from "./StationScreen";

/**
 * Merges real-time voice turns (#270) into the station transcript. Voice entries
 * carry their worker turn id, so a repeated event never renders twice and an
 * outcome lands right after its own learner turn whatever arrived in between.
 * A streamed reply (#281) shows as one partial patient entry that grows with
 * each sentence until the turn is resolved.
 */

type VoiceOutcome = Pick<DisplayMessage, "role" | "text"> & {
  role: "patient" | "examiner";
};

const isOutcome = (message: DisplayMessage, turnId: number): boolean =>
  message.voiceTurnId === turnId && message.role !== "learner";

const hasOutcome = (messages: DisplayMessage[], turnId: number): boolean =>
  messages.some((message) => isOutcome(message, turnId));

export const addVoiceLearnerTurn = (
  messages: DisplayMessage[],
  turnId: number,
  text: string,
): DisplayMessage[] =>
  messages.some(
    (message) => message.voiceTurnId === turnId && message.role === "learner",
  )
    ? messages
    : [...messages, { role: "learner", text, voiceTurnId: turnId }];

/**
 * Places `entry` as the outcome of voice turn `turnId`: in place of a partial
 * outcome, or right after its learner turn. An earlier learner voice turn still
 * without an outcome was superseded (barge-in): the worker cancelled it and
 * Phoenix did not keep it, so it leaves the transcript. `keptTurns` are turns
 * whose learner line stays anyway (e.g. the stored reply is being read).
 */
const placeOutcome = (
  messages: DisplayMessage[],
  turnId: number,
  entry: DisplayMessage,
  keptTurns: ReadonlySet<number>,
): DisplayMessage[] => {
  const partialIndex = messages.findIndex((message) => isOutcome(message, turnId));
  if (partialIndex !== -1) {
    return messages.map((message, index) => (index === partialIndex ? entry : message));
  }
  const kept = messages.filter(
    (message) =>
      message.voiceTurnId === undefined ||
      message.voiceTurnId >= turnId ||
      message.role !== "learner" ||
      keptTurns.has(message.voiceTurnId) ||
      hasOutcome(messages, message.voiceTurnId),
  );
  const learnerIndex = kept.findIndex(
    (message) => message.voiceTurnId === turnId && message.role === "learner",
  );
  if (learnerIndex === -1) return [...kept, entry];
  return [
    ...kept.slice(0, learnerIndex + 1),
    entry,
    ...kept.slice(learnerIndex + 1),
  ];
};

const hasFinalOutcome = (messages: DisplayMessage[], turnId: number): boolean =>
  messages.some((message) => isOutcome(message, turnId) && !message.voicePartial);

/** Adds the outcome of voice turn `turnId`, replacing its partial reply if any. */
export const resolveVoiceTurn = (
  messages: DisplayMessage[],
  turnId: number,
  outcome: VoiceOutcome,
  keptTurns: ReadonlySet<number> = new Set(),
): DisplayMessage[] =>
  hasFinalOutcome(messages, turnId)
    ? messages
    : placeOutcome(messages, turnId, { ...outcome, voiceTurnId: turnId }, keptTurns);

/**
 * Shows the sentences of a streamed reply received so far (#281) as one partial
 * patient entry. A resolved turn is left as it is.
 */
export const showVoiceReplySoFar = (
  messages: DisplayMessage[],
  turnId: number,
  text: string,
  keptTurns: ReadonlySet<number> = new Set(),
): DisplayMessage[] => {
  if (hasFinalOutcome(messages, turnId)) return messages;
  if (
    messages.some((message) => isOutcome(message, turnId) && message.text === text)
  ) {
    return messages;
  }
  return placeOutcome(
    messages,
    turnId,
    { role: "patient", text, voiceTurnId: turnId, voicePartial: true },
    keptTurns,
  );
};

/**
 * Drops the partial replies of voice turns older than `turnId`, with their
 * learner lines (#281). A newer turn means the worker superseded them (barge-in):
 * their end event never comes, and Phoenix did not keep them. `keptTurns` are
 * turns still being resolved or kept for another reason; they stay.
 */
export const dropSupersededVoiceTurns = (
  messages: DisplayMessage[],
  turnId: number,
  keptTurns: ReadonlySet<number> = new Set(),
): DisplayMessage[] => {
  const superseded = new Set(
    messages
      .filter(
        (message) =>
          message.voicePartial === true &&
          message.voiceTurnId !== undefined &&
          message.voiceTurnId < turnId &&
          !keptTurns.has(message.voiceTurnId),
      )
      .map((message) => message.voiceTurnId),
  );
  if (superseded.size === 0) return messages;
  return messages.filter((message) => !superseded.has(message.voiceTurnId));
};

/** The sentences of a streamed reply, in `segment` order. */
export const joinVoiceSegments = (segments: ReadonlyMap<number, string>): string =>
  [...segments.entries()]
    .sort(([left], [right]) => left - right)
    .map(([, text]) => text.trim())
    .join(" ");

/**
 * The stored patient reply (the full verified text, as the text path shows it)
 * that follows the latest stored learner turn with this text, or null.
 */
export const storedReplyFor = (
  stored: SessionMessage[],
  learnerText: string | undefined,
): string | null => {
  const wanted = learnerText?.trim();
  if (!wanted) return null;
  for (let index = stored.length - 1; index >= 0; index -= 1) {
    const message = stored[index];
    if (message.role === "learner" && message.text.trim() === wanted) {
      const next = stored[index + 1];
      return next?.role === "patient" ? next.text : null;
    }
  }
  return null;
};
