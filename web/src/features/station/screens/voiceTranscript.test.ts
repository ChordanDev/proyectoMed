import { describe, expect, it } from "vitest";
import type { DisplayMessage } from "./StationScreen";
import {
  addVoiceLearnerTurn,
  joinVoiceSegments,
  resolveVoiceTurn,
  showVoiceReplySoFar,
  storedReplyFor,
} from "./voiceTranscript";

const textTurn: DisplayMessage[] = [
  { role: "learner", text: "Bom dia." },
  { role: "patient", text: "Bom dia, doutor." },
];

describe("voice transcript merge (#270)", () => {
  it("appends a final learner turn once, keyed by its turn id", () => {
    const once = addVoiceLearnerTurn(textTurn, 1, "Onde dói?");
    expect(once).toEqual([
      ...textTurn,
      { role: "learner", text: "Onde dói?", voiceTurnId: 1 },
    ]);
    expect(addVoiceLearnerTurn(once, 1, "Onde dói?")).toBe(once);
  });

  it("places the outcome right after its learner turn", () => {
    let messages = addVoiceLearnerTurn([], 1, "Onde dói?");
    messages = [...messages, { role: "examiner", text: "Entrega: ECG" }];
    messages = resolveVoiceTurn(messages, 1, { role: "patient", text: "No peito." });

    expect(messages).toEqual([
      { role: "learner", text: "Onde dói?", voiceTurnId: 1 },
      { role: "patient", text: "No peito.", voiceTurnId: 1 },
      { role: "examiner", text: "Entrega: ECG" },
    ]);
  });

  it("ignores a duplicate outcome for the same turn", () => {
    const messages = resolveVoiceTurn(
      addVoiceLearnerTurn([], 2, "Pode chamar o examinador?"),
      2,
      { role: "examiner", text: "Anotado." },
    );
    expect(
      resolveVoiceTurn(messages, 2, { role: "examiner", text: "Anotado." }),
    ).toBe(messages);
  });

  it("appends an outcome whose learner turn never arrived", () => {
    expect(resolveVoiceTurn(textTurn, 5, { role: "patient", text: "Sim." })).toEqual([
      ...textTurn,
      { role: "patient", text: "Sim.", voiceTurnId: 5 },
    ]);
  });

  it("drops an earlier learner turn left without an outcome (barge-in)", () => {
    let messages = addVoiceLearnerTurn(textTurn, 1, "Desde quando");
    messages = addVoiceLearnerTurn(messages, 2, "Desde quando a dor começou?");
    messages = resolveVoiceTurn(messages, 2, { role: "patient", text: "Há duas horas." });

    expect(messages).toEqual([
      ...textTurn,
      { role: "learner", text: "Desde quando a dor começou?", voiceTurnId: 2 },
      { role: "patient", text: "Há duas horas.", voiceTurnId: 2 },
    ]);
  });

  it("keeps an earlier learner turn whose outcome is still pending", () => {
    let messages = addVoiceLearnerTurn([], 1, "Onde dói?");
    messages = addVoiceLearnerTurn(messages, 2, "Chame o examinador.");
    messages = resolveVoiceTurn(
      messages,
      2,
      { role: "examiner", text: "Anotado." },
      new Set([1]),
    );
    messages = resolveVoiceTurn(messages, 1, { role: "patient", text: "No peito." });

    expect(messages.map((message) => message.text)).toEqual([
      "Onde dói?",
      "No peito.",
      "Chame o examinador.",
      "Anotado.",
    ]);
  });

  it("keeps earlier answered voice turns and text turns", () => {
    let messages = addVoiceLearnerTurn(textTurn, 1, "Onde dói?");
    messages = resolveVoiceTurn(messages, 1, { role: "patient", text: "No peito." });
    messages = addVoiceLearnerTurn(messages, 2, "Irradia?");
    messages = resolveVoiceTurn(messages, 2, { role: "patient", text: "Não." });

    expect(messages.map((message) => message.text)).toEqual([
      "Bom dia.",
      "Bom dia, doutor.",
      "Onde dói?",
      "No peito.",
      "Irradia?",
      "Não.",
    ]);
  });
});

describe("streamed voice replies (#281)", () => {
  it("joins the sentences received so far in segment order", () => {
    expect(
      joinVoiceSegments(
        new Map([
          [2, "Muito."],
          [0, "Começou ontem."],
          [1, " Ainda dói. "],
        ]),
      ),
    ).toBe("Começou ontem. Ainda dói. Muito.");
    expect(joinVoiceSegments(new Map())).toBe("");
  });

  it("grows one partial reply right after its learner turn", () => {
    let messages = addVoiceLearnerTurn([], 1, "Desde quando?");
    messages = [...messages, { role: "examiner", text: "Entrega: ECG" }];
    messages = showVoiceReplySoFar(messages, 1, "Começou ontem.");
    messages = showVoiceReplySoFar(messages, 1, "Começou ontem. Ainda dói.");

    expect(messages).toEqual([
      { role: "learner", text: "Desde quando?", voiceTurnId: 1 },
      {
        role: "patient",
        text: "Começou ontem. Ainda dói.",
        voiceTurnId: 1,
        voicePartial: true,
      },
      { role: "examiner", text: "Entrega: ECG" },
    ]);
    expect(showVoiceReplySoFar(messages, 1, "Começou ontem. Ainda dói.")).toBe(
      messages,
    );
  });

  it("replaces the partial reply with the resolved one, which then stays", () => {
    let messages = addVoiceLearnerTurn([], 1, "Desde quando?");
    messages = showVoiceReplySoFar(messages, 1, "Começou ontem.");
    messages = resolveVoiceTurn(messages, 1, {
      role: "patient",
      text: "Começou ontem. (suspira) Ainda dói.",
    });

    expect(messages).toEqual([
      { role: "learner", text: "Desde quando?", voiceTurnId: 1 },
      {
        role: "patient",
        text: "Começou ontem. (suspira) Ainda dói.",
        voiceTurnId: 1,
      },
    ]);
    expect(showVoiceReplySoFar(messages, 1, "Começou ontem.")).toBe(messages);
  });

  it("keeps a learner turn whose reply is still streaming", () => {
    let messages = addVoiceLearnerTurn([], 1, "Onde dói?");
    messages = showVoiceReplySoFar(messages, 1, "No peito.");
    messages = addVoiceLearnerTurn(messages, 2, "Irradia?");
    messages = resolveVoiceTurn(messages, 2, { role: "patient", text: "Não." });

    expect(messages.map((message) => message.text)).toEqual([
      "Onde dói?",
      "No peito.",
      "Irradia?",
      "Não.",
    ]);
  });
});

describe("storedReplyFor", () => {
  it("returns the stored reply that follows the latest matching learner turn", () => {
    expect(
      storedReplyFor(
        [
          { role: "learner", text: "Onde dói?" },
          { role: "patient", text: "Aqui. (aponta o peito)" },
          { role: "learner", text: "Onde dói?" },
          { role: "patient", text: "No peito. (leva a mão ao peito)" },
        ],
        " Onde dói? ",
      ),
    ).toBe("No peito. (leva a mão ao peito)");
  });

  it("returns null when the learner turn is unknown, absent or unanswered", () => {
    const stored = [{ role: "learner" as const, text: "Onde dói?" }];
    expect(storedReplyFor(stored, undefined)).toBeNull();
    expect(storedReplyFor(stored, "Irradia?")).toBeNull();
    expect(storedReplyFor(stored, "Onde dói?")).toBeNull();
  });
});
