import { act, fireEvent, render } from "@testing-library/react";
import strings from "../i18n/pt-BR.json";
import { StationSession } from "./StationSession";

const { session, voiceSession } = vi.hoisted(() => ({
  session: {
    session_id: "session-1",
    station_id: "station-1",
    station_version: "1.0.0",
    audio_consent: true,
    started_at: "2026-01-01T10:00:00Z",
    expires_at: "2026-01-01T10:30:00Z",
    server_now: "2026-01-01T10:00:00Z",
  },
  voiceSession: {
    url: "wss://livekit.example.test",
    token: "signed-jwt",
    room: "station-session-session-1",
    identity: "learner-session-1",
    expires_at: "2026-01-01T10:02:00Z",
  },
}));

vi.mock("../api/client", async () => {
  const actual =
    await vi.importActual<typeof import("../api/client")>("../api/client");
  return {
    ...actual,
    startSession: vi.fn().mockResolvedValue(session),
    createVoiceSession: vi.fn().mockResolvedValue(voiceSession),
    finishSession: vi.fn().mockResolvedValue({ status: "completed" }),
    fetchResult: vi.fn().mockResolvedValue({}),
  };
});

describe("StationSession", () => {
  it("shows the notice screen before a session starts", async () => {
    const { getByText } = await render(<StationSession />);
    expect(getByText(strings.noticeTitle)).toBeTruthy();
  });

  it("renders the voice panel once an audio-consented session is active", async () => {
    const { getByTestId, getByText } = await render(<StationSession />);

    await act(async () => {
      fireEvent.click(getByTestId("consent-checkbox"));
    });
    await act(async () => {
      fireEvent.click(getByTestId("notice-button"));
    });

    expect(getByTestId("voice-panel")).toBeTruthy();
    expect(getByText(strings.voiceStatusIdle)).toBeTruthy();
  });

  it("finishes the station from the session screen", async () => {
    const client = await import("../api/client");
    const { getByTestId } = await render(<StationSession />);

    await act(async () => {
      fireEvent.click(getByTestId("consent-checkbox"));
    });
    await act(async () => {
      fireEvent.click(getByTestId("notice-button"));
    });
    await act(async () => {
      fireEvent.click(getByTestId("finish-button"));
    });

    expect(client.finishSession).toHaveBeenCalledWith("session-1", "user");
    expect(getByTestId("finish-button")).toBeDisabled();
  });
});
