import strings from "../i18n/pt-BR.json";

/** pt-BR labels for the impresso categories the package validator accepts. */
const CATEGORY_LABELS = new Map<string, string>([
  ["physical_exam", strings.impressoCategoryPhysicalExam],
  ["laboratory", strings.impressoCategoryLaboratory],
  ["imaging", strings.impressoCategoryImaging],
  ["report", strings.impressoCategoryReport],
]);

/** Returns the learner-facing label, or null for an unknown category (never the raw key). */
export function impressoCategoryLabel(category: string): string | null {
  return CATEGORY_LABELS.get(category) ?? null;
}
