import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import type { SessionResult } from "../../../api/client";
import strings from "../../../i18n/pt-BR.json";
import { ResultScreen, ResultScreenState } from "./ResultScreen";

describe("ResultScreen (Slice 2)", () => {
  const sampleResult: SessionResult = {
    session_id: "session-123",
    status: "completed",
    criteria: [
      {
        id: "crit-history-onset",
        status: "met",
        evidence: [],
        recommendation: "Mantenha a abordagem sistemática.",
      },
      {
        id: "crit-family-history",
        status: "omitted",
        evidence: [],
        recommendation: "Investigue antecedentes familiares na anamnese.",
      },
      {
        id: "crit-duration",
        status: "uncertain",
        evidence: [],
        recommendation: "Esclareça o tempo de evolução dos sintomas.",
      },
    ],
  };

  it("renders ordered report with 3 criteria statuses, visible ordinals, and recommendations", () => {
    render(
      <ResultScreen
        status="finished"
        result={sampleResult}
        onRestart={vi.fn()}
      />,
    );

    const reportHeading = screen.getByRole("heading", {
      level: 1,
      name: strings.resultReportTitle,
    });
    expect(reportHeading).toBeInTheDocument();

    const reportList = screen.getByRole("list");
    expect(reportList).toBeInTheDocument();

    const items = screen.getAllByRole("listitem");
    expect(items).toHaveLength(3);

    expect(
      screen.getByText(`${strings.resultOrdinalPrefix} 1`),
    ).toBeInTheDocument();
    expect(
      screen.getByText(`${strings.resultOrdinalPrefix} 2`),
    ).toBeInTheDocument();
    expect(
      screen.getByText(`${strings.resultOrdinalPrefix} 3`),
    ).toBeInTheDocument();

    expect(screen.getByText(strings.criterionMet)).toBeInTheDocument();
    expect(screen.getByText(strings.criterionOmitted)).toBeInTheDocument();
    expect(screen.getByText(strings.criterionUncertain)).toBeInTheDocument();

    const recHeadings = screen.getAllByText(
      strings.resultRecommendationHeading,
    );
    expect(recHeadings).toHaveLength(3);

    expect(
      screen.getByText("Mantenha a abordagem sistemática."),
    ).toBeInTheDocument();
    expect(
      screen.getByText("Investigue antecedentes familiares na anamnese."),
    ).toBeInTheDocument();
    expect(
      screen.getByText("Esclareça o tempo de evolução dos sintomas."),
    ).toBeInTheDocument();
  });

  it("renders evidence heading and blockquote excerpts with mark highlight when evidence is non-empty", () => {
    const resultWithEvidence: SessionResult = {
      session_id: "session-with-evidence",
      status: "completed",
      criteria: [
        {
          id: "crit-history-onset",
          status: "met",
          evidence: [
            "Quando começou a dor no peito?",
            "A dor irradia para algum lugar?",
          ],
          recommendation: "Mantenha a abordagem sistemática.",
        },
      ],
    };

    render(
      <ResultScreen
        status="finished"
        result={resultWithEvidence}
        onRestart={vi.fn()}
      />,
    );

    expect(
      screen.getByRole("heading", {
        level: 3,
        name: strings.resultEvidenceHeading,
      }),
    ).toBeInTheDocument();

    const excerpts = screen.getAllByRole("blockquote");
    expect(excerpts).toHaveLength(2);

    const firstMark = excerpts[0].querySelector("mark");
    expect(firstMark).not.toBeNull();
    expect(firstMark).toHaveTextContent("Quando começou a dor no peito?");

    const secondMark = excerpts[1].querySelector("mark");
    expect(secondMark).not.toBeNull();
    expect(secondMark).toHaveTextContent("A dor irradia para algum lugar?");
  });

  it("renders multiple criteria preserving evidence scoping per criterion", () => {
    const mixedResult: SessionResult = {
      session_id: "mixed-evidence-session",
      status: "completed",
      criteria: [
        {
          id: "crit-onset",
          status: "met",
          evidence: ["Início súbito da dor."],
          recommendation: "Rec 1",
        },
        {
          id: "crit-risk-factors",
          status: "omitted",
          evidence: [],
          recommendation: "Rec 2",
        },
        {
          id: "crit-history",
          status: "uncertain",
          evidence: ["Histórico incerto.", "Dúvida relatada."],
          recommendation: "Rec 3",
        },
      ],
    };

    render(
      <ResultScreen
        status="finished"
        result={mixedResult}
        onRestart={vi.fn()}
      />,
    );

    const evidenceHeadings = screen.getAllByRole("heading", {
      level: 3,
      name: strings.resultEvidenceHeading,
    });
    expect(evidenceHeadings).toHaveLength(2);

    const excerpts = screen.getAllByRole("blockquote");
    expect(excerpts).toHaveLength(3);
    expect(excerpts[0]).toHaveTextContent("Início súbito da dor.");
    expect(excerpts[1]).toHaveTextContent("Histórico incerto.");
    expect(excerpts[2]).toHaveTextContent("Dúvida relatada.");
  });

  it("omits the evidence section entirely when evidence array is empty", () => {
    render(
      <ResultScreen
        status="finished"
        result={sampleResult}
        onRestart={vi.fn()}
      />,
    );

    expect(
      screen.queryByRole("heading", {
        level: 3,
        name: strings.resultEvidenceHeading,
      }),
    ).not.toBeInTheDocument();
    expect(screen.queryByRole("blockquote")).not.toBeInTheDocument();
  });

  it("hides technical criteria IDs from visible text without coupling to metadata attributes", () => {
    render(
      <ResultScreen
        status="finished"
        result={sampleResult}
        onRestart={vi.fn()}
      />,
    );

    expect(screen.queryByText("crit-history-onset")).not.toBeInTheDocument();
    expect(screen.queryByText("crit-family-history")).not.toBeInTheDocument();
    expect(screen.queryByText("crit-duration")).not.toBeInTheDocument();
    expect(screen.queryByText(/crit-/i)).not.toBeInTheDocument();
  });

  it("delegates recovery when status is finishing, failed, or result is null/empty", () => {
    const handleRestart = vi.fn();

    const { unmount: unmountFinishing } = render(
      <ResultScreen
        status="finishing"
        result={null}
        onRestart={handleRestart}
      />,
    );
    expect(screen.getByRole("status")).toHaveTextContent(strings.loadingResult);
    unmountFinishing();

    const { unmount: unmountFailed } = render(
      <ResultScreen status="failed" result={null} onRestart={handleRestart} />,
    );
    expect(screen.getByRole("alert")).toHaveTextContent(
      strings.resultUnavailable,
    );
    unmountFailed();

    const { unmount: unmountNullResult } = render(
      <ResultScreen
        status="finished"
        result={null}
        onRestart={handleRestart}
      />,
    );
    expect(screen.getByRole("alert")).toHaveTextContent(
      strings.resultUnavailable,
    );
    unmountNullResult();

    const { unmount: unmountEmptyResult } = render(
      <ResultScreen
        status="finished"
        result={{ session_id: "s1", status: "completed", criteria: [] }}
        onRestart={handleRestart}
      />,
    );
    expect(screen.getByRole("alert")).toHaveTextContent(
      strings.resultUnavailable,
    );
    unmountEmptyResult();
  });

  it("triggers onRestart from report action button", async () => {
    const user = userEvent.setup();
    const handleRestart = vi.fn();

    render(
      <ResultScreen
        status="finished"
        result={sampleResult}
        onRestart={handleRestart}
      />,
    );

    const restartButton = screen.getByRole("button", {
      name: strings.resultRestartButton,
    });
    expect(restartButton).toBeInTheDocument();

    await user.click(restartButton);
    expect(handleRestart).toHaveBeenCalledTimes(1);
  });

  it("does not contain forbidden judgmental, grading, or score language", () => {
    const { container } = render(
      <ResultScreen
        status="finished"
        result={sampleResult}
        onRestart={vi.fn()}
      />,
    );

    const fullText = (container.textContent || "").toLowerCase();
    const forbiddenPatterns = [
      "nota",
      "score",
      "pontuação",
      "pontuacao",
      "porcentagem",
      "porcento",
      "%",
      "aprovad",
      "reprovad",
      "pass",
      "fail",
      "grade",
      "prontidão",
      "prontidao",
      "readiness",
    ];

    for (const pattern of forbiddenPatterns) {
      expect(fullText).not.toContain(pattern);
    }
  });
});

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

  it("remounts DOM node when transitioning from finishing to failed recovery (TR-03)", () => {
    const { rerender } = render(
      <ResultScreenState
        status="finishing"
        hasUsableFeedback={false}
        onRestart={vi.fn()}
      />,
    );

    const finishingNode = screen.getByRole("status");

    rerender(
      <ResultScreenState
        status="failed"
        hasUsableFeedback={false}
        onRestart={vi.fn()}
      />,
    );

    const recoveryNode = screen.getByRole("alert");
    expect(recoveryNode).not.toBe(finishingNode);
  });

  it("binds disabled prop to restart button and prevents click when disabled (TR-01)", async () => {
    const user = userEvent.setup();
    const handleRestart = vi.fn();

    render(
      <ResultScreenState
        status="failed"
        hasUsableFeedback={false}
        onRestart={handleRestart}
        disabled={true}
      />,
    );

    const restartButton = screen.getByRole("button", {
      name: strings.resultRestartButton,
    });
    expect(restartButton).toBeDisabled();

    await user.click(restartButton);
    expect(handleRestart).not.toHaveBeenCalled();
  });
});
