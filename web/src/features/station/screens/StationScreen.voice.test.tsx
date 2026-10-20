import { act, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { RoomEvent } from "livekit-client";
import { describe, expect, it, vi } from "vitest";
import type { SessionMessage, VoiceSession } from "../api/client";
import type { VoiceRoom, VoiceSessionApi } from "../hooks/useVoiceSession";
import strings from "../i18n/pt-BR.json";
import { StationScreen } from "./StationScreen";

const voiceSession: VoiceSession = {
  url: "wss://livekit.example.test",
  token: "signed-jwt",
  room: "station-session-session-1",
  identity: "learner-session-1",
  expires_at: "2026-01-01T10:02:00Z",
};

class FakeRoom implements VoiceRoom {
  listeners = new Map<string, Set<(...args: unknown[]) => void>>();
  disconnectCalls = 0;
  localParticipant = {
    setMicrophoneEnabled: () => Promise.resolve(undefined),
  };

  on(event: string, listener: (...args: unknown[]) => void): this {
    if (!this.listeners.has(event)) this.listeners.set(event, new Set());
    this.listeners.get(event)!.add(listener);
    return this;
  }

  off(event: string, listener: (...args: unknown[]) => void): this {
    this.listeners.get(event)?.delete(listener);
    return this;
  }

  connect(): Promise<void> {
    return Promise.resolve();
  }

  disconnect(): Promise<void> {
    this.disconnectCalls += 1;
    return Promise.resolve();
  }

  /** Publish one worker event on the transcript topic, as LiveKit delivers it. */
  worker(event: Record<string, unknown>): void {
    const payload = new TextEncoder().encode(
      JSON.stringify({ session_id: "session-1", ...event }),
    );
    this.listeners
      .get(RoomEvent.DataReceived)
      ?.forEach((listener) =>
        listener(payload, { identity: "voice-worker" }, undefined, "transcript"),
      );
  }
}

const transcriptTexts = () =>
  within(screen.getByTestId("message-list"))
    .queryAllByTestId(/^message-/)
    .map((entry) => [entry.dataset.testid, entry.lastChild?.textContent ?? ""]);

const renderRealtime = async ({
  stored = [] as SessionMessage[],
  disabled = false,
  initialMessages = undefined as { role: "learner" | "patient"; text: string }[] | undefined,
} = {}) => {
  const room = new FakeRoom();
  const api: VoiceSessionApi = {
    createVoiceSession: vi.fn().mockResolvedValue(voiceSession),
  };
  const onFetchTranscript = vi.fn().mockResolvedValue(stored);
  const onTranscribe = vi.fn();
  const onSendVoice = vi.fn();
  const onSynthesize = vi.fn();
  const props = {
    onSend: vi.fn().mockResolvedValue("reply"),
    onFinish: vi.fn(),
    onRequestImpresso: vi.fn().mockResolvedValue(null),
    audioConsent: true,
    onTranscribe,
    onSendVoice,
    onSynthesize,
    initialMessages,
    realtimeVoice: { sessionId: "session-1", api, createRoom: () => room },
    onFetchTranscript,
  };
  const view = render(<StationScreen {...props} disabled={disabled} />);
  await userEvent.click(screen.getByTestId("voice-toggle-button"));
  await waitFor(() =>
    expect(screen.getByTestId("voice-status").textContent).toBe(
      strings.voiceStatusConnected,
    ),
  );
  return { room, props, view, onFetchTranscript };
};

describe("StationScreen real-time voice (#270)", () => {
  it("hosts the voice panel and hides the turn-based voice buttons", async () => {
    const { props } = await renderRealtime({
      initialMessages: [
        { role: "learner", text: "Bom dia." },
        { role: "patient", text: "Bom dia, doutor." },
      ],
    });

    const panel = screen.getByTestId("voice-panel");
    expect(screen.getByTestId("station-screen").contains(panel)).toBe(true);
    expect(screen.queryByTestId("voice-button")).toBeNull();
    expect(screen.queryByTestId("play-button")).toBeNull();
    expect(props.onTranscribe).not.toHaveBeenCalled();
  });

  it("shows spoken turns, the stored patient reply and the examiner acknowledgement in order", async () => {
    const { room, onFetchTranscript } = await renderRealtime({
      stored: [
        { role: "learner", text: "Onde dói?" },
        { role: "patient", text: "No peito. (leva a mão ao peito)" },
        { role: "learner", text: "Chame o examinador." },
      ],
    });

    act(() => {
      room.worker({ turn_id: 1, final: false, text: "Onde" });
    });
    expect(screen.getByTestId("voice-caption").textContent).toContain("Onde");
    expect(transcriptTexts()).toEqual([]);

    act(() => {
      room.worker({ turn_id: 1, final: true, text: "Onde dói?" });
    });
    expect(screen.queryByTestId("voice-caption")).toBeNull();

    act(() => {
      room.worker({
        turn_id: 1,
        generation_id: 1,
        role: "patient",
        text: "No peito.",
      });
      room.worker({ turn_id: 2, final: true, text: "Chame o examinador." });
      room.worker({ turn_id: 2, generation_id: 2, role: "examiner", status: "kept" });
    });

    await waitFor(() =>
      expect(transcriptTexts()).toEqual([
        ["message-learner", "Onde dói?"],
        ["message-patient", "No peito. (leva a mão ao peito)"],
        ["message-learner", "Chame o examinador."],
        ["message-examiner", strings.examinerAcknowledgement],
      ]),
    );
    expect(onFetchTranscript).toHaveBeenCalledTimes(1);
  });

  it("does not render a turn twice when the worker repeats an event", async () => {
    const { room, onFetchTranscript } = await renderRealtime({
      stored: [
        { role: "learner", text: "Onde dói?" },
        { role: "patient", text: "No peito." },
      ],
    });

    act(() => {
      room.worker({ turn_id: 1, final: true, text: "Onde dói?" });
      room.worker({ turn_id: 1, final: true, text: "Onde dói?" });
      room.worker({ turn_id: 1, generation_id: 1, role: "patient", text: "No peito." });
      room.worker({ turn_id: 1, generation_id: 1, role: "patient", text: "No peito." });
    });

    await waitFor(() =>
      expect(transcriptTexts()).toEqual([
        ["message-learner", "Onde dói?"],
        ["message-patient", "No peito."],
      ]),
    );
    expect(onFetchTranscript).toHaveBeenCalledTimes(1);
  });

  it("falls back to the spoken reply text when the stored transcript cannot be read", async () => {
    const { room, onFetchTranscript } = await renderRealtime();
    onFetchTranscript.mockRejectedValueOnce(new Error("offline"));

    act(() => {
      room.worker({ turn_id: 1, final: true, text: "Onde dói?" });
      room.worker({ turn_id: 1, generation_id: 1, role: "patient", text: "No peito." });
    });

    await waitFor(() =>
      expect(transcriptTexts()).toEqual([
        ["message-learner", "Onde dói?"],
        ["message-patient", "No peito."],
      ]),
    );
  });

  it("recovers an undelivered reply from the stored transcript", async () => {
    const { room } = await renderRealtime({
      stored: [
        { role: "learner", text: "Onde dói?" },
        { role: "patient", text: "No peito." },
      ],
    });

    act(() => {
      room.worker({ turn_id: 1, final: true, text: "Onde dói?" });
      room.worker({ turn_id: 1, generation_id: 1, failure: "text_delivery_failed" });
    });

    await waitFor(() =>
      expect(transcriptTexts()).toEqual([
        ["message-learner", "Onde dói?"],
        ["message-patient", "No peito."],
      ]),
    );
  });

  it("shows failures as notices, never as transcript entries", async () => {
    const { room } = await renderRealtime();

    act(() => {
      room.worker({ turn_id: 1, generation_id: 1, failure: "synthesis_failed" });
    });
    expect(screen.getByTestId("voice-notice").textContent).toBe(
      strings.voicePatientAudioFailed,
    );

    act(() => {
      room.worker({ error: "auth" });
    });
    expect(screen.getByTestId("voice-notice").textContent).toBe(
      strings.voiceRealtimeStopped,
    );
    expect(transcriptTexts()).toEqual([]);
  });

  describe("sentence-streamed replies (#281)", () => {
    const sentence = (segment: number, text: string, turn_id = 1) => ({
      turn_id,
      generation_id: turn_id,
      role: "patient",
      text,
      segment,
    });
    const complete = (turn_id = 1) => ({
      turn_id,
      generation_id: turn_id,
      role: "patient",
      status: "complete",
    });

    it("grows one patient bubble sentence by sentence, then shows the stored reply", async () => {
      const { room, onFetchTranscript } = await renderRealtime({
        stored: [
          { role: "learner", text: "Desde quando?" },
          {
            role: "patient",
            text: "Começou ontem. (suspira) Ainda dói. Muito.",
          },
        ],
      });

      act(() => {
        room.worker({ turn_id: 1, final: true, text: "Desde quando?" });
        room.worker(sentence(0, "Começou ontem."));
      });
      expect(transcriptTexts()).toEqual([
        ["message-learner", "Desde quando?"],
        ["message-patient", "Começou ontem."],
      ]);

      act(() => {
        room.worker(sentence(1, "Ainda dói."));
        room.worker(sentence(2, "Muito."));
      });
      expect(transcriptTexts()).toEqual([
        ["message-learner", "Desde quando?"],
        ["message-patient", "Começou ontem. Ainda dói. Muito."],
      ]);
      expect(onFetchTranscript).not.toHaveBeenCalled();

      act(() => {
        room.worker(complete());
      });
      await waitFor(() =>
        expect(transcriptTexts()).toEqual([
          ["message-learner", "Desde quando?"],
          ["message-patient", "Começou ontem. (suspira) Ainda dói. Muito."],
        ]),
      );
      expect(onFetchTranscript).toHaveBeenCalledTimes(1);
    });

    it("orders out-of-order sentences and renders a repeated one once", async () => {
      const { room, onFetchTranscript } = await renderRealtime({
        stored: [{ role: "learner", text: "Chame o examinador." }],
      });
      onFetchTranscript.mockRejectedValueOnce(new Error("offline"));

      act(() => {
        room.worker({ turn_id: 1, final: true, text: "Desde quando?" });
        room.worker(sentence(1, "Ainda dói."));
        room.worker(sentence(0, "Começou ontem."));
        room.worker(sentence(0, "Começou ontem."));
        room.worker(sentence(2, "Muito."));
        room.worker(sentence(1, "Ainda dói."));
      });
      expect(transcriptTexts()).toEqual([
        ["message-learner", "Desde quando?"],
        ["message-patient", "Começou ontem. Ainda dói. Muito."],
      ]);

      act(() => {
        room.worker(complete());
        room.worker(complete());
      });
      // The stored transcript cannot be read: the spoken sentences stay.
      await waitFor(() => expect(onFetchTranscript).toHaveBeenCalledTimes(1));

      act(() => {
        room.worker(sentence(3, "Late."));
        room.worker({ turn_id: 2, final: true, text: "Chame o examinador." });
        room.worker({ turn_id: 2, generation_id: 2, role: "examiner", status: "kept" });
      });
      await waitFor(() =>
        expect(transcriptTexts()).toEqual([
          ["message-learner", "Desde quando?"],
          ["message-patient", "Começou ontem. Ainda dói. Muito."],
          ["message-learner", "Chame o examinador."],
          ["message-examiner", strings.examinerAcknowledgement],
        ]),
      );
      expect(onFetchTranscript).toHaveBeenCalledTimes(1);
    });

    it("waits for the end of a streamed reply when one of its sentences was not delivered", async () => {
      const { room, onFetchTranscript } = await renderRealtime({
        stored: [
          { role: "learner", text: "Desde quando?" },
          { role: "patient", text: "Começou ontem. Ainda dói." },
        ],
      });

      act(() => {
        room.worker({ turn_id: 1, final: true, text: "Desde quando?" });
        room.worker(sentence(0, "Começou ontem."));
        room.worker({ turn_id: 1, generation_id: 1, failure: "text_delivery_failed" });
      });
      expect(onFetchTranscript).not.toHaveBeenCalled();

      act(() => {
        room.worker(complete());
      });
      await waitFor(() =>
        expect(transcriptTexts()).toEqual([
          ["message-learner", "Desde quando?"],
          ["message-patient", "Começou ontem. Ainda dói."],
        ]),
      );
    });

    it("keeps the learner line of a reply that could not be delivered", async () => {
      const { room } = await renderRealtime({
        stored: [
          { role: "learner", text: "Irradia?" },
          { role: "patient", text: "Não." },
        ],
      });

      act(() => {
        room.worker({ turn_id: 1, final: true, text: "Onde dói?" });
        room.worker({ turn_id: 1, generation_id: 1, failure: "text_delivery_failed" });
      });
      await waitFor(() =>
        expect(screen.getByTestId("voice-notice").textContent).toBe(
          strings.voiceTextDeliveryFailed,
        ),
      );

      act(() => {
        room.worker({ turn_id: 2, final: true, text: "Irradia?" });
        room.worker({ turn_id: 2, generation_id: 2, role: "patient", text: "Não." });
      });
      await waitFor(() =>
        expect(transcriptTexts()).toEqual([
          ["message-learner", "Onde dói?"],
          ["message-learner", "Irradia?"],
          ["message-patient", "Não."],
        ]),
      );
    });
  });

  it("ends the voice session at the deadline and on unmount", async () => {
    const { room, props, view } = await renderRealtime();

    view.rerender(<StationScreen {...props} disabled />);
    expect(room.disconnectCalls).toBe(1);
    expect(screen.getByTestId("voice-toggle-button")).toBeDisabled();

    view.unmount();
    expect(room.listeners.get(RoomEvent.DataReceived)?.size ?? 0).toBe(0);
  });
});
