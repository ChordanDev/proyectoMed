import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import App from "./App";
import strings from "./features/station/i18n/pt-BR.json";
import type { SessionResult } from "./features/station/api/client";

const mockStart = vi.fn();
const mockSend = vi.fn();
const mockFinish = vi.fn();
const mockReset = vi.fn();

let mockStationState = {
  status: "idle",
  result: null as SessionResult | null,
  error: null as string | null,
  start: mockStart,
  send: mockSend,
  finish: mockFinish,
  reset: mockReset,
};

vi.mock("./features/station", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./features/station")>();
  return {
    ...actual,
    useStation: () => mockStationState,
  };
});

describe("App", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockStationState = {
      status: "idle",
      result: null,
      error: null,
      start: mockStart,
      send: mockSend,
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
    await user.click(startButton);

    expect(mockStart).toHaveBeenCalledWith(false);
  });

  it("renders loading message when station status is loading", () => {
    mockStationState.status = "loading";
    render(<App />);

    expect(screen.getByRole("status")).toHaveTextContent(strings.loadingStation);
  });

  it("renders StationScreen when station status is active and wires handlers", async () => {
    const user = userEvent.setup();
    mockStationState.status = "active";
    mockSend.mockResolvedValue({
      reply_text: "Paciente respondeu",
      server_now: "2026-01-01T10:00:00Z",
    });

    render(<App />);

    expect(screen.getByTestId("station-screen")).toBeInTheDocument();

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

  it("renders ResultScreen with finishing state when station status is finishing", () => {
    mockStationState.status = "finishing";
    render(<App />);

    expect(screen.getByText(strings.loadingResult)).toBeInTheDocument();
  });

  it("renders ResultScreen with results when station status is finished", async () => {
    const user = userEvent.setup();
    mockStationState.status = "finished";
    mockStationState.result = {
      session_id: "s-1",
      status: "completed",
      criteria: [
        {
          id: "c-1",
          status: "met",
          evidence: ["Boa tarde"],
          recommendation: "Excelente abordagem",
        },
      ],
    };

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
