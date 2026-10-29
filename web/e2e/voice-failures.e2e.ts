import { expect, test } from "./fixtures";
import {
  LEARNER_QUESTION,
  PATIENT_REPLY,
  enterStation,
  sendText,
  strings,
} from "./station";

// Both voice providers fail; the text provider still answers.
test.use({
  harnessOptions: {
    mockTranscriptionFailureStatus: 500,
    mockSpeechFailureStatus: 500,
  },
});

test("a failed transcription falls back to text", async ({ page }) => {
  await enterStation(page);

  await page.getByRole("button", { name: strings.startVoiceInput }).click();
  const stop = page.getByRole("button", { name: strings.stopVoiceInput });
  await expect(stop).toBeVisible();
  await page.waitForTimeout(1_000);
  await stop.click();

  await expect(page.getByTestId("voice-fallback")).toHaveText(
    strings.voiceFallbackNotice,
  );
  await expect(page.getByTestId("message-learner")).toHaveCount(0);
  await expect(page.getByTestId("message-patient")).toHaveCount(0);

  await sendText(page, LEARNER_QUESTION);
  await expect(page.getByTestId("message-patient")).toHaveText(
    new RegExp(PATIENT_REPLY),
  );
});

test("a failed patient audio keeps the reply readable", async ({ page }) => {
  await enterStation(page);
  await sendText(page, LEARNER_QUESTION);

  const reply = page.getByTestId("message-patient");
  await expect(reply).toHaveText(new RegExp(PATIENT_REPLY));
  await reply.getByRole("button", { name: strings.playAudio }).click();

  // The reply loses its play control but stays on screen, and the station
  // goes on.
  await expect(reply.getByRole("button")).toHaveCount(0);
  await expect(reply).toHaveText(new RegExp(PATIENT_REPLY));
  await expect(page.getByTestId("station-screen")).toBeVisible();
  await expect(page.getByTestId("station-error")).toHaveCount(0);
});
