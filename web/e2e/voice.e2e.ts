import { expect, test } from "./fixtures";
import {
  PATIENT_REPLY,
  enterStation,
  strings,
} from "./station";

const TRANSCRIBED_QUESTION = "A dor irradia para algum lugar?";

test.use({ harnessOptions: { mockTranscriptionText: TRANSCRIBED_QUESTION } });

test("a recorded turn is transcribed and answered, and the reply plays", async ({
  page,
}) => {
  await enterStation(page);

  await page.getByRole("button", { name: strings.startVoiceInput }).click();
  const stop = page.getByRole("button", { name: strings.stopVoiceInput });
  await expect(stop).toBeVisible();
  // Let the fake microphone produce some audio before stopping.
  await page.waitForTimeout(1_000);
  await stop.click();

  await expect(page.getByTestId("message-learner")).toHaveText(
    new RegExp(TRANSCRIBED_QUESTION),
  );
  const reply = page.getByTestId("message-patient");
  await expect(reply).toHaveText(new RegExp(PATIENT_REPLY));
  await expect(page.getByTestId("voice-fallback")).toHaveCount(0);

  // Patient audio: the play control turns into a stop control while it
  // plays and back once the clip ends.
  await reply.getByRole("button", { name: strings.playAudio }).click();
  await expect(
    reply.getByRole("button", { name: strings.stopAudio }),
  ).toBeVisible();
  await expect(
    reply.getByRole("button", { name: strings.playAudio }),
  ).toBeVisible();
  await expect(page.getByTestId("station-error")).toHaveCount(0);
});
