import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import App from "./App";
import strings from "./features/station/i18n/pt-BR.json";
import type { SessionResult } from "./features/station/api/client";
import { partialResult } from "./features/station/result/educational-result.fixture";

const mockStart = vi.fn();
const mockSend = vi.fn();
const mockFinish = vi.fn();
const mockReset = vi.fn();
const mockTranscribe = vi.fn();
const mockSynthesize = vi.fn();

let mockStationState = {
  status: "idle",
  result: null as SessionResult | null,
  error: null as string | null,
  audioConsent: false,
  remainingMs: null as number | null,
  initialMessages: [] as { role: "learner" | "patient"; text: string }[],
  start: mockStart,
  send: mockSend,
  transcribe: mockTranscribe,
  synthesize: mockSynthesize,
  finish: mockFinish,
  reset: mockReset,
};

const activeStation = {
  station_id: "acute-appendicitis",
  version: "2.0.0",
  display_title: "Abdome agudo inflamatório — apendicite aguda",
  language: "pt-BR",
  candidate_brief: {
    scenario: "Você é o médico de plantão em um pronto-socorro.",
    tasks: ["Obter anamnese dirigida.", "Indicar a conduta inicial."],
  },
};

let mockActiveStationState = {
  station: activeStation as typeof activeStation | null,
  error: null as string | null,
};

afterEach(() => {
  vi.unstubAllGlobals();
});

vi.mock("./features/station", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./features/station")>();
  return {
    ...actual,
    useStation: () => mockStationState,
    useActiveStation: () => mockActiveStationState,
  };
});

