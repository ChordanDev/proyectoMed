import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import strings from "../i18n/pt-BR.json";
import { BriefScreen } from "./BriefScreen";

const brief = {
  scenario: "Você é o médico de plantão em um pronto-socorro.",
  tasks: ["Obter anamnese dirigida.", "Indicar a conduta inicial."],
};

describe("BriefScreen", () => {
  it("shows the title, scenario, numbered tasks and the fictional-case note", () => {
    render(
      <BriefScreen title="Apendicite aguda" brief={brief} onEnter={vi.fn()} />,
    );

    expect(
      screen.getByRole("heading", { level: 1, name: "Apendicite aguda" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("heading", { name: strings.briefScenarioHeading }),
    ).toBeInTheDocument();
    expect(screen.getByText(brief.scenario)).toBeInTheDocument();

    const list = screen.getByRole("list", { name: strings.briefTasksHeading });
    expect(list.tagName).toBe("OL");
    expect(
      within(list)
        .getAllByRole("listitem")
        .map((item) => item.textContent),
    ).toEqual(brief.tasks);

    expect(screen.getByText(strings.briefFictionalNote)).toBeInTheDocument();
    expect(screen.getByText(strings.briefTimerNote)).toBeInTheDocument();
  });

  it("enters the station from the start button", async () => {
    const user = userEvent.setup();
    const onEnter = vi.fn();
    render(<BriefScreen title="Apendicite aguda" brief={brief} onEnter={onEnter} />);

    await user.click(screen.getByRole("button", { name: strings.briefEnterButton }));

    expect(onEnter).toHaveBeenCalledTimes(1);
  });

  it("shows a loading notice while the brief is not loaded", () => {
    render(<BriefScreen brief={null} onEnter={vi.fn()} />);

    expect(screen.getByRole("status")).toHaveTextContent(strings.briefLoading);
    expect(
      screen.getByRole("heading", { level: 1, name: strings.stationScreenTitle }),
    ).toBeInTheDocument();
  });

  it("shows the load error and still lets the learner start", async () => {
    const user = userEvent.setup();
    const onEnter = vi.fn();
    render(
      <BriefScreen
        brief={null}
        error={strings.briefUnavailable}
        onEnter={onEnter}
      />,
    );

    expect(screen.getByRole("alert")).toHaveTextContent(strings.briefUnavailable);
    await user.click(screen.getByRole("button", { name: strings.briefEnterButton }));
    expect(onEnter).toHaveBeenCalledTimes(1);
  });

  it("disables the start button when asked", () => {
    render(<BriefScreen brief={brief} onEnter={vi.fn()} disabled />);

    expect(
      screen.getByRole("button", { name: strings.briefEnterButton }),
    ).toBeDisabled();
  });
});
