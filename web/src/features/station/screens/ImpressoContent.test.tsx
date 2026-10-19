import { describe, expect, it } from "vitest";
import { render, screen } from "@testing-library/react";
import { ImpressoContent } from "./ImpressoContent";

describe("ImpressoContent", () => {
  it("renders a bullet list with bold labels and no Markdown markers", () => {
    const { container } = render(
      <ImpressoContent
        content={
          "- **Estado geral:** regular, consciente.\n- **Ausculta:** ruídos presentes."
        }
      />,
    );

    const items = screen.getAllByRole("listitem");
    expect(items).toHaveLength(2);
    expect(items[0]).toHaveTextContent("Estado geral: regular, consciente.");
    expect(items[1]).toHaveTextContent("Ausculta: ruídos presentes.");

    const bold = container.querySelectorAll("strong");
    expect(Array.from(bold).map((node) => node.textContent)).toEqual([
      "Estado geral:",
      "Ausculta:",
    ]);
    expect(container.textContent).not.toContain("**");
    expect(container.textContent).not.toMatch(/(^|\n)- /);
  });

  it("renders paragraphs separated by blank lines and a list after a bold paragraph", () => {
    const { container } = render(
      <ImpressoContent
        content={
          "**Hemograma completo:**\n\n- Hemoglobina: 14,6 g/dL.\n- Leucócitos: 15.800/mm³.\n\n**Conclusão:** achados compatíveis."
        }
      />,
    );

    const paragraphs = container.querySelectorAll("p");
    expect(paragraphs).toHaveLength(2);
    expect(paragraphs[0]).toHaveTextContent("Hemograma completo:");
    expect(paragraphs[1]).toHaveTextContent("Conclusão: achados compatíveis.");
    expect(screen.getAllByRole("listitem")).toHaveLength(2);
    expect(container.textContent).not.toContain("**");
  });

  it("renders ### lines as headings without the hash markers", () => {
    render(
      <ImpressoContent
        content={
          "### SINAIS VITAIS:\n- PA: 150/90 mmHg\n\n### EXAME FÍSICO:\n- Geral: bom estado."
        }
      />,
    );

    const headings = screen.getAllByRole("heading");
    expect(headings.map((heading) => heading.textContent)).toEqual([
      "SINAIS VITAIS:",
      "EXAME FÍSICO:",
    ]);
    expect(screen.getAllByRole("listitem")).toHaveLength(2);
    expect(screen.queryByText(/###/)).not.toBeInTheDocument();
  });

  it("keeps single line breaks inside a paragraph", () => {
    const { container } = render(
      <ImpressoContent content={"Primeira linha.\nSegunda linha."} />,
    );

    const paragraph = container.querySelector("p");
    expect(paragraph).not.toBeNull();
    expect(paragraph?.innerHTML).toBe("Primeira linha.<br>Segunda linha.");
  });

  it("renders an unclosed bold marker as literal text", () => {
    const { container } = render(
      <ImpressoContent content={"Valor **sem fim"} />,
    );

    expect(container.querySelector("strong")).toBeNull();
    expect(container).toHaveTextContent("Valor **sem fim");
  });

  it("never turns package markup into HTML elements", () => {
    const { container } = render(
      <ImpressoContent
        content={
          '<img src=x onerror="alert(1)"> **<script>alert(2)</script>**\n- <b>negrito</b>'
        }
      />,
    );

    expect(container.querySelector("img")).toBeNull();
    expect(container.querySelector("script")).toBeNull();
    expect(container.querySelector("b")).toBeNull();
    expect(container).toHaveTextContent('<img src=x onerror="alert(1)">');
    expect(container.querySelector("strong")).toHaveTextContent(
      "<script>alert(2)</script>",
    );
    expect(screen.getByRole("listitem")).toHaveTextContent("<b>negrito</b>");
  });
});
