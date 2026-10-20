import { describe, expect, it } from "vitest";
import { parseVoiceTranscriptEvent } from "./voiceTranscriptEvents";

const encode = (value: unknown) =>
  new TextEncoder().encode(
    typeof value === "string" ? value : JSON.stringify(value),
  );

const parse = (value: unknown, sessionId = "session-1") =>
  parseVoiceTranscriptEvent(encode(value), sessionId);

describe("parseVoiceTranscriptEvent", () => {
  it("reads an interim and a final learner transcript", () => {
    expect(
      parse({ session_id: "session-1", turn_id: 3, final: false, text: "Onde" }),
    ).toEqual({ type: "learner", turnId: 3, final: false, text: "Onde" });
    expect(
      parse({ session_id: "session-1", turn_id: 3, final: true, text: "Onde dói?" }),
    ).toEqual({ type: "learner", turnId: 3, final: true, text: "Onde dói?" });
  });

  it("reads a verified patient reply", () => {
    expect(
      parse({
        session_id: "session-1",
        turn_id: 3,
        generation_id: 7,
        role: "patient",
        text: "No peito.",
      }),
    ).toEqual({ type: "patient", turnId: 3, text: "No peito." });
  });

  it("reads a kept turn as an examiner acknowledgement", () => {
    expect(
      parse({
        session_id: "session-1",
        turn_id: 4,
        generation_id: 8,
        role: "examiner",
        status: "kept",
      }),
    ).toEqual({ type: "examiner-kept", turnId: 4 });
  });

  it("reads a turn failure and a fatal worker error", () => {
    expect(
      parse({
        session_id: "session-1",
        turn_id: 4,
        generation_id: 8,
        failure: "synthesis_failed",
      }),
    ).toEqual({ type: "turn-failure", turnId: 4, failure: "synthesis_failed" });
    expect(parse({ session_id: "session-1", error: "auth" })).toEqual({
      type: "fatal",
      error: "auth",
    });
  });

  it.each([
    ["another session", { session_id: "other", turn_id: 1, final: true, text: "Oi" }],
    ["no session", { turn_id: 1, final: true, text: "Oi" }],
    ["a missing turn id", { session_id: "session-1", final: true, text: "Oi" }],
    ["a non-positive turn id", { session_id: "session-1", turn_id: 0, final: true, text: "Oi" }],
    ["a fractional turn id", { session_id: "session-1", turn_id: 1.5, final: true, text: "Oi" }],
    ["a non-string text", { session_id: "session-1", turn_id: 1, final: true, text: 3 }],
    ["an empty final", { session_id: "session-1", turn_id: 1, final: true, text: "  " }],
    ["an empty patient reply", { session_id: "session-1", turn_id: 1, role: "patient", text: "" }],
    ["an unknown examiner status", { session_id: "session-1", turn_id: 1, role: "examiner", status: "x" }],
    ["an unknown role", { session_id: "session-1", turn_id: 1, role: "nurse", text: "Oi" }],
    ["invalid JSON", "{not json"],
    ["a JSON array", []],
  ])("ignores %s", (_label, value) => {
    expect(parse(value)).toBeNull();
  });
});
