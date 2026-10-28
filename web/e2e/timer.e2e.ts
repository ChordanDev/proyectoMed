import { expect, test } from "./fixtures";
import {
  LEARNER_QUESTION,
  PATIENT_REPLY,
  countdown,
  enterStation,
  persistedSessionId,
  remainingSeconds,
  restartStation,
  sendText,
  strings,
} from "./station";

const STATION_DURATION_MS = 8_000;

test.use({ harnessOptions: { stationDurationMs: STATION_DURATION_MS } });

test("the station finishes by timer when the countdown reaches zero", async ({
  page,
  stack,
}) => {
  await enterStation(page);
  const sessionId = await persistedSessionId(page);
  expect(await remainingSeconds(page)).toBeLessThanOrEqual(
    STATION_DURATION_MS / 1000,
  );

  await sendText(page, LEARNER_QUESTION);
  await expect(page.getByTestId("message-patient")).toHaveText(
    new RegExp(PATIENT_REPLY),
  );

  // No finish click: the authoritative deadline ends the station.
  await expect(
    page.getByRole("heading", { name: strings.resultReportTitle }),
  ).toBeVisible({ timeout: STATION_DURATION_MS + 30_000 });
  await expect(countdown(page)).toHaveCount(0);
  await expect(page.getByTestId("station-screen")).toHaveCount(0);

  await restartStation(page, stack, sessionId!);
});
