import { expect, test } from "./fixtures";
import { MICROPHONE_DENIED_ARGS } from "./media";
import {
  LEARNER_QUESTION,
  PATIENT_REPLY,
  enterStation,
  sendText,
  strings,
} from "./station";

test.use({ launchOptions: { args: MICROPHONE_DENIED_ARGS } });

test("a denied microphone falls back to text", async ({ page }) => {
  await enterStation(page);

  await page.getByRole("button", { name: strings.startVoiceInput }).click();

  await expect(page.getByTestId("voice-fallback")).toHaveText(
    strings.voiceFallbackNotice,
  );
  await expect(
    page.getByRole("button", { name: strings.startVoiceInput }),
  ).toHaveCount(0);
  await expect(page.getByTestId("message-learner")).toHaveCount(0);

  await sendText(page, LEARNER_QUESTION);
  await expect(page.getByTestId("message-patient")).toHaveText(
    new RegExp(PATIENT_REPLY),
  );
});
