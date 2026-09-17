import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import strings from "../i18n/pt-BR.json";
import { StationScreen } from "./StationScreen";

describe("StationScreen", () => {
  const defaultProps = {
    onSend: vi.fn().mockResolvedValue("reply text"),
    onFinish: vi.fn(),
  };

  it("renders the default title and controls", () => {
    render(<StationScreen {...defaultProps} />);

    expect(screen.getByText(strings.stationScreenTitle)).toBeInTheDocument();
    expect(screen.getByTestId("finish-button")).toBeInTheDocument();
    expect(screen.getByTestId("message-input")).toBeInTheDocument();
    expect(screen.getByTestId("send-button")).toBeInTheDocument();
  });

  it("renders a custom title when provided", () => {
    render(<StationScreen {...defaultProps} title="Dor torácica" />);

    expect(screen.getByText("Dor torácica")).toBeInTheDocument();
  });

  it("disables send button when input is empty", () => {
    render(<StationScreen {...defaultProps} />);

    expect(screen.getByTestId("send-button")).toBeDisabled();
  });

  it("enables send button when input has text", async () => {
    const user = userEvent.setup();
    render(<StationScreen {...defaultProps} />);

    await user.type(screen.getByTestId("message-input"), "Olá");

    expect(screen.getByTestId("send-button")).toBeEnabled();
  });

  it("sends a message and displays learner + patient messages", async () => {
    const user = userEvent.setup();
    const onSend = vi.fn().mockResolvedValue("Boa tarde, doutor.");
    render(<StationScreen {...defaultProps} onSend={onSend} />);

    await user.type(screen.getByTestId("message-input"), "Boa tarde");
    await user.click(screen.getByTestId("send-button"));

    // Learner message appears immediately
    expect(screen.getByText("Boa tarde")).toBeInTheDocument();

    // onSend called with trimmed text
    expect(onSend).toHaveBeenCalledWith("Boa tarde");

    // Patient reply appears after resolution
    await waitFor(() => {
      expect(screen.getByText("Boa tarde, doutor.")).toBeInTheDocument();
    });
  });

  it("clears input after sending", async () => {
    const user = userEvent.setup();
    render(<StationScreen {...defaultProps} />);

    const input = screen.getByTestId("message-input");
    await user.type(input, "Teste");
    await user.click(screen.getByTestId("send-button"));

    expect(input).toHaveValue("");
  });

  it("shows typing indicator while waiting for reply", async () => {
    const user = userEvent.setup();
    let resolve: (value: string | null) => void;
    const onSend = vi.fn(
      () => new Promise<string | null>((r) => { resolve = r; }),
    );
    render(<StationScreen {...defaultProps} onSend={onSend} />);

    await user.type(screen.getByTestId("message-input"), "Olá");
    await user.click(screen.getByTestId("send-button"));

    expect(screen.getByTestId("typing-indicator")).toBeInTheDocument();
    expect(screen.getByTestId("typing-indicator")).toHaveTextContent(
      strings.sendingMessage,
    );

    // Resolve the pending send
    resolve!("Resposta");

    await waitFor(() => {
      expect(screen.queryByTestId("typing-indicator")).not.toBeInTheDocument();
    });
  });

  it("disables input and send while a message is in flight", async () => {
    const user = userEvent.setup();
    let resolve: (value: string | null) => void;
    const onSend = vi.fn(
      () => new Promise<string | null>((r) => { resolve = r; }),
    );
    render(<StationScreen {...defaultProps} onSend={onSend} />);

    await user.type(screen.getByTestId("message-input"), "Olá");
    await user.click(screen.getByTestId("send-button"));

    expect(screen.getByTestId("message-input")).toBeDisabled();
    expect(screen.getByTestId("send-button")).toBeDisabled();

    resolve!("ok");

    await waitFor(() => {
      expect(screen.getByTestId("message-input")).toBeEnabled();
    });
  });

  it("sends on Enter key press", async () => {
    const user = userEvent.setup();
    const onSend = vi.fn().mockResolvedValue("reply");
    render(<StationScreen {...defaultProps} onSend={onSend} />);

    await user.type(screen.getByTestId("message-input"), "Enter test{enter}");

    expect(onSend).toHaveBeenCalledWith("Enter test");
  });

  it("handles null reply (API failure) without crashing", async () => {
    const user = userEvent.setup();
    const onSend = vi.fn().mockResolvedValue(null);
    render(<StationScreen {...defaultProps} onSend={onSend} />);

    await user.type(screen.getByTestId("message-input"), "Olá");
    await user.click(screen.getByTestId("send-button"));

    // Learner message shown
    await waitFor(() => {
      expect(screen.getByText("Olá")).toBeInTheDocument();
    });

    // No patient message rendered
    expect(screen.queryByTestId("message-patient")).not.toBeInTheDocument();

    // Input re-enabled
    await waitFor(() => {
      expect(screen.getByTestId("message-input")).toBeEnabled();
    });
  });

  it("displays an external error message", () => {
    render(
      <StationScreen {...defaultProps} error="Erro de conexão" />,
    );

    expect(screen.getByTestId("station-error")).toBeInTheDocument();
    expect(screen.getByText("Erro de conexão")).toBeInTheDocument();
  });

  it("calls onFinish when finish button is clicked", async () => {
    const user = userEvent.setup();
    const onFinish = vi.fn();
    render(<StationScreen {...defaultProps} onFinish={onFinish} />);

    await user.click(screen.getByTestId("finish-button"));

    expect(onFinish).toHaveBeenCalledTimes(1);
  });

  it("disables controls when disabled prop is true", () => {
    render(<StationScreen {...defaultProps} disabled />);

    expect(screen.getByTestId("message-input")).toBeDisabled();
    expect(screen.getByTestId("send-button")).toBeDisabled();
    expect(screen.getByTestId("finish-button")).toBeDisabled();
  });

  it("trims whitespace-only input and does not send", async () => {
    const user = userEvent.setup();
    const onSend = vi.fn();
    render(<StationScreen {...defaultProps} onSend={onSend} />);

    await user.type(screen.getByTestId("message-input"), "   ");

    // Send button remains disabled for whitespace-only
    expect(screen.getByTestId("send-button")).toBeDisabled();
  });

  it("renders multiple conversation turns in order", async () => {
    const user = userEvent.setup();
    let callCount = 0;
    const onSend = vi.fn(() => {
      callCount++;
      return Promise.resolve(`Reply ${callCount}`);
    });
    render(<StationScreen {...defaultProps} onSend={onSend} />);

    // First turn
    await user.type(screen.getByTestId("message-input"), "Turn 1");
    await user.click(screen.getByTestId("send-button"));

    await waitFor(() => {
      expect(screen.getByText("Reply 1")).toBeInTheDocument();
    });

    // Second turn
    await user.type(screen.getByTestId("message-input"), "Turn 2");
    await user.click(screen.getByTestId("send-button"));

    await waitFor(() => {
      expect(screen.getByText("Reply 2")).toBeInTheDocument();
    });

    // All messages present in order
    const allMessages = screen.getAllByTestId(/^message-(learner|patient)$/);
    expect(allMessages).toHaveLength(4);
  });
});
