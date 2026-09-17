import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import strings from "../../../i18n/pt-BR.json";
import { ResultScreenState } from "./ResultScreen";

describe("ResultScreenState (Slice 1)", () => {
  it("renders polite loading status section when status is finishing", () => {
    render(
      <ResultScreenState
        status="finishing"
        hasUsableFeedback={false}
        onRestart={vi.fn()}
      />,
    );

    const statusSection = screen.getByRole("status");
    expect(statusSection).toBeInTheDocument();
    expect(statusSection).toHaveAttribute("aria-live", "polite");
    expect(statusSection).toHaveTextContent(strings.loadingResult);
  });

  it("renders recovery section with alert and restart button when status is failed", async () => {
    const user = userEvent.setup();
    const handleRestart = vi.fn();

    render(
      <ResultScreenState
        status="failed"
        hasUsableFeedback={false}
        onRestart={handleRestart}
      />,
    );

    const alertSection = screen.getByRole("alert");
    expect(alertSection).toBeInTheDocument();
    expect(alertSection).toHaveTextContent(strings.resultUnavailable);

    const restartButton = screen.getByRole("button", {
      name: strings.resultRestartButton,
    });
    expect(restartButton).toBeInTheDocument();

    await user.click(restartButton);
    expect(handleRestart).toHaveBeenCalledTimes(1);
  });

  it("renders recovery section with alert and restart button when finished without usable feedback", async () => {
    const user = userEvent.setup();
    const handleRestart = vi.fn();

    render(
      <ResultScreenState
        status="finished"
        hasUsableFeedback={false}
        onRestart={handleRestart}
      />,
    );

    const alertSection = screen.getByRole("alert");
    expect(alertSection).toBeInTheDocument();
    expect(alertSection).toHaveTextContent(strings.resultUnavailable);

    const restartButton = screen.getByRole("button", {
      name: strings.resultRestartButton,
    });
    expect(restartButton).toBeInTheDocument();

    await user.click(restartButton);
    expect(handleRestart).toHaveBeenCalledTimes(1);
  });

  it("returns null when finished with usable feedback (leaving report presentation to slice 2)", () => {
    const { container } = render(
      <ResultScreenState
        status="finished"
        hasUsableFeedback={true}
        onRestart={vi.fn()}
      />,
    );

    expect(container).toBeEmptyDOMElement();
  });
});
