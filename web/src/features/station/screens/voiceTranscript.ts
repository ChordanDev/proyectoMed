import type { SessionMessage } from "../api/client";
import type { DisplayMessage } from "./StationScreen";

/**
 * Merges real-time voice turns (#270) into the station transcript. Voice entries
 * carry their worker turn id, so a repeated event never renders twice and an
 * outcome lands right after its own learner turn whatever arrived in between.
 */

type VoiceOutcome = Pick<DisplayMessage, "role" | "text"> & {
  role: "patient" | "examiner";
};

const hasOutcome = (messages: DisplayMessage[], turnId: number): boolean =>
  messages.some(
    (message) => message.voiceTurnId === turnId && message.role !== "learner",
  );

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
 * Adds the outcome of voice turn `turnId`. An earlier learner voice turn still
 * without an outcome was superseded (barge-in): the worker cancelled it and
 * Phoenix did not keep it, so it leaves the transcript. `pendingTurns` are
 * turns whose outcome is on its way (e.g. the stored reply is being read).
 */
export const resolveVoiceTurn = (
  messages: DisplayMessage[],
  turnId: number,
  outcome: VoiceOutcome,
  pendingTurns: ReadonlySet<number> = new Set(),
): DisplayMessage[] => {
  if (hasOutcome(messages, turnId)) return messages;

  const kept = messages.filter(
    (message) =>
      message.voiceTurnId === undefined ||
      message.voiceTurnId >= turnId ||
      message.role !== "learner" ||
      pendingTurns.has(message.voiceTurnId) ||
      hasOutcome(messages, message.voiceTurnId),
  );
  const entry: DisplayMessage = { ...outcome, voiceTurnId: turnId };
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
