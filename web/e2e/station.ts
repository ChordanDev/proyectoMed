import { expect, type Page } from "@playwright/test";
import { readFileSync } from "node:fs";
import type { StationStack } from "./fixtures";

// The learner-visible pt-BR copy, read from the SPA's own catalogue so the
// suite asserts exactly what the learner sees.
export const strings: Record<string, string> = JSON.parse(
  readFileSync(
    new URL("../src/features/station/i18n/pt-BR.json", import.meta.url),
    "utf8",
  ),
);

/** Mirrors `sessionIdStorageKey` in `useStation`. */
const SESSION_ID_STORAGE_KEY = "revalida.station.sessionId";

export const PATIENT_REPLY = "A dor começou durante uma caminhada.";
export const LEARNER_QUESTION = "Quando começou a dor no peito?";

/** Notice (with audio consent) → brief → station. */
export async function enterStation(page: Page): Promise<void> {
  await page.goto("/");
  await expect(
    page.getByRole("heading", { name: strings.noticeTitle }),
  ).toBeVisible();
  await page.getByRole("checkbox", { name: strings.consentCheckboxLabel }).check();
  await page.getByRole("button", { name: strings.noticeButton }).click();

  await expect(page.getByTestId("brief-screen")).toBeVisible();
  await expect(
    page.getByRole("heading", { name: strings.briefScenarioHeading }),
  ).toBeVisible();
  await page.getByRole("button", { name: strings.briefEnterButton }).click();

  await expect(page.getByTestId("station-screen")).toBeVisible();
  await expect(countdown(page)).toBeVisible();
}

export function countdown(page: Page) {
  return page.getByRole("timer", { name: strings.timeRemainingLabel });
}

/** Seconds left on the station countdown ("MM:SS"). */
export async function remainingSeconds(page: Page): Promise<number> {
  const text = (await countdown(page).textContent()) ?? "";
  const match = /^(\d{2}):(\d{2})$/.exec(text.trim());
  if (!match) throw new Error(`Unexpected countdown text: "${text}"`);
  return Number(match[1]) * 60 + Number(match[2]);
}

export async function sendText(page: Page, text: string): Promise<void> {
  await page.getByRole("textbox", { name: strings.inputPlaceholder }).fill(text);
  await page.getByRole("button", { name: strings.sendButton }).click();
}

/**
 * One learner question and its patient reply on screen, so a later check that
 * the reply is gone proves something was cleared.
 */
export async function answeredTurn(page: Page): Promise<void> {
  await sendText(page, LEARNER_QUESTION);
  await expect(page.getByTestId("message-patient")).toHaveText(
    new RegExp(PATIENT_REPLY),
  );
}

export async function persistedSessionId(page: Page): Promise<string | null> {
  return page.evaluate(
    (key) => sessionStorage.getItem(key),
    SESSION_ID_STORAGE_KEY,
  );
}

/** Asserts the server no longer holds the session (discarded, purged or never existed). */
export async function expectSessionGone(
  stack: StationStack,
  sessionId: string,
): Promise<void> {
  await expect
    .poll(async () => (await stack.api.readSession(sessionId)).code, {
      message: `session ${sessionId} should be gone from the server`,
    })
    .toMatch(/^session_(not_found|expired)$/);
}

/** The recovery state shown after an invalidated attempt: no feedback, only a restart. */
export async function expectInvalidatedAttempt(page: Page): Promise<void> {
  await expect(page.getByRole("alert")).toBeVisible();
  await expect(
    page.getByRole("button", { name: strings.resultRestartButton }),
  ).toBeVisible();
  await expect(page.getByText(strings.resultRestartDiscards)).toBeVisible();
  await expectNoStaleOutput(page);
}

/** No patient output, transcript or result is left on screen. */
export async function expectNoStaleOutput(page: Page): Promise<void> {
  await expect(page.getByTestId("message-patient")).toHaveCount(0);
  await expect(page.getByText(PATIENT_REPLY)).toHaveCount(0);
  await expect(
    page.getByRole("heading", { name: strings.resultReportTitle }),
  ).toHaveCount(0);
}

/** Restart from the result or recovery screen: the attempt is discarded. */
export async function restartStation(
  page: Page,
  stack: StationStack,
  sessionId: string,
): Promise<void> {
  await page.getByRole("button", { name: strings.resultRestartButton }).click();
  await expect(
    page.getByRole("heading", { name: strings.noticeTitle }),
  ).toBeVisible();
  await expectNoStaleOutput(page);
  expect(await persistedSessionId(page)).toBeNull();
  await expectSessionGone(stack, sessionId);
}
