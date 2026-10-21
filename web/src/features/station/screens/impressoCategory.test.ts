import { describe, expect, it } from "vitest";
import { impressoCategoryLabel } from "./impressoCategory";

describe("impressoCategoryLabel", () => {
  it.each([
    ["physical_exam", "Exame físico"],
    ["laboratory", "Exames laboratoriais"],
    ["imaging", "Exame de imagem"],
    ["report", "Laudo ou registro"],
  ])("labels %s in pt-BR", (category, label) => {
    expect(impressoCategoryLabel(category)).toBe(label);
  });

  it.each(["unknown_category", "", "toString", "__proto__"])(
    "returns null for an unknown category (%s)",
    (category) => {
      expect(impressoCategoryLabel(category)).toBeNull();
    },
  );
});
