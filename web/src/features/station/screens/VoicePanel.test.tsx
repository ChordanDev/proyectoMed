import { act, fireEvent, render } from "@testing-library/react";
import { ApiError, type VoiceSession } from "../api/client";
import type { VoiceRoom, VoiceSessionApi } from "../hooks/useVoiceSession";
import strings from "../i18n/pt-BR.json";
import { VoicePanel } from "./VoicePanel";

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
}

describe("VoicePanel", () => {
  it("renders the idle status and an enabled connect button", async () => {
    const api: VoiceSessionApi = {
      createVoiceSession: vi.fn().mockResolvedValue(voiceSession),
    };
    const { getByTestId, getByText } = await render(
      <VoicePanel
        api={api}
        sessionId="session-1"
        active={true}
        createRoom={() => new FakeRoom()}
      />,
    );

    expect(getByText(strings.voiceStatusIdle)).toBeTruthy();
    const button = getByTestId("voice-toggle-button");
    expect(button.textContent).toBe(strings.voiceConnectButton);
    expect(button).not.toBeDisabled();
  });

  it("connects, shows the mic indicator, then disconnects on click", async () => {
    const room = new FakeRoom();
    const api: VoiceSessionApi = {
      createVoiceSession: vi.fn().mockResolvedValue(voiceSession),
    };
    const { getByTestId, getByText, queryByTestId } = await render(
      <VoicePanel
        api={api}
        sessionId="session-1"
        active={true}
        createRoom={() => room}
      />,
    );

    await act(async () => {
      fireEvent.click(getByTestId("voice-toggle-button"));
    });

    expect(getByText(strings.voiceStatusConnected)).toBeTruthy();
    expect(getByTestId("voice-mic-indicator")).toBeTruthy();
    const button = getByTestId("voice-toggle-button");
    expect(button.textContent).toBe(strings.voiceDisconnectButton);

    await act(async () => {
      fireEvent.click(button);
    });

    expect(room.disconnectCalls).toBe(1);
    expect(getByText(strings.voiceStatusDisconnected)).toBeTruthy();
    expect(queryByTestId("voice-mic-indicator")).toBeNull();
  });

  it("disables the button while requesting or connecting", async () => {
    let resolveCreate!: (value: VoiceSession) => void;
    const api: VoiceSessionApi = {
      createVoiceSession: vi.fn(
        () =>
          new Promise<VoiceSession>((resolve) => {
            resolveCreate = resolve;
          }),
      ),
    };
    const { getByTestId } = await render(
      <VoicePanel
        api={api}
        sessionId="session-1"
        active={true}
        createRoom={() => new FakeRoom()}
      />,
    );

    act(() => {
      fireEvent.click(getByTestId("voice-toggle-button"));
    });

    expect(getByTestId("voice-toggle-button")).toBeDisabled();

    await act(async () => {
      resolveCreate(voiceSession);
    });
  });

  it("shows the API error message for a failed connection", async () => {
    const api: VoiceSessionApi = {
      createVoiceSession: vi
        .fn()
        .mockRejectedValue(
          new ApiError(429, "rate_limited", "Muitas tentativas."),
        ),
    };
    const { getByTestId, getByText } = await render(
      <VoicePanel
        api={api}
        sessionId="session-1"
        active={true}
        createRoom={() => new FakeRoom()}
      />,
    );

    await act(async () => {
      fireEvent.click(getByTestId("voice-toggle-button"));
    });

    expect(getByText("Muitas tentativas.")).toBeTruthy();
    expect(getByText(strings.voiceStatusFailed)).toBeTruthy();
    const button = getByTestId("voice-toggle-button");
    expect(button.textContent).toBe(strings.voiceConnectButton);
    expect(button).not.toBeDisabled();
  });
});