describe("App", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockActiveStationState = { station: activeStation, error: null };
    mockStationState = {
      status: "idle",
      result: null,
      error: null,
      audioConsent: false,
      remainingMs: null,
      initialMessages: [],
      start: mockStart,
      send: mockSend,
      transcribe: mockTranscribe,
      synthesize: mockSynthesize,
      finish: mockFinish,
      reset: mockReset,
    };
  });

  it("renders NoticeScreen when station status is idle", async () => {
    const user = userEvent.setup();
    render(<App />);

    expect(screen.getByText(strings.noticeTitle)).toBeInTheDocument();

    const startButton = screen.getByRole("button", {
      name: strings.noticeButton,
    });
    expect(startButton).toBeDisabled();

    await user.click(screen.getByRole("checkbox"));
    await user.click(startButton);

    // The brief comes between the notice and the timer start (#239).
    expect(mockStart).not.toHaveBeenCalled();
    expect(
      screen.getByRole("heading", { level: 1, name: activeStation.display_title }),
    ).toBeInTheDocument();
    expect(screen.getByText(activeStation.candidate_brief.scenario)).toBeInTheDocument();
    for (const task of activeStation.candidate_brief.tasks) {
      expect(screen.getByText(task)).toBeInTheDocument();
    }

    await user.click(screen.getByRole("button", { name: strings.briefEnterButton }));

    expect(mockStart).toHaveBeenCalledWith(true);
  });

  it("lets the learner start from the brief when the brief failed to load", async () => {
    const user = userEvent.setup();
    mockActiveStationState = { station: null, error: strings.briefUnavailable };
    render(<App />);

    await user.click(screen.getByRole("checkbox"));
    await user.click(screen.getByRole("button", { name: strings.noticeButton }));

    expect(screen.getByRole("alert")).toHaveTextContent(strings.briefUnavailable);
    await user.click(screen.getByRole("button", { name: strings.briefEnterButton }));
    expect(mockStart).toHaveBeenCalledWith(true);
  });

  it("shows the station title and keeps the brief reachable during the station", async () => {
    const user = userEvent.setup();
    mockStationState.status = "active";
    mockStationState.remainingMs = 9 * 60 * 1000;
    render(<App />);

    expect(
      screen.getByRole("heading", { level: 1, name: activeStation.display_title }),
    ).toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: strings.briefOpenButton }));

    expect(
      screen.getByRole("dialog", { name: strings.briefDialogTitle }),
    ).toHaveTextContent(activeStation.candidate_brief.scenario);
    expect(screen.getByRole("timer")).toHaveTextContent("09:00");
  });

  it("renders loading message when station status is loading", () => {
    mockStationState.status = "loading";
    render(<App />);

    expect(screen.getByRole("status")).toHaveTextContent(strings.loadingStation);
  });

  it("renders StationScreen when station status is active and wires handlers", async () => {
    const user = userEvent.setup();
    mockStationState.status = "active";
    mockStationState.audioConsent = true;
    mockStationState.remainingMs = 9 * 60 * 1000;
    mockSend.mockResolvedValue({
      reply_text: "Paciente respondeu",
      server_now: "2026-01-01T10:00:00Z",
    });

    render(<App />);

    expect(screen.getByTestId("station-screen")).toBeInTheDocument();
    expect(screen.getByRole("timer")).toHaveTextContent("09:00");

    // Send a message
    const input = screen.getByTestId("message-input");
    await user.type(input, "Olá");
    await user.click(screen.getByTestId("send-button"));

    expect(mockSend).toHaveBeenCalledWith({
      role: "learner",
      modality: "text",
      text: "Olá",
    });

    // Finish session
    await user.click(screen.getByTestId("finish-button"));
    expect(mockFinish).toHaveBeenCalledWith("user");
  });

  it("wires successful voice transcription to a voice learner message", async () => {
    const user = userEvent.setup();
    class MockMediaRecorder {
      readonly mimeType = "audio/webm";
      state: RecordingState = "inactive";
      private listeners = new Map<string, EventListener>();

      addEventListener(type: string, listener: EventListener): void {
        this.listeners.set(type, listener);
      }

      start(): void {
        this.state = "recording";
      }

      stop(): void {
        this.state = "inactive";
        this.listeners.get("dataavailable")?.({
          data: new Blob(["audio"]),
        } as BlobEvent);
        this.listeners.get("stop")?.(new Event("stop"));
      }
    }
    vi.stubGlobal("MediaRecorder", MockMediaRecorder);
    vi.stubGlobal("navigator", {
      ...navigator,
      mediaDevices: {
        getUserMedia: vi.fn().mockResolvedValue({
          getTracks: () => [{ stop: vi.fn() }],
        }),
      },
    });
    mockStationState.status = "active";
    mockStationState.audioConsent = true;
    mockTranscribe.mockResolvedValue("A dor irradia?");
    mockSend.mockResolvedValue({
      reply_text: "Irradia para o braço.",
      server_now: "2026-01-01T10:00:00Z",
    });

    render(<App />);

    await user.click(screen.getByTestId("voice-button"));
    await screen.findByRole("button", { name: strings.stopVoiceInput });
    await user.click(screen.getByTestId("voice-button"));

    await screen.findByText("Irradia para o braço.");
    expect(mockTranscribe).toHaveBeenCalledWith(expect.any(Blob));
    expect(mockSend).toHaveBeenCalledWith({
      role: "learner",
      modality: "voice",
      text: "A dor irradia?",
    });
  });

  it("disables the StationScreen input once the countdown reaches zero", () => {
    mockStationState.status = "active";
    mockStationState.remainingMs = 0;

    render(<App />);

    expect(screen.getByTestId("message-input")).toBeDisabled();
    expect(screen.getByTestId("finish-button")).toBeDisabled();
  });

  it("wires onSynthesize to the station's synthesize function", async () => {
    const user = userEvent.setup();
    const createObjectURL = vi.fn().mockReturnValue("blob:audio-url");
    URL.createObjectURL = createObjectURL;
    URL.revokeObjectURL = vi.fn();
    vi.stubGlobal(
      "Audio",
      class {
        constructor(public src: string) {}
        play = vi.fn().mockResolvedValue(undefined);
        pause = vi.fn();
        addEventListener = vi.fn();
        removeEventListener = vi.fn();
      },
    );

    mockStationState.status = "active";
    mockStationState.audioConsent = true;
    mockSend.mockResolvedValue({
      reply_text: "Paciente respondeu",
      server_now: "2026-01-01T10:00:00Z",
    });
    mockSynthesize.mockResolvedValue(new Blob(["audio"], { type: "audio/mpeg" }));

    render(<App />);

    const input = screen.getByTestId("message-input");
    await user.type(input, "Olá");
    await user.click(screen.getByTestId("send-button"));
    await screen.findByText("Paciente respondeu");

    await user.click(screen.getByTestId("play-button"));

    expect(mockSynthesize).toHaveBeenCalledWith("Paciente respondeu");
  });

  it("renders ResultScreen with finishing state when station status is finishing", () => {
    mockStationState.status = "finishing";
    render(<App />);

    expect(screen.getByText(strings.loadingResult)).toBeInTheDocument();
  });

  it("renders ResultScreen with results when station status is finished", async () => {
    const user = userEvent.setup();
    mockStationState.status = "finished";
    mockStationState.result = partialResult;

    render(<App />);

    expect(screen.getByText(strings.resultReportTitle)).toBeInTheDocument();

    // Restart button triggers reset
    const restartButton = screen.getByRole("button", {
      name: strings.resultRestartButton,
    });
    await user.click(restartButton);
    expect(mockReset).toHaveBeenCalledTimes(1);
  });

  it("renders ResultScreen with failed state and error message when station status is failed", async () => {
    const user = userEvent.setup();
    mockStationState.status = "failed";
    mockStationState.error = "Erro no servidor";

    render(<App />);

    expect(screen.getByRole("alert")).toHaveTextContent("Erro no servidor");

    const restartButton = screen.getByRole("button", {
      name: strings.resultRestartButton,
    });
    await user.click(restartButton);
    expect(mockReset).toHaveBeenCalledTimes(1);
  });
});
