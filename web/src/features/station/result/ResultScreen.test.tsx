import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import strings from "../i18n/pt-BR.json";
import { partialResult } from "./educational-result.fixture";
import { ResultScreen, ResultScreenState } from "./ResultScreen";

const disclaimer = "Estimativa educacional gerada por IA. Não é nota oficial do Revalida. Não indica aprovação, reprovação, certificação ou prontidão para o exame.";

describe("educational result presentation", () => {
  it("renders a complete exact total independently from the eligible maximum", () => {
    const complete = {
      ...partialResult,
      criteria: [{ ...partialResult.criteria[0], points: "1.125", max_points: "1.5" }],
      coverage: { assessed: 1, uncertain: 0, not_observable: 0, not_applicable: 0 },
      estimates: {
        total: "1.125",
        scored_subtotal: "1.125",
        scored_max: "1.5",
        eligible_max: "1.5",
        unresolved: [],
      },
    };
    render(<ResultScreen status="finished" result={complete} onRestart={vi.fn()} />);
    expect(screen.getByText("Total educacional: 1,125")).toBeInTheDocument();
    expect(screen.getByText("Máximo elegível: 1,5")).toBeInTheDocument();
    expect(screen.queryByText(/Total indisponível/)).not.toBeInTheDocument();
    expect(screen.queryByText("Critérios não resolvidos")).not.toBeInTheDocument();
  });
  it("shows the disclaimer, fictional label, exact partial estimates and scoped authored evidence", () => {
    render(<ResultScreen status="finished" result={partialResult} onRestart={vi.fn()} />);
    expect(screen.getByText(disclaimer)).toBeInTheDocument();
    expect(screen.getByText("Exemplo — dados fictícios")).toBeInTheDocument();
    expect(screen.getByText("Subtotal avaliado: 0,25")).toBeInTheDocument();
    expect(screen.getByText("Máximo avaliado: 0,25")).toBeInTheDocument();
    expect(screen.getByText("Máximo elegível: 1,25")).toBeInTheDocument();
    expect(screen.getByText(/Total indisponível/)).toBeInTheDocument();
    expect(screen.getByText(/Avaliados: 1/)).toBeInTheDocument();
    const first = screen.getByText(partialResult.criteria[0].description).closest("li")!;
    expect(within(first).getByText("Nível autoral: Criterion A is partially adequate.")).toBeInTheDocument();
    expect(within(first).getByRole("blockquote")).toHaveTextContent("Exemplo da sessão");
    expect(within(first).getByText(/Pontos: 0,25/)).toBeInTheDocument();
    const unresolved = screen.getByText(partialResult.criteria[1].description).closest("li")!;
    expect(within(unresolved).getByText(/Incerto — sem pontos atribuídos/)).toBeInTheDocument();
    expect(within(unresolved).queryByText(/Pontos:/)).not.toBeInTheDocument();
    expect(screen.queryByText("criterion-a")).not.toBeInTheDocument();
  });

  it("distinguishes genuine zero, not observable and excluded without color, and labels only placeholders", () => {
    const zero = { ...partialResult.criteria[0], status: "assessed" as const, reason: null, level: "inadequado", level_description: "No observed action.", points: "0", evidence: [], evidence_ids: [] };
    const unobservable = { ...partialResult.criteria[1], id: "physical", status: "not_observable" as const, reason: "required_modality_unavailable" };
    const excluded = { ...partialResult.criteria[1], id: "excluded", status: "not_applicable" as const, reason: "authored_exclusion" };
    render(<ResultScreen status="finished" result={{ ...partialResult, placeholder: false, criteria: [zero, unobservable, excluded] }} onRestart={vi.fn()} />);
    expect(screen.queryByText("Exemplo — dados fictícios")).not.toBeInTheDocument();
    expect(screen.getByText(/Pontos: 0 de/)).toBeInTheDocument();
    expect(screen.getByText(/Não observável — modalidade indisponível/)).toBeInTheDocument();
    expect(screen.getByText(/Excluído pelo autor — fora dos máximos/)).toBeInTheDocument();
  });

  it("shows empty and all-excluded rubrics as no estimate, not fabricated zero totals", () => {
    const { rerender } = render(<ResultScreen status="finished" result={{ ...partialResult, criteria: [], coverage: { assessed: 0, uncertain: 0, not_observable: 0, not_applicable: 0 }, estimates: { total: null, scored_subtotal: "0", scored_max: "0", eligible_max: "0", unresolved: [] } }} onRestart={vi.fn()} />);
    expect(screen.getByText(/Nenhum critério elegível/)).toBeInTheDocument();
    rerender(<ResultScreen status="finished" result={{ ...partialResult, criteria: [{ ...partialResult.criteria[1], status: "not_applicable", reason: "authored_exclusion" }], coverage: { assessed: 0, uncertain: 0, not_observable: 0, not_applicable: 1 }, estimates: { total: null, scored_subtotal: "0", scored_max: "0", eligible_max: "0", unresolved: [] } }} onRestart={vi.fn()} />);
    expect(screen.getByText(/Nenhum critério elegível/)).toBeInTheDocument();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });

  it("shows the authored level description once and never the raw level identifier", () => {
    const { container } = render(<ResultScreen status="finished" result={partialResult} onRestart={vi.fn()} />);
    expect(container).not.toHaveTextContent("parcialmente_adequado");
    expect(screen.getAllByText(/Criterion A is partially adequate\./)).toHaveLength(1);
  });

  it("omits the level line when the authored level description is blank", () => {
    const blank = { ...partialResult.criteria[0], level_description: " " };
    render(<ResultScreen status="finished" result={{ ...partialResult, criteria: [blank, partialResult.criteria[1]] }} onRestart={vi.fn()} />);
    expect(screen.queryByText(/Nível autoral/)).not.toBeInTheDocument();
    expect(screen.getByText(/Pontos: 0,25/)).toBeInTheDocument();
  });

  it("exposes the disclaimer as a note on the finished report", () => {
    render(<ResultScreen status="finished" result={partialResult} onRestart={vi.fn()} />);
    expect(screen.getByRole("note")).toHaveTextContent(disclaimer);
  });

  it("keeps the session-only sentence out of the coverage summary and next to restart", () => {
    render(<ResultScreen status="finished" result={partialResult} onRestart={vi.fn()} />);
    const coverage = screen.getByRole("region", { name: strings.resultCoverage });
    expect(within(coverage).queryByText(strings.resultSessionOnly)).not.toBeInTheDocument();
    const sessionOnly = screen.getByText(strings.resultSessionOnly);
    expect(sessionOnly.parentElement).toBe(screen.getByRole("button").parentElement);
  });

  it.each([
    ["finishing", "status"],
    ["failed", "alert"],
  ] as const)("stacks the disclaimer note and the %s state in one column container", (status, role) => {
    const { container } = render(<ResultScreen status={status} result={null} onRestart={vi.fn()} />);
    const note = screen.getByRole("note");
    expect(note).toHaveTextContent(disclaimer);
    const column = screen.getByRole(role).parentElement!;
    expect(column).not.toBe(container);
    expect(column).toHaveClass("result-screen");
    expect(note.parentElement).toBe(column);
    expect(note.compareDocumentPosition(screen.getByRole(role)) & Node.DOCUMENT_POSITION_FOLLOWING).not.toBe(0);
  });

  it("does not add affirmative official, pass/fail, readiness or percentage claims", () => {
    const { container } = render(<ResultScreen status="finished" result={partialResult} onRestart={vi.fn()} />);
    const text = container.textContent!.replace(disclaimer, "").toLowerCase();
    for (const word of ["nota oficial", "aprovação", "reprovação", "prontidão", "certificação", "%", "readiness", "pass/fail"]) expect(text).not.toContain(word);
  });

  it("keeps restart acknowledgment, disabled behavior and discard error visible", async () => {
    const restart = vi.fn();
    const user = userEvent.setup();
    const { rerender } = render(<ResultScreen status="finished" result={partialResult} onRestart={restart} disabled errorMessage="Falha ao encerrar" />);
    expect(screen.getByRole("alert")).toHaveTextContent("Falha ao encerrar");
    await user.click(screen.getByRole("button"));
    expect(restart).not.toHaveBeenCalled();
    rerender(<ResultScreen status="finished" result={partialResult} onRestart={restart} />);
    await user.click(screen.getByRole("button"));
    expect(restart).toHaveBeenCalledTimes(1);
  });

  it("keeps technical failure separate from educational uncertainty", () => {
    const { rerender } = render(<ResultScreen status="finishing" result={null} onRestart={vi.fn()} />);
    const loading = screen.getByRole("status");
    expect(loading).toHaveAttribute("aria-live", "polite");
    rerender(<ResultScreen status="failed" result={partialResult} errorMessage="Tentativa inválida" onRestart={vi.fn()} />);
    expect(screen.getByRole("alert")).not.toBe(loading);
    expect(screen.getByRole("alert")).toHaveTextContent("Tentativa inválida");
    expect(screen.queryByRole("blockquote")).not.toBeInTheDocument();
    expect(screen.getByText(disclaimer)).toBeInTheDocument();
    rerender(<ResultScreen status="finished" result={null} onRestart={vi.fn()} />);
    expect(screen.getByRole("alert")).toHaveTextContent(strings.resultUnavailable);
  });
});

describe("ResultScreenState", () => {
  it("leaves valid results to the report", () => {
    const { container } = render(<ResultScreenState status="finished" hasUsableFeedback onRestart={vi.fn()} />);
    expect(container).toBeEmptyDOMElement();
  });
  it("announces failure and honors disabled recovery", async () => {
    const restart = vi.fn();
    const user = userEvent.setup();
    const { rerender } = render(<ResultScreenState status="failed" hasUsableFeedback={false} onRestart={restart} disabled />);
    expect(screen.getByRole("alert")).toHaveAttribute("aria-live", "assertive");
    await user.click(screen.getByRole("button"));
    expect(restart).not.toHaveBeenCalled();
    rerender(<ResultScreenState status="failed" hasUsableFeedback={false} onRestart={restart} />);
    await user.click(screen.getByRole("button"));
    expect(restart).toHaveBeenCalledOnce();
  });
});
